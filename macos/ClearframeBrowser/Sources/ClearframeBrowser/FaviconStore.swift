import AppKit
import ImageIO
import SwiftUI
@preconcurrency import WebKit

/// Site icons for pages the user actually visited.
///
/// The privacy policy this type exists to enforce, in one place:
///
/// - An icon is fetched **only** while the user is visiting that site — the
///   icon the page itself declared (`link[rel~="icon"]`/`apple-touch-icon`),
///   or `/favicon.ico` on its own origin.
/// - The hosts that may be asked are the page's own origin, and any host the
///   page *itself already loaded something from during this visit* — which is
///   how most large sites actually serve their icon: from their own CDN,
///   which delivered the page's scripts seconds earlier and therefore already
///   knows about the visit. One further cookie-free request for an image
///   tells it nothing it does not already have.
/// - **A third-party favicon service is never contacted**, and cannot be:
///   nothing on any page is ever loaded from one, so no such host can pass the
///   test above. That is the promise this exists to keep — stated in terms of
///   who learns about the visit rather than of a single address, because the
///   address-only form was never quite true. `/favicon.ico` follows redirects,
///   so a site could always send this fetch to a host of its choosing simply
///   by answering with one.
/// - When a visit **redirects**, the host it started at is recorded as
///   ending up at the host it finished at, so a bookmark saved at the
///   redirecting address can find the icon. Read from a redirect the user's
///   own navigation already followed — no extra request of any kind. Chrome
///   and Firefox both do this; without it such a bookmark can never show an
///   icon however often it is opened.
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
    /// Hosts that redirect somewhere else, pointing at the host whose icon
    /// they should borrow: `pinterest.co.uk` → `uk.pinterest.com`.
    ///
    /// Learned only from a redirect the person's own navigation already
    /// followed, so it costs no request. Without it a bookmark saved at the
    /// address that redirects can never show an icon, however many times it
    /// is opened: the icon is filed under where the page ended up, and the
    /// bookmark keeps asking for where it started.
    ///
    /// Chrome and Firefox both do this — Chrome maps a captured icon onto
    /// every URL in the redirect chain, Firefox attaches it to the redirect
    /// sources, prioritising bookmarked ones.
    private var aliases: [String: String] = [:]

    init(
        directory: URL? = FaviconStore.defaultDirectory,
        fetch: @escaping Fetcher = FaviconStore.download
    ) {
        self.directory = directory
        self.fetch = fetch
        memory.countLimit = 300
        aliases = Self.loadAliases(in: directory)
    }

    // MARK: - Lookup

    /// The stored icon for `host`, from memory or disk. Never performs a
    /// network request: only an actual visit (`captureIfNeeded`) can fetch.
    ///
    /// A host's own icon always wins. Only when it has none is a redirect
    /// alias followed — so an icon captured directly can never be displaced
    /// by one borrowed from somewhere a host happened to redirect to.
    func icon(forHost host: String) -> NSImage? {
        let key = IdentityColor.normalizedHost(host)
        guard !key.isEmpty else { return nil }
        if let own = storedIcon(forNormalizedHost: key) { return own }
        // One hop only. A chain of aliases would be a way to loop.
        guard let target = aliases[key], target != key else { return nil }
        return storedIcon(forNormalizedHost: target)
    }

    private func storedIcon(forNormalizedHost key: String) -> NSImage? {
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
    /// `requestedURL` is the address the navigation started at, which differs
    /// from `pageURL` when the site redirected. Passing it lets the icon be
    /// found later under the address a bookmark actually holds.
    func captureIfNeeded(for pageURL: URL, requestedURL: URL?, in webView: WKWebView, isPrivate: Bool) async {
        guard let host = Self.captureHost(for: pageURL) else { return }
        recordRedirectAlias(from: requestedURL, to: host, isPrivate: isPrivate)
        guard shouldCapture(host: host) else { return }
        let declared = await declaredIconURLs(in: webView)
        await capture(pageURL: pageURL, declaredIconURLs: declared, isPrivate: isPrivate)
    }

    /// Remembers that `requestedURL`'s host ends up at `finalHost`.
    ///
    /// Last-write-wins, which is how this heals itself: a bookmark that
    /// happens to land on a sign-in page today borrows that icon until the
    /// next visit reaches the real page and overwrites it. Chrome accepts the
    /// same trade and re-propagates on every visit for the same reason.
    ///
    /// Deliberately no "only within the same registered domain" guard. The
    /// case this exists for — `pinterest.co.uk` redirecting to
    /// `uk.pinterest.com` — crosses registrable domains, so such a guard
    /// would rule out exactly the thing it is meant to fix.
    func recordRedirectAlias(from requestedURL: URL?, to finalHost: String, isPrivate: Bool) {
        guard let requestedURL, let requestedHost = Self.captureHost(for: requestedURL), requestedHost != finalHost
        else { return }
        guard aliases[requestedHost] != finalHost else { return }
        aliases[requestedHost] = finalHost
        // A host that had nothing may now resolve through the alias.
        missingOnDisk.remove(requestedHost)
        revision += 1
        // Private tabs leave nothing behind, aliases included.
        if !isPrivate { writeAliases() }
    }

    /// The capture step without WebKit, so the policy is unit-testable:
    /// `declaredIconURLs` is what the page declared, verbatim.
    func capture(pageURL: URL, declaredIconURLs: PageIcons, isPrivate: Bool) async {
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
        aliases.removeAll()
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

    /// One icon the page declared for itself.
    struct DeclaredIcon: Equatable, Sendable {
        let url: String
        /// The `rel` value, lowercased — `icon`, `apple-touch-icon`, and so on.
        let rel: String
        /// The `sizes` attribute verbatim, empty when the page declared none.
        let sizes: String
        /// The `media` attribute verbatim, empty when the page declared none.
        /// Sites increasingly ship two icons — a dark mark for light
        /// backgrounds and a light one for dark — and distinguish them only
        /// here.
        let media: String

        var isAppleTouch: Bool { rel.contains("apple-touch-icon") }

        /// How well this icon suits Clearframe's own chrome, which is always
        /// dark. Lower is better.
        ///
        /// An icon a site declared *for light backgrounds* is usually a dark
        /// mark, and drawing it on a dark tab strip makes it a black square —
        /// which is exactly what Google Flow's `flow_favicon_b.png` did.
        var appearanceScore: Int {
            let value = media.lowercased()
            guard value.contains("prefers-color-scheme") else { return 1 } // Declared for everywhere.
            if value.contains("dark") { return 0 }
            if value.contains("light") { return 2 }
            return 1
        }
        var isSVG: Bool { url.lowercased().hasSuffix(".svg") }

        /// The largest square edge the page claims, or `nil` for none and for
        /// `sizes="any"` — which says scalable rather than a measurement.
        var declaredEdge: Int? {
            sizes.lowercased()
                .split(whereSeparator: { $0 == " " || $0 == "," })
                .compactMap { token -> Int? in
                    guard let x = token.firstIndex(where: { $0 == "x" || $0 == "×" }) else { return nil }
                    return Int(token[token.index(after: x)...])
                }
                .max()
        }
    }

    /// What one page said about its own icons, and which hosts it had already
    /// loaded something from by the time it was asked.
    struct PageIcons: Equatable, Sendable {
        var icons: [DeclaredIcon] = []
        /// Lowercased hostnames this page already fetched a resource from
        /// during this visit. Reachability is decided against this and nothing
        /// else — see `iconCandidates`.
        var contactedHosts: Set<String> = []
    }

    /// The addresses worth trying for one page's icon, best first, at most
    /// four.
    ///
    /// **Which hosts may be asked.** The page's own origin always. Beyond it,
    /// only a host the page *itself already loaded something from during this
    /// visit* — which is how the icons of most large sites are actually
    /// served: the site's own CDN, which delivered its scripts and images
    /// seconds earlier and therefore already knows about the visit. Asking it
    /// for one more image, without cookies, discloses nothing it does not
    /// already have.
    ///
    /// A favicon service can never satisfy that test, because nothing on the
    /// page was ever loaded from one — which is the promise this rule exists
    /// to keep, stated in terms of who learns about the visit rather than of
    /// a single address. The address-only form was always approximate anyway:
    /// `/favicon.ico` follows redirects, so a site could already send this
    /// fetch to another host of its choosing simply by answering with one.
    ///
    /// **Which is tried first.** The site's own origin before a CDN; a bitmap
    /// close to the stored size before a far one; a bitmap before an SVG,
    /// because a page that offers both usually offers the SVG first and only
    /// the bitmap can be decoded today. `/favicon.ico` last, as the guess it
    /// is.
    nonisolated static func iconCandidates(for pageURL: URL, declared: PageIcons) -> [URL] {
        guard let fallback = sameOriginFaviconURL(for: pageURL) else { return [] }

        let ranked = declared.icons
            .compactMap { icon -> (URL, DeclaredIcon)? in
                guard let url = URL(string: icon.url, relativeTo: pageURL)?.absoluteURL,
                      isReachable(url, from: pageURL, contactedHosts: declared.contactedHosts)
                else { return nil }
                return (url, icon)
            }
            .enumerated()
            .sorted { left, right in
                let (l, r) = (left.element.1, right.element.1)
                let lOwn = isSameOrigin(left.element.0, as: pageURL)
                let rOwn = isSameOrigin(right.element.0, as: pageURL)
                if lOwn != rOwn { return lOwn }
                if l.appearanceScore != r.appearanceScore { return l.appearanceScore < r.appearanceScore }
                if l.isSVG != r.isSVG { return r.isSVG }
                let lScore = sizeScore(l), rScore = sizeScore(r)
                if lScore != rScore { return lScore < rScore }
                if l.isAppleTouch != r.isAppleTouch { return r.isAppleTouch }
                // Declaration order decides the rest, so the result never
                // depends on how the page happened to be walked.
                return left.offset < right.offset
            }
            .map(\.element.0)

        var candidates: [URL] = []
        for url in ranked where !candidates.contains(url) {
            candidates.append(url)
            if candidates.count == maximumCandidates - 1 { break }
        }
        if !candidates.contains(fallback) { candidates.append(fallback) }
        return candidates
    }

    /// Lower sorts first. An icon at least as big as what is stored beats a
    /// smaller one — downscaling keeps detail, upscaling invents it — and an
    /// undeclared size sits between the two, since it is usually 16px but
    /// might not be.
    private nonisolated static func sizeScore(_ icon: DeclaredIcon) -> Int {
        guard let edge = icon.declaredEdge else { return 1_000 }
        return edge >= storedPixelSize ? edge - storedPixelSize : 2_000 + (storedPixelSize - edge)
    }

    /// Whether this browser is willing to ask `url`'s host for an icon while
    /// visiting `pageURL`. See `iconCandidates` for why the page's own
    /// contacts are the boundary.
    nonisolated static func isReachable(_ url: URL, from pageURL: URL, contactedHosts: Set<String>) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return false }
        if isSameOrigin(url, as: pageURL) { return true }
        // A plain-http icon is never worth reaching off-origin for.
        guard scheme == "https", let host = url.host?.lowercased(), !host.isEmpty else { return false }
        return contactedHosts.contains(host)
    }

    /// Four addresses, of which the last is always `/favicon.ico`. Chromium
    /// usually downloads one or two; this is generous and still bounded.
    nonisolated static let maximumCandidates = 4

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

    /// The alias table sits beside the icons, so the browsing-data reset —
    /// which deletes the whole directory — takes it too.
    private static func aliasFileURL(in directory: URL?) -> URL? {
        directory?.appendingPathComponent("redirects.json", isDirectory: false)
    }

    private static func loadAliases(in directory: URL?) -> [String: String] {
        guard let url = aliasFileURL(in: directory),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return decoded
    }

    private func writeAliases() {
        guard let directory, let url = Self.aliasFileURL(in: directory),
              let data = try? JSONEncoder().encode(aliases) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private func writeToDisk(_ png: Data, forNormalizedHost host: String) {
        guard let directory, let fileURL = fileURL(forNormalizedHost: host) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? png.write(to: fileURL, options: .atomic)
    }

    /// Reads what the live document declared. Failures return no candidates,
    /// which leaves only the same-origin `/favicon.ico` attempt.
    private func declaredIconURLs(in webView: WKWebView) async -> PageIcons {
        let value: Any? = await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(Self.iconLinkScript) { value, _ in
                continuation.resume(returning: value)
            }
        }
        guard let payload = value as? [String: Any] else { return PageIcons() }
        let icons = (payload["icons"] as? [[String: Any]] ?? []).compactMap { entry -> DeclaredIcon? in
            guard let url = entry["href"] as? String, !url.isEmpty else { return nil }
            return DeclaredIcon(
                url: url,
                rel: (entry["rel"] as? String ?? "").lowercased(),
                sizes: entry["sizes"] as? String ?? "",
                media: entry["media"] as? String ?? ""
            )
        }
        let hosts = Set((payload["hosts"] as? [String] ?? []).map { $0.lowercased() }.filter { !$0.isEmpty })
        return PageIcons(icons: icons, contactedHosts: hosts)
    }

    /// Reads what the page declared, and which hosts it has already fetched
    /// something from. Both come from the page itself: the second is the
    /// browser's own resource timing, which is a record of loads that already
    /// happened rather than anything new.
    private static let iconLinkScript = #"""
    (() => {
      const wanted = ['icon', 'shortcut', 'apple-touch-icon', 'apple-touch-icon-precomposed'];
      const icons = [];
      document.querySelectorAll('link[rel][href]').forEach(link => {
        if (icons.length >= 8) return;
        const rel = (link.getAttribute('rel') || '').toLowerCase();
        if (!rel.split(/\s+/).some(value => wanted.includes(value))) return;
        try {
          icons.push({
            href: new URL(link.getAttribute('href'), document.baseURI).href,
            rel: rel,
            sizes: (link.getAttribute('sizes') || ''),
            media: (link.getAttribute('media') || '')
          });
        } catch (error) {}
      });
      const hosts = new Set();
      try {
        performance.getEntriesByType('resource').forEach(entry => {
          if (hosts.size >= 64) return;
          try {
            const url = new URL(entry.name);
            if (url.protocol === 'https:') { hosts.add(url.hostname.toLowerCase()); }
          } catch (error) {}
        });
      } catch (error) {}
      return { icons: icons, hosts: Array.from(hosts) };
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
            guard !isHTML(response: http, body: data) else { return nil }
            return data
        } catch {
            return nil
        }
    }

    /// Whether a 200 is really a web page. Single-page apps commonly answer
    /// every unmatched path with their own shell, so `/favicon.ico` comes back
    /// as a perfectly successful HTML document. Decoding it would fail anyway;
    /// recognising it here says so without the work, and keeps "this site
    /// serves a page, not an icon" a distinct outcome rather than a decode
    /// error.
    ///
    /// Only HTML is rejected, never "not an image": plenty of servers hand
    /// icons back as `text/plain` or `application/octet-stream`, and those are
    /// fine to try.
    nonisolated static func isHTML(response: HTTPURLResponse, body: Data) -> Bool {
        if let type = response.mimeType?.lowercased(),
           type.hasPrefix("text/html") || type.hasPrefix("application/xhtml") {
            return true
        }
        // Some servers send no usable type at all, so the first bytes decide.
        let prefix = String(decoding: body.prefix(64), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return prefix.hasPrefix("<!doctype html") || prefix.hasPrefix("<html")
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
    /// Decorative by default: the icon sits beside a title that already says
    /// which site this is, so announcing it again is noise. A caller that
    /// shows the icon *instead* of a title — a pinned tab — passes the name
    /// here, so the icon is not hidden outright. Note that the name does not
    /// currently survive as the element's label from a pinned chip; see
    /// `TabChip.pinnedChip`.
    var accessibilityName: String?
    @Environment(\.faviconStore) private var store

    init(host: String, size: CGFloat = ClearframeTheme.siteIconSize, accessibilityName: String? = nil) {
        self.host = host
        self.size = size
        self.accessibilityName = accessibilityName
    }

    init(urlString: String, size: CGFloat = ClearframeTheme.siteIconSize, accessibilityName: String? = nil) {
        self.init(
            host: URL(string: urlString)?.host ?? "",
            size: size,
            accessibilityName: accessibilityName
        )
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
        .accessibilityHidden(accessibilityName == nil)
        .accessibilityLabel(accessibilityName ?? "")
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
                // `fit`, not `fill`: a site's icon is not always square —
                // Google Flow's is 653x524 — and filling a square slot with
                // one crops its sides away and upscales what is left into a
                // blur. Fitting shows all of it. For the square icons that
                // are the norm the two are identical.
                .aspectRatio(contentMode: .fit)
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
