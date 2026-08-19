import ClearframeCore
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
}

@MainActor
final class BrowserSession: NSObject, ObservableObject {
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
    @Published private(set) var pageZoom: CGFloat = BrowserSession.defaultPageZoom
    /// A link Clearframe declined to open, stated as a dismissible line above
    /// the page. Refusing a link must never take away the page the reader is
    /// on, so this never touches `loadState`.
    @Published private(set) var linkNotice: String?

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

    init(
        downloadCenter: DownloadCenter,
        searchSettings: SearchSettingsStore,
        initialURL: URL? = nil,
        isPrivate: Bool = false,
        contentBlocking: ContentRuleListProvider? = nil,
        favicons: FaviconStore? = nil,
        adoptingPopupConfiguration popupConfiguration: WKWebViewConfiguration? = nil
    ) {
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
            configuration.websiteDataStore = isPrivate ? .nonPersistent() : .default()
            // Ask for the page Safari would get: same engine, same capabilities.
            configuration.applicationNameForUserAgent = BrowserUserAgent.applicationName
            configuration.preferences.isElementFullscreenEnabled = true
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

    var isSecure: Bool {
        URL(string: currentURLString)?.scheme?.lowercased() == "https"
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
                    message: "Clearframe opens web links only in this release.",
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
        activeNavigation = webView.load(URLRequest(url: safeURL))
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

    /// Schemes Clearframe does not navigate to but macOS owns. Handing them
    /// over is what every browser does; the page the reader was on stays put.
    private static let systemHandoffSchemes: Set<String> = ["mailto", "tel"]

    /// The address WebKit reports for a tab's start surface. `showStartPage()`
    /// renders it with `loadHTMLString`, which WebKit records as `about:blank`
    /// and keeps in the back-forward list like any other entry.
    static func isStartSurfaceURL(_ url: URL) -> Bool {
        url.absoluteString == "about:blank"
    }

    /// A link Clearframe will not navigate to. `mailto:` and `tel:` go to the
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
        showLinkNotice("Clearframe opens web links only, so it did not open this \(described).")
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
    }

    func teardown() {
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

    /// Reveal locally extracted evidence in the current document. This is deliberately
    /// best-effort: pages own their DOM and can change it after analysis, so the
    /// Assistant always keeps the extracted source text as the reliable fallback.
    func revealEvidence(_ text: String, expectedNavigationVersion: Int? = nil) async -> Bool {
        if let expectedNavigationVersion, expectedNavigationVersion != navigationVersion { return false }
        guard !text.isEmpty,
              let data = try? JSONEncoder().encode(text),
              let quoted = String(data: data, encoding: .utf8) else { return false }
        let script = """
        (() => {
          const needle = \(quoted).replace(/\\s+/g, ' ').trim();
          if (!needle || !document.body) return false;
          const clean = value => (value || '').replace(/\\s+/g, ' ').trim();
          const visible = element => {
            const style = getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            return style.display !== 'none' && style.visibility !== 'hidden' &&
              Number(style.opacity || 1) > 0 && rect.width > 0 && rect.height > 0;
          };
          const roots = [document];
          document.querySelectorAll('*').forEach(element => { if (element.shadowRoot) roots.push(element.shadowRoot); });
          roots.forEach(root => root.querySelectorAll('[data-clearframe-evidence]').forEach(element => {
            element.removeAttribute('data-clearframe-evidence');
          }));
          const matches = roots.flatMap(root => [...root.querySelectorAll('h1,h2,h3,p,li,blockquote')])
            .filter(visible)
            .map(element => ({ element, value: clean(element.innerText || element.textContent) }))
            .filter(candidate => candidate.value.length > 0 && candidate.value.includes(needle))
            .sort((left, right) => left.value.length - right.value.length);
          const match = matches[0];
          if (!match) return false;
          const root = match.element.getRootNode();
          const styleHost = root === document ? (document.head || document.documentElement) : root;
          if (!root.querySelector('#clearframe-evidence-style')) {
            const style = document.createElement('style');
            style.id = 'clearframe-evidence-style';
            style.textContent = '[data-clearframe-evidence]{background:rgba(132,204,22,.20)!important;outline:2px solid rgba(77,124,15,.75)!important;outline-offset:3px!important;}';
            styleHost.appendChild(style);
          }
          match.element.setAttribute('data-clearframe-evidence', 'true');

          const range = document.createRange();
          const walker = document.createTreeWalker(match.element, NodeFilter.SHOW_TEXT);
          const positions = [];
          let normalized = '';
          let pendingWhitespace = null;
          while (walker.nextNode()) {
            const node = walker.currentNode;
            const value = node.textContent || '';
            for (let index = 0; index < value.length; index += 1) {
              if (/\\s/.test(value[index])) {
                if (normalized && !pendingWhitespace) pendingWhitespace = { node, offset: index };
                continue;
              }
              if (pendingWhitespace && normalized && !normalized.endsWith(' ')) {
                normalized += ' ';
                positions.push(pendingWhitespace);
              }
              pendingWhitespace = null;
              normalized += value[index];
              positions.push({ node, offset: index });
            }
          }
          const start = normalized.indexOf(needle);
          if (start >= 0 && positions[start] && positions[start + needle.length - 1]) {
            const first = positions[start];
            const last = positions[start + needle.length - 1];
            range.setStart(first.node, first.offset);
            range.setEnd(last.node, last.offset + 1);
          } else {
            range.selectNodeContents(match.element);
          }
          const selection = typeof root.getSelection === 'function' ? root.getSelection() : window.getSelection();
          if (selection) {
            selection.removeAllRanges();
            selection.addRange(range);
          }
          match.element.scrollIntoView({ behavior: 'smooth', block: 'center' });
          return true;
        })()
        """
        do {
            let value: Any = try await withCheckedThrowingContinuation { continuation in
                webView.evaluateJavaScript(script) { value, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: value as Any) }
                }
            }
            guard expectedNavigationVersion == nil || expectedNavigationVersion == navigationVersion else {
                return false
            }
            return value as? Bool ?? false
        } catch {
            return false
        }
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
          <div class="eyebrow">CLEARFRAME BROWSER</div>
          <h1>Browse first.<br>Understand as you go.</h1>
          <p>Enter a web address or search in the bar above. Open the assistant when you want a local summary, source context, or visible risk signals.</p>
          <div class="hint">Local analysis runs only when you click <strong>Analyze page</strong>.</div>
        </main>
      </body>
    </html>
    """#

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
      const isRendered = node => {
        const style = getComputedStyle(node);
        const rect = node.getBoundingClientRect();
        const viewportWidth = document.documentElement.clientWidth || window.innerWidth;
        return style.display !== 'none' && style.visibility !== 'hidden' && Number(style.opacity || 1) > 0 &&
          rect.width > 0 && rect.height > 0 && rect.right > 0 && rect.left < viewportWidth;
      };
      const preferred = [document.querySelector('article'), document.querySelector('main'), document.querySelector('[role="main"]')]
        .filter(node => (node?.innerText?.trim().length || 0) >= 400);
      const root = preferred[0] || document.body;
      const clone = root.cloneNode(true);
      clone.querySelectorAll(excludedSelector).forEach(node => node.remove());
      const shadowRoots = [];
      document.querySelectorAll('*').forEach(node => {
        if (node.shadowRoot && (root === document.body || root.contains(node))) shadowRoots.push(node.shadowRoot);
      });
      const readingNodes = selector => [root, ...shadowRoots].flatMap(scope => [...scope.querySelectorAll(selector)]);
      const seenBlocks = new Set();
      const blocks = readingNodes('h1,h2,h3,p,li,blockquote')
        .filter(node => !node.closest(excludedSelector) && isRendered(node))
        .map(node => clean(node.innerText))
        .filter(text => text.length >= 45 && text.length <= 1800)
        .filter(text => {
          const key = text.toLocaleLowerCase();
          if (seenBlocks.has(key)) return false;
          seenBlocks.add(key);
          return true;
        });
      const bodyText = clean(clone.innerText || '');
      const text = (blocks.length >= 2 ? blocks.join('\n') : bodyText).slice(0, 48000);
      const readingUnits = text.match(/[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]|[\p{L}\p{M}\p{N}]+/gu) || [];
      const actions = [...document.forms].map(form => {
        try { return new URL(form.action || location.href, location.href).origin; } catch { return ''; }
      }).filter(Boolean);
      const meta = selector => document.querySelector(selector)?.content?.trim() || '';
      return {
        title: meta('meta[property="og:title"]') || document.querySelector('h1')?.innerText?.trim() || document.title || location.hostname,
        url: location.href,
        hostname: location.hostname,
        scheme: location.protocol.replace(':', ''),
        language: document.documentElement.lang || meta('meta[http-equiv="content-language"]') || '',
        text,
        wordCount: readingUnits.length,
        hasPasswordField: Boolean(document.querySelector('input[type="password"]')),
        formActions: actions
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
        isLoading = true
        hasCommittedNavigation = false
        // A notice about a link Clearframe declined belongs to the page it was
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

    /// The only place Clearframe fetches a site icon: a real, finished visit
    /// to an ordinary web page, from that page's own origin. Private tabs
    /// still get an icon for the tab strip, but `FaviconStore` keeps it in
    /// memory only.
    private func captureSiteIcon() {
        guard let favicons,
              let url = webView.url.flatMap(WebURLPolicy.validatedURL),
              FaviconStore.captureHost(for: url) != nil else { return }
        faviconTask?.cancel()
        faviconTask = Task { [weak self] in
            guard let self else { return }
            await favicons.captureIfNeeded(for: url, in: self.webView, isPrivate: self.isPrivate)
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
                // Clearframe cannot open: let WebKit restore the document it
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
        // WebKit owns the visible per-request prompt. Clearframe never remembers or
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
