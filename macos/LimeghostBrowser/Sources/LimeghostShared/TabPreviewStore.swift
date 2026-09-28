import Combine
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A picture of what each open tab last showed, for the phone's tab switcher.
///
/// **An ordinary tab's preview is kept; a private tab's never is.** That is the
/// same policy `FaviconStore` follows, and the line matters more here than it
/// does there:
///
/// - A private tab's whole promise is that nothing it loads reaches the disk.
///   Its WebKit store is non-persistent, so no cookie, no cache and no history
///   entry survives it. A preserved preview would be the *only* trace left
///   behind — not merely inconsistent, a hole. This type therefore takes
///   `isPrivate` at the moment of storing and never writes one.
/// - An ordinary tab's preview was memory-only too until September 28, 2026, on
///   the reasoning that a photograph of a page is a different kind of thing to
///   leave behind than a site's mark. That was defensible and was too strict:
///   the same container already holds WebKit's own cache of the page, the
///   history and the cookies, so a hard line at "no page pictures" was drawn
///   where more revealing data already sat. The founder quit the app, lost
///   eleven cards, and the trade stopped looking worth it.
///
/// Kept in **Caches**, not Application Support, for three reasons that all
/// point the same way: a preview can always be taken again, iOS may purge the
/// directory under pressure rather than killing the app, and a caches folder is
/// left out of backups — so the pictures do not travel to a computer or to
/// iCloud.
///
/// Holds `CGImage`, not the platform's own image type, for the reason
/// `FaviconStore` records above its ImageIO helpers: `takeSnapshot` hands back
/// an `NSImage` on the Mac and a `UIImage` on the phone, and neither belongs in
/// a shared file. Capture happens on the platform side and converts.
@MainActor
public final class TabPreviewStore: ObservableObject {
    /// Bumped whenever a preview is stored or dropped.
    ///
    /// An `NSCache` mutating tells SwiftUI nothing by itself, so the grid would
    /// keep drawing yesterday's squares. `FaviconStore` publishes a counter for
    /// the same reason.
    @Published public private(set) var revision = 0

    /// The width, in pixels, previews are asked for at.
    ///
    /// A card is about 173 points wide, so this is a little over two points per
    /// pixel — enough not to look soft on a 3× screen, and far short of the
    /// megabytes a full-resolution page image would cost. WebKit renders
    /// straight to this width when asked, so nothing is captured large and then
    /// thrown away.
    public static let captureWidth: CGFloat = 400

    /// `nil` keeps everything in memory, which is what a test wants and what a
    /// caller gets when Caches cannot be resolved.
    private let directory: URL?
    private let memory = NSCache<NSUUID, CGImage>()
    /// Tabs already looked for on disk and not found. Without it every card of
    /// an unseen tab re-reads a file that is not there, on every redraw.
    private var missing: Set<UUID> = []

    public init(
        directory: URL? = TabPreviewStore.defaultDirectory,
        limit: Int = 16,
        byteLimit: Int = 24 * 1024 * 1024
    ) {
        self.directory = directory
        memory.countLimit = limit
        memory.totalCostLimit = byteLimit
    }

    public func preview(for tabID: UUID) -> CGImage? {
        if let held = memory.object(forKey: tabID as NSUUID) { return held }
        guard !missing.contains(tabID), let url = fileURL(for: tabID) else { return nil }
        guard let data = try? Data(contentsOf: url), let image = Self.image(from: data) else {
            missing.insert(tabID)
            return nil
        }
        memory.setObject(image, forKey: tabID as NSUUID, cost: Self.byteCost(of: image))
        return image
    }

    /// - Parameter isPrivate: a private tab's picture is held for as long as the
    ///   tab lives and written nowhere. Passed at the moment of storing rather
    ///   than remembered per tab, so there is no state to get out of step with
    ///   the tab it describes.
    public func store(_ image: CGImage, for tabID: UUID, isPrivate: Bool) {
        memory.setObject(image, forKey: tabID as NSUUID, cost: Self.byteCost(of: image))
        missing.remove(tabID)
        revision += 1
        guard !isPrivate, let url = fileURL(for: tabID), let data = Self.jpegData(from: image) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    /// Called when a tab closes: its picture has no reader left.
    public func forget(_ tabID: UUID) {
        memory.removeObject(forKey: tabID as NSUUID)
        missing.insert(tabID)
        if let url = fileURL(for: tabID) { try? FileManager.default.removeItem(at: url) }
        revision += 1
    }

    /// Called by the local-data reset, beside `FaviconStore.clearAll()`.
    public func clearAll() {
        memory.removeAllObjects()
        missing.removeAll()
        if let directory { try? FileManager.default.removeItem(at: directory) }
        revision += 1
    }

    /// `Caches`, not Application Support: a preview can be taken again, so iOS
    /// may purge this under pressure instead of ending the app, and a caches
    /// folder is left out of device backups.
    public nonisolated static var defaultDirectory: URL? {
        try? FileManager.default
            .url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("Limeghost", isDirectory: true)
            .appendingPathComponent("TabPreviews", isDirectory: true)
    }

    /// A tab's identifier is a UUID, whose text is hex and hyphens only — so
    /// unlike a site's host it needs no sanitising and can name no file but its
    /// own.
    private func fileURL(for tabID: UUID) -> URL? {
        directory?.appendingPathComponent("\(tabID.uuidString).jpg")
    }

    /// JPEG rather than PNG: a page is a photograph, and the same picture costs
    /// tens of kilobytes here against hundreds as PNG, on a device where twelve
    /// of them share a caches folder.
    nonisolated static func jpegData(from image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    nonisolated static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// What one preview costs the cache. `bytesPerRow` rather than
    /// `width * 4`: a `CGImage` row is padded to an alignment WebKit chooses,
    /// so the multiplication would under-count every image.
    private nonisolated static func byteCost(of image: CGImage) -> Int {
        image.bytesPerRow * image.height
    }
}
