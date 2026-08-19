import AppKit
import ImageIO
import SwiftUI
@preconcurrency import WebKit

/// Site icons for pages the user actually visited.
///
/// The privacy policy this type exists to enforce, in one place:
///
/// - An icon is fetched **only** while the user is visiting that site, from
///   that site's **own origin** — the icon the page itself declared
///   (`link[rel~="icon"]`/`apple-touch-icon`, resolved against the page URL),
///   or `/favicon.ico` on the same origin. A third-party favicon service is
///   never contacted; doing so would hand a log of the user's browsing to
///   somebody else, which is exactly what Clearframe promises not to do.
/// - A host that was never visited has no icon and never causes a request.
///   Bookmarks of unvisited sites keep the deterministic `IdentityColor`
///   square instead (see `SiteIconView`).
/// - Private tabs stay memory-only: nothing they load is written to disk.
/// - Everything stored is erased by `clearAll()`, which the local-data reset
///   calls alongside `BrowserDataStore.clearAllBrowserRecords()`.
///
/// Capture is best-effort and silent: short timeouts, one attempt per
/// navigation, failures remembered for the session only, and no UI anywhere
/// that reports a fetch succeeded or failed.
@MainActor
final class FaviconStore: ObservableObject {
    /// Injected so tests can drive capture without a network. Main-actor
    /// isolated to match the store, so a test fetcher's bookkeeping runs on
    /// the same actor as its assertions.
    typealias Fetcher = @MainActor (URL) async -> Data?

    /// Bumped when a newly stored icon becomes available, so views showing
    /// `SiteIconView` swap the fallback square for the real icon.
    @Published private(set) var revision = 0

    /// `nil` disables disk storage entirely (the caller could not resolve
    /// Application Support); capture then behaves like a private tab.
    private let directory: URL?
    private let fetch: Fetcher
    private let memory = NSCache<NSString, NSImage>()
    /// Hosts already looked for on disk and not found — keeps repeated view
    /// renders from re-reading a file that is not there.
    private var missingOnDisk: Set<String> = []
    /// Hosts whose capture failed in this run. Session-only and never
    /// persisted: a site that adds an icon tomorrow gets a fresh chance.
    private var failedThisSession: Set<String> = []
    private var inFlight: Set<String> = []

    init(
        directory: URL? = FaviconStore.defaultDirectory,
        fetch: @escaping Fetcher = FaviconStore.download
    ) {
        self.directory = directory
        self.fetch = fetch
        memory.countLimit = 300
    }

    // MARK: - Lookup

    /// The stored icon for `host`, from memory or disk. Never performs a
    /// network request: only an actual visit (`captureIfNeeded`) can fetch.
    func icon(forHost host: String) -> NSImage? {
        let key = IdentityColor.normalizedHost(host)
        guard !key.isEmpty else { return nil }
        if let cached = memory.object(forKey: key as NSString) { return cached }
        guard !missingOnDisk.contains(key),
              let fileURL = fileURL(forNormalizedHost: key),
              let data = try? Data(contentsOf: fileURL),
              let image = NSImage(data: data) else {
            missingOnDisk.insert(key)
            return nil
        }
        memory.setObject(image, forKey: key as NSString)
        return image
    }

    // MARK: - Capture

    /// Called from `BrowserSession`'s `didFinish` for the page just loaded.
    /// Reads the icon the live page declared, then stores the first
    /// same-origin candidate that resolves to an image.
    func captureIfNeeded(for pageURL: URL, in webView: WKWebView, isPrivate: Bool) async {
        guard let host = Self.captureHost(for: pageURL), shouldCapture(host: host) else { return }
        let declared = await declaredIconURLs(in: webView)
        await capture(pageURL: pageURL, declaredIconURLs: declared, isPrivate: isPrivate)
    }

    /// The capture step without WebKit, so the policy is unit-testable:
    /// `declaredIconURLs` is what the page declared, verbatim.
    func capture(pageURL: URL, declaredIconURLs: [String], isPrivate: Bool) async {
        guard let host = Self.captureHost(for: pageURL), shouldCapture(host: host) else { return }
        inFlight.insert(host)
        defer { inFlight.remove(host) }

        for candidate in Self.iconCandidates(for: pageURL, declared: declaredIconURLs) {
            guard let data = await fetch(candidate),
                  !data.isEmpty,
                  data.count <= Self.maximumDownloadBytes,
                  let png = Self.normalizedPNG(from: data),
                  png.count <= Self.maximumStoredBytes,
                  let image = NSImage(data: png) else { continue }
            memory.setObject(image, forKey: host as NSString)
            missingOnDisk.remove(host)
            // Private tabs keep the icon for the life of the tab's window and
            // leave nothing behind.
            if !isPrivate { writeToDisk(png, forNormalizedHost: host) }
            revision += 1
            return
        }
        failedThisSession.insert(host)
    }

    /// Erases every stored icon: the on-disk directory and the in-memory
    /// caches, including the session's negative results.
    func clearAll() {
        memory.removeAllObjects()
        missingOnDisk.removeAll()
        failedThisSession.removeAll()
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        revision += 1
    }

    // MARK: - Policy (pure, testable)

    /// The normalized cache key for a page Clearframe may capture an icon
    /// for, or `nil` for anything that is not an ordinary web page.
    nonisolated static func captureHost(for pageURL: URL) -> String? {
        guard let scheme = pageURL.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }
        let host = IdentityColor.normalizedHost(pageURL.host ?? "")
        return host.isEmpty ? nil : host
    }

    /// At most two same-origin candidates, in the order they are tried: the
    /// first icon the page declared for its own origin, then `/favicon.ico`
    /// on that origin. A declared icon hosted anywhere else — a CDN, an
    /// icon service, another one of the site's own subdomains — is dropped,
    /// because "the site the user is visiting" is the only origin this
    /// browser is willing to reveal the visit to.
    nonisolated static func iconCandidates(for pageURL: URL, declared: [String]) -> [URL] {
        guard let fallback = sameOriginFaviconURL(for: pageURL) else { return [] }
        var candidates: [URL] = []
        if let first = declared.lazy
            .compactMap({ URL(string: $0, relativeTo: pageURL)?.absoluteURL })
            .first(where: { isSameOrigin($0, as: pageURL) }) {
            candidates.append(first)
        }
        if !candidates.contains(fallback) { candidates.append(fallback) }
        return candidates
    }

    nonisolated static func isSameOrigin(_ url: URL, as pageURL: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return false }
        return scheme == pageURL.scheme?.lowercased()
            && url.host?.lowercased() == pageURL.host?.lowercased()
            && url.port == pageURL.port
    }

    /// The file name a normalized host is stored under. Restricted to
    /// characters that cannot escape the favicon directory or hide a file.
    nonisolated static func fileName(forNormalizedHost host: String) -> String? {
        guard !host.isEmpty else { return nil }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789.-")
        var name = String(host.prefix(120).map { allowed.contains($0) ? $0 : "_" })
        while name.hasPrefix(".") || name.hasPrefix("-") {
            name = "_" + name.dropFirst()
        }
        return name.isEmpty ? nil : name + ".png"
    }

    nonisolated static var defaultDirectory: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Clearframe", isDirectory: true)
            .appendingPathComponent("Favicons", isDirectory: true)
    }

    /// Raw bytes accepted from a site before the image is even decoded.
    nonisolated static let maximumDownloadBytes = 512 * 1024
    /// Ceiling on what is written per host after downscaling. A 64×64 PNG is
    /// far below this; the cap exists so a pathological encode cannot fill
    /// the user's disk.
    nonisolated static let maximumStoredBytes = 256 * 1024
    nonisolated static let storedPixelSize = 64

    // MARK: - Internals

    private func shouldCapture(host: String) -> Bool {
        guard !inFlight.contains(host), !failedThisSession.contains(host) else { return false }
        return icon(forHost: host) == nil
    }

    private func fileURL(forNormalizedHost host: String) -> URL? {
        guard let directory, let name = Self.fileName(forNormalizedHost: host) else { return nil }
        return directory.appendingPathComponent(name, isDirectory: false)
    }

    private func writeToDisk(_ png: Data, forNormalizedHost host: String) {
        guard let directory, let fileURL = fileURL(forNormalizedHost: host) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? png.write(to: fileURL, options: .atomic)
    }

    /// Reads what the live document declared. Failures return no candidates,
    /// which leaves only the same-origin `/favicon.ico` attempt.
    private func declaredIconURLs(in webView: WKWebView) async -> [String] {
        let value: Any? = await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(Self.iconLinkScript) { value, _ in
                continuation.resume(returning: value)
            }
        }
        return (value as? [Any])?.compactMap { $0 as? String } ?? []
    }

    private static let iconLinkScript = #"""
    (() => {
      const wanted = ['icon', 'shortcut', 'apple-touch-icon', 'apple-touch-icon-precomposed'];
      const found = [];
      document.querySelectorAll('link[rel][href]').forEach(link => {
        if (found.length >= 8) return;
        const rel = (link.getAttribute('rel') || '').toLowerCase().split(/\s+/);
        if (!rel.some(value => wanted.includes(value))) return;
        try {
          found.push(new URL(link.getAttribute('href'), document.baseURI).href);
        } catch (error) {}
      });
      return found;
    })()
    """#

    private nonisolated static func sameOriginFaviconURL(for pageURL: URL) -> URL? {
        guard let scheme = pageURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = pageURL.host, !host.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        // Hosts are case-insensitive; asking for one spelling keeps the
        // request identical however the user typed the address.
        components.host = host.lowercased()
        components.port = pageURL.port
        components.path = "/favicon.ico"
        return components.url
    }

    /// Downscales whatever the site returned — PNG, ICO with several sizes,
    /// JPEG — to a single small PNG. Anything ImageIO cannot decode (an SVG
    /// icon, an HTML error page served with a 200) simply becomes a miss.
    nonisolated static func normalizedPNG(from data: Data, maximumPixelSize: Int = storedPixelSize) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        // An .ico bundles several sizes and does not promise the largest is
        // first; picking the largest keeps the 64pt render sharp.
        var bestIndex = 0
        var bestPixels = 0
        for index in 0..<min(count, 12) {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else { continue }
            let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
            let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
            if width * height > bestPixels {
                bestPixels = width * height
                bestIndex = index
            }
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, bestIndex, options as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// The shipped fetcher. Ephemeral session, no cookies, short timeouts,
    /// and no redirect to a different origin is ever followed to disk — a
    /// redirect that leaves the origin simply produces bytes we then treat
    /// like any other response for the visited host.
    static func download(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeout
        request.httpShouldHandleCookies = false
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private static let requestTimeout: TimeInterval = 5

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()
}

// MARK: - Site icon view

private struct FaviconStoreKey: EnvironmentKey {
    static let defaultValue: FaviconStore? = nil
}

extension EnvironmentValues {
    /// Injected once, by `BrowserView`. Optional on purpose: a view rendered
    /// without a store (a preview, a test host) still draws its fallback
    /// square instead of crashing.
    var faviconStore: FaviconStore? {
        get { self[FaviconStoreKey.self] }
        set { self[FaviconStoreKey.self] = newValue }
    }
}

/// A site's mark at chip scale: the real icon when Clearframe captured one
/// during a visit, otherwise the deterministic `IdentityColor` square. A
/// square rather than a dot because at 13pt it reads as an icon slot, so a
/// site with an icon and one without sit on the same grid.
///
/// Rendering never triggers a fetch — only `FaviconStore.captureIfNeeded`
/// does, and only for the page being visited.
struct SiteIconView: View {
    let host: String
    var size: CGFloat = ClearframeTheme.siteIconSize
    @Environment(\.faviconStore) private var store

    init(host: String, size: CGFloat = ClearframeTheme.siteIconSize) {
        self.host = host
        self.size = size
    }

    init(urlString: String, size: CGFloat = ClearframeTheme.siteIconSize) {
        self.init(host: URL(string: urlString)?.host ?? "", size: size)
    }

    var body: some View {
        Group {
            if let store {
                StoredSiteIcon(store: store, host: host, size: size)
            } else {
                SiteIconFallback(host: host, size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Split out so the icon redraws when a capture completes: `@ObservedObject`
/// needs a concrete view identity to subscribe from.
private struct StoredSiteIcon: View {
    @ObservedObject var store: FaviconStore
    let host: String
    let size: CGFloat

    var body: some View {
        if let icon = store.icon(forHost: host) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: SiteIconFallback.cornerRadius, style: .continuous))
        } else {
            SiteIconFallback(host: host, size: size)
        }
    }
}

private struct SiteIconFallback: View {
    static let cornerRadius: CGFloat = 4

    let host: String
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            .fill(IdentityColor.color(forHost: host))
            .frame(width: size, height: size)
    }
}
