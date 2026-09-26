import Combine
import CoreGraphics
import Foundation

/// A picture of what each open tab last showed, for the phone's tab switcher.
///
/// **Nothing here is ever written to disk, for any tab** — not even an
/// ordinary one. That is stricter than `FaviconStore`, which does cache to
/// disk, and the difference is the point:
///
/// - A favicon is a *site's mark*, keyed by host. It is the same picture for
///   everyone who loads that site, and it says only that the site was
///   visited.
/// - A preview is keyed by *tab* and is a photograph of what that page showed
///   this person — a balance, a result, a half-written message. A folder of
///   those surviving a relaunch is a different kind of thing to leave behind.
///
/// The workspace already draws this line for the same reason: closed tabs are
/// remembered in memory only, because one reappearing after a relaunch is a
/// surprise and for a private tab it would be a leak. Previews follow the
/// stricter neighbour, not the looser one.
///
/// Because nothing is stored, private and ordinary tabs need no separate
/// treatment here and this type takes no `isPrivate` anywhere: a private tab's
/// preview lives exactly as long as the web view that drew it, which is the
/// promise private browsing already makes.
///
/// What that costs is one relaunch: the switcher shows identity squares until
/// each tab has been looked at once. Restored tabs are deferred and have not
/// loaded yet, so for most of them there would be nothing truthful to show.
///
/// Holds `CGImage`, not the platform's own image type, for the reason
/// `FaviconStore` records above its ImageIO helpers: `takeSnapshot` hands back
/// an `NSImage` on the Mac and a `UIImage` on the phone, and neither belongs
/// in a shared file. Capture happens on the platform side and converts.
@MainActor
public final class TabPreviewStore: ObservableObject {
    /// Bumped whenever a preview is stored or dropped.
    ///
    /// An `NSCache` mutating tells SwiftUI nothing by itself, so the grid
    /// would keep drawing yesterday's squares. `FaviconStore` publishes a
    /// counter for the same reason.
    @Published public private(set) var revision = 0

    /// The width, in pixels, previews are asked for at.
    ///
    /// A card is about 173 points wide, so this is a little over two points
    /// per pixel — enough not to look soft on a 3× screen, and far short of
    /// the megabytes a full-resolution page image would cost. WebKit renders
    /// straight to this width when asked, so nothing is captured large and
    /// then thrown away.
    public static let captureWidth: CGFloat = 400

    private let memory = NSCache<NSUUID, CGImage>()

    /// - Parameters:
    ///   - limit: how many previews to keep. Above this the cache drops the
    ///     least useful, and the card falls back to its identity square —
    ///     which is what an unseen tab shows anyway, so nothing looks broken.
    ///   - byteLimit: a second ceiling in bytes, because `limit` alone cannot
    ///     bound a grid of large images.
    public init(limit: Int = 16, byteLimit: Int = 24 * 1024 * 1024) {
        memory.countLimit = limit
        memory.totalCostLimit = byteLimit
    }

    public func preview(for tabID: UUID) -> CGImage? {
        memory.object(forKey: tabID as NSUUID)
    }

    public func store(_ image: CGImage, for tabID: UUID) {
        memory.setObject(image, forKey: tabID as NSUUID, cost: Self.byteCost(of: image))
        revision += 1
    }

    /// Called when a tab closes: its picture has no reader left.
    public func forget(_ tabID: UUID) {
        memory.removeObject(forKey: tabID as NSUUID)
        revision += 1
    }

    /// Called by the local-data reset, beside `FaviconStore.clearAll()`.
    public func clearAll() {
        memory.removeAllObjects()
        revision += 1
    }

    /// What one preview costs the cache. `bytesPerRow` rather than
    /// `width * 4`: a `CGImage` row is padded to an alignment WebKit chooses,
    /// so the multiplication would under-count every image.
    private nonisolated static func byteCost(of image: CGImage) -> Int {
        image.bytesPerRow * image.height
    }
}
