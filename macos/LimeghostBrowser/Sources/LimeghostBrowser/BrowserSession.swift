import LimeghostCore
import AppKit
import Combine
import Foundation
@preconcurrency import WebKit

enum BrowserFailureKind: Equatable {
    case offline
    case timedOut
    case cannotReachHost
    case blocked
    case other
}

struct BrowserFailure: Equatable {
    let kind: BrowserFailureKind
    let title: String
    let message: String
    let retryable: Bool
}

enum BrowserLoadState: Equatable {
    case startPage
    case loading
    case content
    case failed(BrowserFailure)

    /// Whether there is a real web document in front of the reader.
    ///
    /// The page actions that read a page — Reader, and anything added beside it
    /// — belong only here. On a start surface there is no document to extract,
    /// and on a failure there is nothing but the error Limeghost drew itself.
    var showsLoadedPage: Bool {
        switch self {
        case .content, .loading: return true
        case .startPage, .failed: return false
        }
    }
}

@MainActor
final class BrowserSession: NSObject, ObservableObject {
    /// Stable identity for SwiftUI, which needs to know when the session behind
    /// a view has been replaced.
    ///
    /// Not `ObjectIdentifier`: that is the object's address, and an address is
    /// reused once the object at it is freed. Tearing a session down and
    /// building another for the same assistant is exactly the case where malloc
    /// is likely to hand back the block it just took — SwiftUI would read the
    /// same identity, keep the view it already had, and show a torn-down web
    /// view forever.
    let instanceID = UUID()
    let webView: WKWebView
    let downloadCenter: DownloadCenter
    let searchSettings: SearchSettingsStore
    let isPrivate: Bool

    @Published private(set) var currentURLString = ""
    @Published private(set) var pageTitle = "New Page"
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var estimatedProgress = 0.0
    @Published private(set) var navigationVersion = 0
    @Published private(set) var loadState: BrowserLoadState = .startPage
    @Published private(set) var hasCommittedNavigation = false
    /// Whether the web view still holds a page from an earlier navigation.
    /// While it does, following a link must leave it on screen: covering it
    /// with a progress card is something no other browser does, and it hides
    /// the page the reader was still reading.
    @Published private(set) var hasRenderedPage = false
    /// Mirrors `webView.pageZoom` so the chrome and tests can read the current
    /// step. Per tab, and deliberately not stored: a site's zoom is not
    /// remembered between tabs or between launches.
    /// Starts at the size chosen in Settings → General rather than at 1.0, so
    /// somebody who reads at 125% gets it on every page instead of pressing ⌘+
    /// on each one. ⌘0 still returns to 100%: the preference is where pages
    /// open, not a floor under them.
    @Published private(set) var pageZoom: CGFloat
    /// A link Limeghost declined to open, stated as a dismissible line above
    /// the page. Refusing a link must never take away the page the reader is
    /// on, so this never touches `loadState`.
    @Published private(set) var linkNotice: String?
    /// A short sentence about the page itself, shown in the same bar and dismissed
    /// the same way. Used when copying a page has a caveat worth one line — the
    /// extractor was unsure, or the page is a list rather than an article. Silence
    /// is the normal case: a notice that appears every time is one nobody reads.
    @Published private(set) var pageNotice: String?
    /// How the connection to the current page actually stands, from the scheme
    /// *and* from WebKit's own report of whether everything on the page arrived
    /// encrypted. Published so the address chip and the site information
    /// popover can never disagree about the same page.
    @Published private(set) var connectionSecurity: ConnectionSecurity = .noPage

    /// `nil` opens an empty tab: a popup script may set the location later.
    var onRequestNewTab: ((URL?) -> Void)?
    /// Builds the tab a `window.open()` popup will live in and returns the web
    /// view that tab adopted, so WebKit can drive that exact instance and keep
    /// `window.opener` connected to the page that opened it.
    var onRequestPopupWebView: ((WKWebViewConfiguration) -> WKWebView?)?
    var onCompletedVisit: ((String, String) -> Void)?
    /// How a `mailto:`/`tel:` link reaches the app that owns it. Injectable so
    /// the smoke suite can prove the page survives the hand-off without
    /// launching the tester's mail client.
    var openExternalScheme: (URL) -> Void = { NSWorkspace.shared.open($0) }

    private var isShowingStartPage = true
    private var lastRequestedURL: URL?
    /// Where the navigation now in flight began, before any redirect.
    ///
    /// Separate from `lastRequestedURL`, which does not survive a redirect —
    /// once the site sends the browser somewhere else, that becomes the new
    /// address. This is written once when a navigation starts and then left
    /// alone, which is what makes it possible to tell afterwards that
    /// `pinterest.co.uk` is where the visit to `uk.pinterest.com` came from.
    private var navigationOriginURL: URL?
    private var lastCommittedWebURL: URL?
    private var navigationDisplayName: String?
    private var activeNavigation: WKNavigation?
    private var lastObservedWebURLString: String?
    private var lastVersionedStandardNavigationURLString: String?
    private var webViewSubscriptions: Set<AnyCancellable> = []
    private var appearanceObservation: NSKeyValueObservation?
    private let contentBlocking: ContentRuleListProvider?
    private let favicons: FaviconStore?
    private var faviconTask: Task<Void, Never>?
    private var linkNoticeTask: Task<Void, Never>?
    private var pageNoticeTask: Task<Void, Never>?

    init(
        downloadCenter: DownloadCenter,
        searchSettings: SearchSettingsStore,
        initialURL: URL? = nil,
        isPrivate: Bool = false,
        contentBlocking: ContentRuleListProvider? = nil,
        favicons: FaviconStore? = nil,
        webFeatures: WebFeatureSettingsStore? = nil,
        /// The profile's cookies and logins. Left unset, the app's default
        /// store — which is where anything saved before profiles existed is.
        websiteDataStore: WKWebsiteDataStore? = nil,
        /// The size this page opens at. Injectable rather than read straight
        /// from the shared preferences, so a test can hand in a size that
        /// differs from the default — the first version of that test compared
        /// 1.0 to 1.0 and passed with the wiring removed. Nil means the
        /// preference, resolved here because a default argument cannot reach a
        /// main-actor value.
        initialPageZoom: CGFloat? = nil,
        adoptingPopupConfiguration popupConfiguration: WKWebViewConfiguration? = nil
    ) {
        self.pageZoom = initialPageZoom ?? BrowserPreferences.shared.defaultPageZoom
        self.downloadCenter = downloadCenter
        self.searchSettings = searchSettings
        self.isPrivate = isPrivate
        self.contentBlocking = contentBlocking
        self.favicons = favicons
        // A popup has to be built from the configuration WebKit handed over, or
        // the opener relationship is severed and `window.opener` is null in the
        // new tab — which is how a popup sign-in completes and can never report
        // back to the page that started it. That configuration already carries
        // the opener's data store and user agent, so nothing here overrides it.
        let configuration = popupConfiguration ?? WKWebViewConfiguration()
        if popupConfiguration == nil {
            // A private tab is ephemeral whatever profile it belongs to; an
            // ordinary one gets its profile's store, which is what keeps two
            // profiles signed into the same site apart.
            configuration.websiteDataStore = isPrivate
                ? .nonPersistent()
                : (websiteDataStore ?? .default())
            // Ask for the page Safari would get: same engine, same capabilities.
            configuration.applicationNameForUserAgent = BrowserUserAgent.applicationName
            configuration.preferences.isElementFullscreenEnabled = true
            // Where a host is known to support HTTPS, take it. This upgrades
            // the navigation only; it is not a promise that every subresource
            // the page then loads is encrypted.
            configuration.upgradeKnownHostsToHTTPS = webFeatures?.upgradesToHTTPS ?? true
        }
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        // Registered before the first load so tracker rules apply from the
        // first request, including in private tabs.
        contentBlocking?.register(webView)
        // Chrome is dark because that is the product; a webpage is not. The
        // window forces dark on everything inside it, so without this a site
        // would be told the Mac prefers dark even when it is set to light.
        // Pages follow the Mac, and keep following it when it changes.
        // Off unless the person turned it on in Settings; it lets Safari's
        // Develop menu attach the Web Inspector to this page.
        // The size chosen in Settings → General. `pageZoom` is initialised from
        // the same preference, but that only sets the number this object
        // publishes — WKWebView starts at 1.0 regardless, so without this line
        // the setting moves a number and never the page.
        webView.pageZoom = pageZoom
        webView.isInspectable = webFeatures?.showsDeveloperFeatures ?? false
        webView.appearance = NSApp.effectiveAppearance
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsMagnification = true
        // Two-finger swipe for back and forward. It is reflexive on a Mac
        // trackpad, and a browser that ignores it reads as broken.
        webView.allowsBackForwardNavigationGestures = true
        observeSystemAppearance()
        observeWebViewState()
        if popupConfiguration != nil {
            // WebKit owns this web view's first navigation — it either has one
            // queued from `window.open(url)` or the script that opened it will
            // assign `location`. Loading anything here would throw that away,
            // so the tab simply shows its start surface until the popup moves.
            isShowingStartPage = true
            pageTitle = "New Tab"
            loadState = .startPage
        } else if let initialURL {
            load(initialURL)
        } else {
            showStartPage()
        }
    }

    /// Fully secure means HTTPS *and* nothing on the page arrived unencrypted.
    /// An HTTPS page carrying insecure subresources is not secure, and used to
    /// read as one here because only the scheme was consulted.
    var isSecure: Bool {
        connectionSecurity == .secure
    }

    /// Recomputed wherever `currentURLString` changes and whenever WebKit
    /// revises `hasOnlySecureContent`, which it can do after a page has already
    /// finished loading — a late subresource is exactly the case a scheme check
    /// misses.
    private func refreshConnectionSecurity() {
        connectionSecurity = ConnectionSecurity.make(
            urlString: currentURLString,
            hasOnlySecureContent: webView.hasOnlySecureContent,
            hasCommittedNavigation: hasCommittedNavigation
        )
    }

    /// App activation may focus the address field on a start/new tab, but must
    /// not steal keyboard focus from an already loaded webpage.
    var shouldFocusAddressOnAppActivation: Bool {
        isShowingStartPage
    }

    func navigate(_ input: String) {
        guard let url = resolve(input) else {
            loadState = .failed(
                BrowserFailure(
                    kind: .other,
                    title: "Nothing to open",
                    message: "Enter a web address or search terms.",
                    retryable: false
                )
            )
            return
        }
        load(url)
    }

    func load(_ url: URL, displayName: String? = nil) {
        guard let safeURL = WebURLPolicy.validatedURL(url) else {
            loadState = .failed(
                BrowserFailure(
                    kind: .blocked,
                    title: "Unsupported link",
                    message: "Limeghost opens web links only in this release.",
                    retryable: false
                )
            )
            return
        }
        isShowingStartPage = false
        lastRequestedURL = safeURL
        navigationDisplayName = displayName
        currentURLString = safeURL.absoluteString
        pageTitle = displayName.map { "Opening \($0)…" } ?? "Loading…"
        hasCommittedNavigation = false
        isLoading = true
        estimatedProgress = 0.05
        loadState = .loading
        refreshConnectionSecurity()
        activeNavigation = webView.load(URLRequest(url: safeURL))
    }

    /// Opens a file the person picked in an open panel.
    ///
    /// Deliberately a separate door from `load(_:)`, which takes http and
    /// https and nothing else. Only an open panel the person drove reaches
    /// this: no link, script, popup, redirect, restored tab, or typed address
    /// can, so `WebURLPolicy`'s refusal of local schemes stands everywhere it
    /// stood before.
    ///
    /// Read access is granted to the chosen file's own folder rather than the
    /// file alone, because a saved page keeps its images and stylesheet beside
    /// it and would otherwise render bare. WebKit gives file pages opaque
    /// origins, so this widens what the page may *display*, not what its
    /// scripts may read.
    func loadLocalFile(_ url: URL) {
        guard url.isFileURL else { return }
        isShowingStartPage = false
        lastRequestedURL = url
        navigationDisplayName = url.lastPathComponent
        currentURLString = url.absoluteString
        pageTitle = url.lastPathComponent
        hasCommittedNavigation = false
        isLoading = true
        estimatedProgress = 0.05
        loadState = .loading
        refreshConnectionSecurity()
        activeNavigation = webView.loadFileURL(
            url,
            allowingReadAccessTo: url.deletingLastPathComponent()
        )
    }

    func openAITool(_ tool: AIToolListing) {
        load(tool.officialURL, displayName: tool.name)
    }

    // MARK: - Page zoom

    /// The steps ⌘+ and ⌘− walk. `1.0` is the unzoomed page and the value ⌘0
    /// returns to.
    static let pageZoomSteps: [CGFloat] = [0.5, 0.67, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]
    static let defaultPageZoom: CGFloat = 1.0

    func zoomIn() {
        setPageZoom(Self.pageZoomSteps.first { $0 > pageZoom } ?? pageZoom)
    }

    func zoomOut() {
        setPageZoom(Self.pageZoomSteps.last { $0 < pageZoom } ?? pageZoom)
    }

    /// ⌘0.
    func resetPageZoom() {
        setPageZoom(Self.defaultPageZoom)
    }

    private func setPageZoom(_ value: CGFloat) {
        pageZoom = value
        webView.pageZoom = value
    }

    // MARK: - Printing

    /// True only while a real web page is on screen. The AI guide, the
    /// bookmarks home, and the error surfaces are app views, not documents, so
    /// the Print command disables itself on them.
    var canPrintPage: Bool { loadState == .content }

    /// The page as a PDF, laid out as WebKit is showing it.
    func makePDF(completion: @escaping (Result<Data, Error>) -> Void) {
        webView.createPDF { completion($0) }
    }

    /// The page as WebKit currently holds it, resources included, so a saved
    /// copy is what was on screen rather than a fresh fetch of the address.
    func makeWebArchive(completion: @escaping (Result<Data, Error>) -> Void) {
        webView.createWebArchiveData { completion($0) }
    }

    /// ⌘P. WebKit paginates the page the user is looking at; the print panel
    /// runs as a sheet on the browser window when there is one.
    func printPage() {
        guard canPrintPage else { return }
        let printInfo = NSPrintInfo.shared
        let operation = webView.printOperation(with: printInfo)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        // The operation's view has no frame of its own; without one WebKit
        // paginates an empty rectangle and the job comes out blank.
        operation.view?.frame = NSRect(
            x: 0,
            y: 0,
            width: max(printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin, 1),
            height: max(printInfo.paperSize.height - printInfo.topMargin - printInfo.bottomMargin, 1)
        )
        if let window = webView.window {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() {
        if isShowingStartPage { showStartPage() } else { webView.reload() }
    }
    func stopLoading() {
        webView.stopLoading()
        isLoading = false
        navigationDisplayName = nil
        loadState = isShowingStartPage ? .startPage : .content
    }

    func showStartPage() {
        isShowingStartPage = true
        hasRenderedPage = false
        lastRequestedURL = nil
        navigationDisplayName = nil
        hasCommittedNavigation = false
        isLoading = false
        estimatedProgress = 0
        currentURLString = ""
        pageTitle = "New Tab"
        loadState = .startPage
        refreshConnectionSecurity()
        activeNavigation = webView.loadHTMLString(Self.startPageHTML, baseURL: nil)
    }

    func retry() {
        guard let lastRequestedURL else {
            showStartPage()
            return
        }
        load(lastRequestedURL)
    }

    // MARK: - Declined links

    /// Schemes Limeghost does not navigate to but macOS owns. Handing them
    /// over is what every browser does; the page the reader was on stays put.
    private static let systemHandoffSchemes: Set<String> = ["mailto", "tel"]

    /// The address WebKit reports for a tab's start surface. `showStartPage()`
    /// renders it with `loadHTMLString`, which WebKit records as `about:blank`
    /// and keeps in the back-forward list like any other entry.
    static func isStartSurfaceURL(_ url: URL) -> Bool {
        url.absoluteString == "about:blank"
    }

    /// A link Limeghost will not navigate to. `mailto:` and `tel:` go to the
    /// app that owns them; anything else is named in a dismissible notice.
    /// Neither path touches `loadState` — refusing a link must not destroy the
    /// page the reader is reading.
    private func handleUnsupportedLink(_ url: URL) {
        let scheme = url.scheme?.lowercased() ?? ""
        if Self.systemHandoffSchemes.contains(scheme) {
            openExternalScheme(url)
            return
        }
        let described = scheme.isEmpty ? "link" : "\(scheme) link"
        showLinkNotice("Limeghost opens web links only, so it did not open this \(described).")
    }

    /// One rule for every request to open a tab, whether it came from a
    /// `target="_blank"` link or from `window.open()`.
    private func requestNewTab(for url: URL?) {
        if let url, WebURLPolicy.validatedURL(url) == nil, !Self.isStartSurfaceURL(url) {
            handleUnsupportedLink(url)
            return
        }
        // A popup with no address yet is still a tab: scripts routinely open
        // one blank and set its location a moment later. Opening nothing,
        // silently, is how a sign-in flow appears to do nothing at all.
        onRequestNewTab?(url.flatMap(WebURLPolicy.validatedURL))
    }

    func showPageNotice(_ message: String) {
        pageNoticeTask?.cancel()
        pageNotice = message
        pageNoticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            self?.pageNotice = nil
        }
    }

    func dismissPageNotice() {
        pageNoticeTask?.cancel()
        pageNotice = nil
    }

    private func showLinkNotice(_ message: String) {
        linkNoticeTask?.cancel()
        linkNotice = message
        linkNoticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            self?.linkNotice = nil
        }
    }

    func dismissLinkNotice() {
        linkNoticeTask?.cancel()
        linkNoticeTask = nil
        linkNotice = nil
    }

    /// Returns the chrome to the start surface for a back or forward move onto
    /// the tab's own `about:blank` entry, without loading anything. Calling
    /// `showStartPage()` here would push a second entry each time and make the
    /// back list grow instead of shrink.
    private func adoptStartPageEntry() {
        isShowingStartPage = true
        hasRenderedPage = false
        lastRequestedURL = nil
        lastCommittedWebURL = nil
        navigationDisplayName = nil
        hasCommittedNavigation = false
        estimatedProgress = 0
        currentURLString = ""
        pageTitle = "New Tab"
        loadState = .startPage
        refreshConnectionSecurity()
    }

    func teardown() {
        // `stopLoading` ends the network fetch and nothing else. A <video> that
        // has already buffered goes on playing, so a closed tab or a closed
        // window kept making noise with nothing left on screen to stop it.
        // Pausing is not enough on its own either — a paused element can be
        // resumed by the page's own script — so the document is replaced below,
        // once nothing is listening for the navigation.
        webView.pauseAllMediaPlayback()
        webView.closeAllMediaPresentations { }
        webView.stopLoading()
        faviconTask?.cancel()
        faviconTask = nil
        linkNoticeTask?.cancel()
        linkNoticeTask = nil
        linkNotice = nil
        onRequestNewTab = nil
        onRequestPopupWebView = nil
        onCompletedVisit = nil
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        contentBlocking?.unregister(webView)
        webViewSubscriptions.removeAll()
        appearanceObservation = nil
        // Last, and only once the subscriptions above are gone so this blank
        // load cannot overwrite the address this tab is remembered by: replacing
        // the document is what actually releases the media element.
        webView.loadHTMLString("", baseURL: nil)
    }

    func extractPage() async throws -> PageSnapshot {
        let value: Any = try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(Self.extractionScript) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let value {
                    continuation.resume(returning: value)
                } else {
                    continuation.resume(throwing: PageIntelligenceError.noReadableText)
                }
            }
        }
        guard JSONSerialization.isValidJSONObject(value) else {
            throw PageIntelligenceError.noReadableText
        }
        let data = try JSONSerialization.data(withJSONObject: value)
        let snapshot = try JSONDecoder().decode(PageSnapshot.self, from: data)
        guard snapshot.text.count >= 80 else { throw PageIntelligenceError.noReadableText }
        return snapshot
    }

    /// macOS posts this when the user switches Light and Dark; the page should
    /// follow without needing a reload.
    private func observeSystemAppearance() {
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] app, _ in
            Task { @MainActor in self?.webView.appearance = app.effectiveAppearance }
        }
    }

    private func observeWebViewState() {
        webView.publisher(for: \.estimatedProgress)
            .receive(on: RunLoop.main)
            .sink { [weak self] progress in
                guard let self, self.isLoading else { return }
                self.estimatedProgress = progress
            }
            .store(in: &webViewSubscriptions)

        // WebKit knows whether the page is still loading; this object only
        // mirrors it. The mirror can strand — a navigation superseded before it
        // reported an outcome leaves nothing to clear the flag, and the tab
        // spins on a page that finished. Treat WebKit as the authority: once it
        // has been idle briefly while this still claims to be loading, the
        // claim is wrong. Debounced so the moment between asking for a page and
        // WebKit starting it is not mistaken for the end of one.
        webView.publisher(for: \.isLoading)
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] webKitIsLoading in
                guard let self, !webKitIsLoading, self.isLoading else { return }
                self.reconcileStrandedLoadingState()
            }
            .store(in: &webViewSubscriptions)

        webView.publisher(for: \.title)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshState() }
            .store(in: &webViewSubscriptions)

        webView.publisher(for: \.url)
            .receive(on: RunLoop.main)
            .sink { [weak self] url in self?.observeURLChange(url) }
            .store(in: &webViewSubscriptions)

        // A page can pull an insecure subresource long after it finished
        // loading. WebKit revises this then, and the chip has to follow, or the
        // lock keeps claiming something that stopped being true.
        webView.publisher(for: \.hasOnlySecureContent)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshConnectionSecurity() }
            .store(in: &webViewSubscriptions)
    }

    private func observeURLChange(_ url: URL?) {
        let safeURL = url.flatMap(WebURLPolicy.validatedURL)
        let nextValue = safeURL?.absoluteString
        defer {
            lastObservedWebURLString = nextValue
            refreshState()
        }

        guard !isShowingStartPage,
              activeNavigation == nil,
              hasCommittedNavigation,
              let previous = lastObservedWebURLString,
              let nextValue,
              previous != nextValue,
              nextValue != lastVersionedStandardNavigationURLString else { return }

        // History API/hash changes do not run the ordinary provisional-navigation
        // callbacks, but they still change the page identity used by the assistant.
        navigationVersion += 1
        lastRequestedURL = safeURL
        lastCommittedWebURL = safeURL
    }

    /// Clears a loading state WebKit has already finished with. Deliberately
    /// narrow: it settles the chrome and nothing else. It does not record a
    /// visit, because a navigation that never reported finishing is not
    /// something to write into history from a guess.
    private func reconcileStrandedLoadingState() {
        activeNavigation = nil
        isLoading = false
        estimatedProgress = 1
        navigationDisplayName = nil
        if isShowingStartPage {
            loadState = .startPage
        } else if case .failed = loadState {
            // A failure already explains itself; leave it on screen.
        } else {
            hasCommittedNavigation = true
            loadState = .content
        }
        refreshState()
    }

    /// Puts the chrome into the stranded state the recovery path exists for, so
    /// the smoke suite can prove it recovers rather than trusting that it would.
    /// Not reachable from the interface; nothing in the app calls it.
    func simulateStrandedLoadingForTesting() {
        isLoading = true
        estimatedProgress = 0.4
        loadState = .loading
    }

    private func refreshState() {
        let activeURL = hasCommittedNavigation
            ? (webView.url ?? lastRequestedURL)
            : (lastRequestedURL ?? webView.url)
        currentURLString = isShowingStartPage ? "" : (activeURL?.absoluteString ?? "")
        if isShowingStartPage {
            pageTitle = "New Tab"
        } else if !hasCommittedNavigation, let navigationDisplayName {
            pageTitle = "Opening \(navigationDisplayName)…"
        } else {
            pageTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Loading…"
        }
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        refreshConnectionSecurity()
    }

    private func handleFailure(_ error: Error, navigation: WKNavigation?) {
        if let activeNavigation, let navigation, navigation !== activeNavigation {
            return
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            activeNavigation = nil
            isLoading = false
            navigationDisplayName = nil
            loadState = isShowingStartPage ? .startPage : .content
            return
        }
        if Self.isDownloadTransitionError(nsError) {
            activeNavigation = nil
            isLoading = false
            navigationDisplayName = nil
            if let lastCommittedWebURL {
                isShowingStartPage = false
                lastRequestedURL = lastCommittedWebURL
                hasCommittedNavigation = true
                loadState = .content
                refreshState()
            } else {
                showStartPage()
            }
            return
        }
        activeNavigation = nil
        isLoading = false
        navigationDisplayName = nil
        hasCommittedNavigation = false
        loadState = .failed(Self.describe(error))
        refreshState()
    }

    /// WebKit reports code 102 when a navigation policy converts a frame load
    /// into a download. It is an expected handoff to WKDownload, not a page error.
    static func isDownloadTransitionError(_ error: NSError) -> Bool {
        error.domain == "WebKitErrorDomain" && error.code == 102
    }

    var loadingTitle: String {
        navigationDisplayName.map { "Opening \($0)…" } ?? "Opening page…"
    }

    var loadingHost: String {
        lastRequestedURL?.host ?? ""
    }

    private static func describe(_ error: Error) -> BrowserFailure {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return BrowserFailure(kind: .other, title: "This page couldn’t be opened", message: error.localizedDescription, retryable: true)
        }
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return BrowserFailure(kind: .offline, title: "You appear to be offline", message: "Check your internet connection, then try this page again.", retryable: true)
        case NSURLErrorTimedOut:
            return BrowserFailure(kind: .timedOut, title: "The page took too long", message: "The website did not respond in time.", retryable: true)
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return BrowserFailure(kind: .cannotReachHost, title: "Website not found", message: "Check the address for a typo or try searching for the site.", retryable: true)
        case NSURLErrorCannotConnectToHost:
            return BrowserFailure(kind: .cannotReachHost, title: "Couldn’t connect to this website", message: "The server may be unavailable. Try again in a moment.", retryable: true)
        default:
            return BrowserFailure(kind: .other, title: "This page couldn’t be opened", message: error.localizedDescription, retryable: true)
        }
    }

    private func resolve(_ rawInput: String) -> URL? {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        if input.contains("://") {
            return WebURLPolicy.validatedURL(input)
        }

        if !input.contains(" ") && (input.contains(".") || input.hasPrefix("localhost")) {
            return WebURLPolicy.validatedURL("https://\(input)")
        }

        return searchSettings.searchURL(for: input)
    }

    private static let startPageHTML = #"""
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
          body { align-items:center; background:#f5f5f7; color:#141417; display:flex; min-height:100vh; margin:0; }
          main { margin:auto; max-width:620px; padding:48px; text-align:center; }
          .mark { align-items:center; background:#123c2e; border-radius:28px 8px 28px 8px; color:#66db7d; display:flex; font:700 56px Georgia,serif; height:110px; justify-content:center; margin:0 auto 34px; width:110px; }
          .eyebrow { color:#1f6e4f; font-size:11px; font-weight:800; letter-spacing:.15em; }
          h1 { font:700 clamp(38px,6vw,64px)/.98 Georgia,serif; letter-spacing:-.045em; margin:12px 0 20px; }
          p { color:#5c6360; font-size:17px; line-height:1.6; }
          .hint { background:#fff; border:1px solid #e2e3e1; border-radius:14px; box-shadow:0 12px 40px rgba(10,14,12,.07); font-size:14px; margin-top:30px; padding:16px; }
          @media (prefers-color-scheme: dark) { body { background:#0b0b0e; color:#f4f4f2; } .eyebrow{color:#66db7d}.hint{background:#15151a;border-color:rgba(255,255,255,.08)} }
        </style>
      </head>
      <body>
        <main>
          <div class="mark">C</div>
          <div class="eyebrow">LIMEGHOST BROWSER</div>
          <h1>Browse first.<br>Hand it over when you want to.</h1>
          <p>Enter a web address or search in the bar above. When a page is worth asking about, copy its readable text for the AI you already use.</p>
          <div class="hint">Press <strong>⇧⌘C</strong> to copy a page. Nothing is sent anywhere by Limeghost.</div>
        </main>
      </body>
    </html>
    """#

    /// Pulls the page's readable text out of the DOM.
    ///
    /// The old version asked the page to identify itself: take the first
    /// `<article>`, `<main>` or `[role=main]` with 400 characters, otherwise take
    /// the whole `<body>`, then keep only blocks between 45 and 1800 characters.
    /// Both halves were wrong. A great many sites are anonymous `<div>`s, so the
    /// fallback fired and the navigation menu arrived as article text; and the
    /// 45-character floor deleted every short block — measured on Apple's Mac mini
    /// specifications page it removed **157 of them**, which were the
    /// specifications: "Apple M6 chip", "12-core GPU", "153GB/s memory bandwidth".
    /// A specifications page is made of short blocks, and the floor could not tell
    /// one from a menu item because both are short.
    ///
    /// This version asks a different question. It measures **reading mass** — the
    /// text a block holds, discounted by how much of that text is inside links —
    /// and then walks down from `<body>` for as long as a single child still holds
    /// most of it. A menu is nearly all links and weighs almost nothing; an article
    /// column outweighs everything beside it. It stops where the text spreads out,
    /// which is the container that holds the article rather than one column of it.
    ///
    /// Link density is what the length floor was reaching for and failing to say. A
    /// menu item is a link; a specification value is not.
    ///
    /// Measured against the previous version on three live pages:
    ///
    ///     Britannica article    5,377 chars whole →  3,604 before →  3,368 now
    ///     MacRumors homepage   53,753 chars whole →  5,027 before → 38,328 now
    ///     Apple specifications 16,493 chars whole →  4,501 before →  5,182 now
    ///                                            (0 spec values) (154 blocks, all)
    ///
    /// `extractionConfidence` is the share of the page's reading mass the chosen
    /// container holds. Low means the page had no dominant body of text and the
    /// result should be treated as a guess.
    private static let extractionScript = #"""
    (() => {
      const clean = (value = '') => value.replace(/\s+/g, ' ').trim();
      const excludedSelector = [
        'script', 'style', 'noscript', 'svg', 'canvas', 'nav', 'footer', 'header', 'aside',
        'form', 'dialog', 'button', 'input', 'select', 'textarea', 'video', 'audio', 'iframe',
        '[hidden]', '[aria-hidden="true"]', '[aria-modal="true"]', '[role="button"]',
        '[role="toolbar"]', '[role="menu"]', '[role="navigation"]', '[role="dialog"]',
        '[role="alertdialog"]', '[class*="jwplayer"]', '[class*="jw-"]', '[class*="vjs-"]',
        '[class*="plyr__"]', '[class*="video-player"]', '[class*="videoplayer"]',
        '[class*="media-player"]', '[class*="mediaplayer"]', '[class*="player-control"]',
        '[class*="cookie"]', '[id*="cookie"]', '[class*="consent"]', '[id*="consent"]'
      ].join(',');

      // `td`/`th` are deliberately absent: a table row is one reading unit, and
      // splitting it into cells loses which value belongs to which label.
      const BLOCKS = 'p,li,blockquote,h1,h2,h3,h4,dd,dt,tr,figcaption,pre';

      const viewportWidth = document.documentElement.clientWidth || window.innerWidth;
      const isRendered = node => {
        const style = getComputedStyle(node);
        const rect = node.getBoundingClientRect();
        return style.display !== 'none' && style.visibility !== 'hidden' &&
          Number(style.opacity || 1) > 0 && rect.width > 0 && rect.height > 0 &&
          rect.right > 0 && rect.left < viewportWidth;
      };

      // What share of this element's text sits inside links. A navigation list is
      // close to 1; ordinary prose is close to 0.
      const linkDensity = element => {
        const total = (element.innerText || '').length;
        if (!total) return 1;
        let linked = 0;
        element.querySelectorAll('a').forEach(anchor => { linked += (anchor.innerText || '').length; });
        return Math.min(1, linked / total);
      };

      // Innermost blocks only, so a list is read as its items rather than twice.
      // A row is an exception: it is one unit unless it nests real blocks inside.
      const isLeafBlock = element => {
        if (!element.matches || !element.matches(BLOCKS)) return false;
        if (element.closest(excludedSelector) || !isRendered(element)) return false;
        if (element.tagName === 'TR') return !element.querySelector('p,li,blockquote,h1,h2,h3,h4,tr');
        return !element.querySelector(BLOCKS);
      };

      const readingMass = element => {
        let mass = 0;
        for (const block of element.querySelectorAll(BLOCKS)) {
          if (!isLeafBlock(block)) continue;
          mass += clean(block.innerText).length * (1 - linkDensity(block));
        }
        return mass;
      };

      const totalMass = readingMass(document.body);
      let root = document.body;
      for (let depth = 0; depth < 30; depth += 1) {
        const here = readingMass(root);
        if (here < 200) break;
        let candidate = null;
        let candidateMass = 0;
        for (const child of root.children) {
          if (child.closest(excludedSelector)) continue;
          const mass = readingMass(child);
          if (mass > candidateMass) { candidateMass = mass; candidate = child; }
        }
        // Descend only while one child still carries the page. Where the text
        // spreads across siblings — a specifications page's columns — this is the
        // container that holds them all, and stopping here is the whole point.
        if (candidate && candidateMass >= here * 0.8) root = candidate; else break;
      }

      // Open shadow roots inside the chosen container. Closed ones are unreadable
      // by anyone, including this.
      const shadowRoots = [];
      root.querySelectorAll('*').forEach(node => { if (node.shadowRoot) shadowRoots.push(node.shadowRoot); });

      const seen = new Set();
      const blocks = [];
      const collect = scope => {
        const elements = scope === root ? [root, ...root.querySelectorAll(BLOCKS)] : [...scope.querySelectorAll(BLOCKS)];
        for (const element of elements) {
          if (!isLeafBlock(element)) continue;
          const text = clean(element.innerText);
          if (!text || text.length > 1800) continue;
          // A short block that is almost entirely a link is a menu item, whatever
          // element it happens to use.
          if (text.length < 100 && linkDensity(element) > 0.8) continue;
          const key = text.toLocaleLowerCase();
          if (seen.has(key)) continue;
          seen.add(key);
          blocks.push(text);
        }
      };
      collect(root);
      shadowRoots.forEach(collect);

      // Nothing survived: hand back the page as it reads, line by line, rather
      // than nothing at all. `extractionConfidence` says this happened.
      const bodyText = (document.body.innerText || '').split('\n').map(clean).filter(Boolean).join('\n');
      const usedFallback = blocks.length < 2;
      const text = (usedFallback ? bodyText : blocks.join('\n')).slice(0, 48000);

      const readingUnits = text.match(/[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]|[\p{L}\p{M}\p{N}]+/gu) || [];
      const actions = [...document.forms]
        .map(form => { try { return new URL(form.action, location.href).origin; } catch { return ''; } })
        .filter(Boolean);
      const meta = selector => document.querySelector(selector)?.getAttribute('content') || '';

      return {
        title: meta('meta[property="og:title"]') || clean(document.querySelector('h1')?.innerText || '') ||
          document.title || location.hostname,
        url: location.href,
        hostname: location.hostname,
        scheme: location.protocol.replace(':', ''),
        language: document.documentElement.lang || meta('meta[http-equiv="content-language"]') || '',
        text,
        wordCount: readingUnits.length,
        hasPasswordField: Boolean(document.querySelector('input[type="password"]')),
        formActions: actions,
        extractionConfidence: usedFallback ? 0 : Math.min(1, readingMass(root) / (totalMass || 1))
      };
    })()
    """#
}

extension BrowserSession: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        // A provisional navigation that starts now is by definition the newest,
        // so it takes over. Refusing it would leave the older one active while
        // WebKit quietly abandons it, and the newer one's didFinish would then
        // be dismissed as stale — the tab spins for a page that finished
        // loading. Staleness is filtered where it belongs, on the callbacks
        // that report an outcome.
        activeNavigation = navigation
        // Recorded here because nothing has had a chance to change it yet:
        // a server redirect is reported later, on this same navigation.
        navigationOriginURL = lastRequestedURL ?? webView.url.flatMap(WebURLPolicy.validatedURL)
        isLoading = true
        hasCommittedNavigation = false
        // A notice about a link Limeghost declined belongs to the page it was
        // declined on; the next page starts without it.
        dismissLinkNotice()
        navigationVersion += 1
        lastVersionedStandardNavigationURLString = lastRequestedURL?.absoluteString
        if !isShowingStartPage { loadState = .loading }
        refreshState()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let activeNavigation, navigation !== activeNavigation { return }
        // A back or forward move onto the tab's own start-surface entry may
        // arrive here without passing the policy decision — WebKit can restore
        // a cached document directly. Whichever route it took, the tab is on
        // its start surface now and the chrome has to agree, or it keeps
        // showing the address and title of the page the reader just left.
        if let url = webView.url, Self.isStartSurfaceURL(url), !isShowingStartPage {
            adoptStartPageEntry()
        }
        hasCommittedNavigation = true
        if let url = webView.url, WebURLPolicy.validatedURL(url) != nil {
            hasRenderedPage = true
        }
        if isShowingStartPage { loadState = .startPage }
        if let url = webView.url,
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme) {
            lastCommittedWebURL = url
            lastVersionedStandardNavigationURLString = url.absoluteString
        }
        navigationDisplayName = nil
        refreshState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let activeNavigation, navigation !== activeNavigation { return }
        activeNavigation = nil
        isLoading = false
        estimatedProgress = 1
        hasCommittedNavigation = true
        navigationDisplayName = nil
        if let url = webView.url.flatMap(WebURLPolicy.validatedURL) {
            lastVersionedStandardNavigationURLString = url.absoluteString
        }
        refreshState()
        if isShowingStartPage {
            loadState = .startPage
        } else {
            loadState = .content
            if !currentURLString.isEmpty {
                onCompletedVisit?(pageTitle, currentURLString)
            }
            captureSiteIcon()
        }
    }

    /// The only place Limeghost fetches a site icon: a real, finished visit
    /// to an ordinary web page, from that page's own origin. Private tabs
    /// still get an icon for the tab strip, but `FaviconStore` keeps it in
    /// memory only.
    private func captureSiteIcon() {
        guard let favicons,
              let url = webView.url.flatMap(WebURLPolicy.validatedURL),
              FaviconStore.captureHost(for: url) != nil else { return }
        // Where this navigation started, captured before the site had a
        // chance to redirect. After `pinterest.co.uk` sends the browser to
        // `uk.pinterest.com`, this is still the address a bookmark holds.
        let requested = navigationOriginURL
        // Let the cancelled run unwind before the replacement starts. It holds
        // this host in the store's in-flight set until it does, and a
        // replacement arriving first is turned away by it — which on a site
        // that reloads itself moments after loading is exactly when the
        // replacement is the run that matters.
        let previous = faviconTask
        previous?.cancel()
        faviconTask = Task { [weak self] in
            _ = await previous?.value
            guard let self else { return }
            await favicons.captureIfNeeded(
                for: url,
                requestedURL: requested,
                in: self.webView,
                isPrivate: self.isPrivate
            )
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleFailure(error, navigation: navigation)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        activeNavigation = nil
        isLoading = false
        hasCommittedNavigation = false
        loadState = .failed(
            BrowserFailure(
                kind: .other,
                title: "This page stopped responding",
                message: "WebKit ended the page process. Reload to open the page again.",
                retryable: true
            )
        )
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleFailure(error, navigation: navigation)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // Asked first, deliberately. `<a download href="blob:…">` is how a web
        // app hands over a CSV or a PDF it built in the page, and a blob: or
        // data: address is not a navigable web URL. Judging the scheme before
        // asking WebKit what the link is for would refuse the file the user
        // just asked to save.
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        if navigationAction.targetFrame == nil {
            requestNewTab(for: navigationAction.request.url)
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame?.isMainFrame == true,
           let url = navigationAction.request.url,
           WebURLPolicy.validatedURL(url) == nil {
            if Self.isStartSurfaceURL(url) {
                // Every tab opens on `loadHTMLString`, so its first
                // back-forward entry is `about:blank`. Going back onto that
                // entry is a return to this tab's start surface, not a link
                // Limeghost cannot open: let WebKit restore the document it
                // already holds and put the chrome back on the start state.
                adoptStartPageEntry()
                decisionHandler(.allow)
                return
            }
            handleUnsupportedLink(url)
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame?.isMainFrame == true,
           let url = navigationAction.request.url,
           let safeURL = WebURLPolicy.validatedURL(url) {
            isShowingStartPage = false
            lastRequestedURL = safeURL
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        downloadCenter.track(download, sourceURL: navigationAction.request.url)
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        downloadCenter.track(download, sourceURL: navigationResponse.response.url)
    }
}

extension BrowserSession: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url,
           WebURLPolicy.validatedURL(url) == nil,
           !Self.isStartSurfaceURL(url) {
            // `window.open('mailto:…')` is still not a web link.
            handleUnsupportedLink(url)
            return nil
        }
        // Handing back a web view built from WebKit's own configuration is what
        // keeps `window.opener` alive in the new tab. Returning nil severs it,
        // so a popup sign-in completes in the new tab and can never tell the
        // page that started it. `window.open()` with no address is ordinary
        // too — the script opens the popup first and assigns `location` a
        // moment later — so a popup without a URL still gets its tab.
        if let popup = onRequestPopupWebView?(configuration) { return popup }
        // No workspace attached (unit fixtures): open a plain tab rather than
        // drop the popup silently.
        requestNewTab(for: navigationAction.request.url)
        return nil
    }

    /// Without this, every `<input type="file">` on the web is dead: no picker
    /// appears and the page is never told anything happened. Private tabs are
    /// no different — a file the user chose is a file the user chose.
    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        // WebKit keeps the page's file input suspended until this handler is
        // called, and dropping it deadlocks uploads for the rest of the
        // session. Every path out of here — choose, cancel, no window — answers
        // through one latch that fires exactly once.
        let answer = OpenPanelAnswer(completionHandler)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canCreateDirectories = false
        panel.prompt = "Choose"
        panel.message = webView.url?.host.map { "Choose what to upload to \($0)." }
            ?? "Choose what to upload to this page."
        if let window = webView.window {
            panel.beginSheetModal(for: window) { response in
                answer.deliver(response == .OK ? panel.urls : nil)
            }
        } else {
            answer.deliver(panel.runModal() == .OK ? panel.urls : nil)
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = pageAlert(message: message)
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = pageAlert(message: message)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = pageAlert(message: prompt)
        let field = NSTextField(string: defaultText ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil)
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        // WebKit owns the visible per-request prompt. Limeghost never remembers or
        // silently grants camera/microphone access from page content.
        decisionHandler(.prompt)
    }

    private func pageAlert(message: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = webView.url?.host.map { "Message from \($0)" } ?? "Message from this page"
        alert.informativeText = String(message.prefix(4_000))
        alert.alertStyle = .informational
        return alert
    }
}

/// One-shot latch for WebKit's open-panel completion handler. WebKit treats a
/// second call as a hard error and a missing call as a permanent stall, so the
/// handler is released here once and then forgotten.
private final class OpenPanelAnswer {
    private var completionHandler: (([URL]?) -> Void)?

    init(_ completionHandler: @escaping ([URL]?) -> Void) {
        self.completionHandler = completionHandler
    }

    func deliver(_ urls: [URL]?) {
        guard let completionHandler else { return }
        self.completionHandler = nil
        completionHandler(urls)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
