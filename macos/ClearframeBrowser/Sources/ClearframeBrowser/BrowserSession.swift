import ClearframeCore
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

    @Published private(set) var currentURLString = ""
    @Published private(set) var pageTitle = "New Page"
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var estimatedProgress = 0.0
    @Published private(set) var navigationVersion = 0
    @Published private(set) var loadState: BrowserLoadState = .startPage
    @Published private(set) var hasCommittedNavigation = false

    var onRequestNewTab: ((URL) -> Void)?
    var onCompletedVisit: ((String, String) -> Void)?

    private var isShowingStartPage = true
    private var lastRequestedURL: URL?
    private var navigationDisplayName: String?
    private var activeNavigation: WKNavigation?

    init(
        downloadCenter: DownloadCenter,
        searchSettings: SearchSettingsStore,
        initialURL: URL? = nil
    ) {
        self.downloadCenter = downloadCenter
        self.searchSettings = searchSettings
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.isElementFullscreenEnabled = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsMagnification = true
        if let initialURL {
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
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
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
        lastRequestedURL = url
        navigationDisplayName = displayName
        currentURLString = url.absoluteString
        pageTitle = displayName.map { "Opening \($0)…" } ?? "Loading…"
        hasCommittedNavigation = false
        isLoading = true
        estimatedProgress = 0.05
        loadState = .loading
        activeNavigation = webView.load(URLRequest(url: url))
    }

    func openAITool(_ tool: AIToolListing) {
        load(tool.officialURL, displayName: tool.name)
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

    func teardown() {
        webView.stopLoading()
        onRequestNewTab = nil
        onCompletedVisit = nil
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
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
        activeNavigation = nil
        isLoading = false
        navigationDisplayName = nil
        hasCommittedNavigation = false
        loadState = .failed(Self.describe(error))
        refreshState()
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

        if let explicit = URL(string: input),
           let scheme = explicit.scheme?.lowercased(),
           ["http", "https"].contains(scheme) {
            return explicit
        }

        if !input.contains(" ") && (input.contains(".") || input.hasPrefix("localhost")) {
            return URL(string: "https://\(input)")
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
          body { align-items:center; background:#f5f5ef; color:#17231f; display:flex; min-height:100vh; margin:0; }
          main { margin:auto; max-width:620px; padding:48px; text-align:center; }
          .mark { align-items:center; background:#174f3e; border-radius:28px 8px 28px 8px; color:#d4f379; display:flex; font:700 56px Georgia,serif; height:110px; justify-content:center; margin:0 auto 34px; width:110px; }
          .eyebrow { color:#174f3e; font-size:11px; font-weight:800; letter-spacing:.15em; }
          h1 { font:700 clamp(38px,6vw,64px)/.98 Georgia,serif; letter-spacing:-.045em; margin:12px 0 20px; }
          p { color:#64716c; font-size:17px; line-height:1.6; }
          .hint { background:#fff; border:1px solid #dfe4dc; border-radius:14px; box-shadow:0 12px 40px rgba(29,54,45,.08); font-size:14px; margin-top:30px; padding:16px; }
          @media (prefers-color-scheme: dark) { body { background:#111814; color:#edf5ef; } .eyebrow{color:#d4f379}.hint{background:#19231e;border-color:#33443a} }
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
      const seenBlocks = new Set();
      const blocks = [...root.querySelectorAll('h2,h3,p,li,blockquote')]
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
        language: document.documentElement.lang || navigator.language || '',
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
        if let activeNavigation, navigation !== activeNavigation { return }
        activeNavigation = navigation
        isLoading = true
        estimatedProgress = 0.25
        hasCommittedNavigation = false
        navigationVersion += 1
        if !isShowingStartPage { loadState = .loading }
        refreshState()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let activeNavigation, navigation !== activeNavigation { return }
        estimatedProgress = 0.65
        hasCommittedNavigation = true
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
        refreshState()
        if isShowingStartPage {
            loadState = .startPage
        } else {
            loadState = .content
            if !currentURLString.isEmpty {
                onCompletedVisit?(pageTitle, currentURLString)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleFailure(error, navigation: navigation)
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
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            if let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
                onRequestNewTab?(url)
            } else {
                loadState = .failed(
                    BrowserFailure(
                        kind: .blocked,
                        title: "Unsupported link",
                        message: "Clearframe did not open this link because this release supports web links only.",
                        retryable: false
                    )
                )
            }
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame?.isMainFrame == true,
           let scheme = navigationAction.request.url?.scheme?.lowercased(),
           !["http", "https", "about", "data"].contains(scheme) {
            loadState = .failed(
                BrowserFailure(
                    kind: .blocked,
                    title: "Unsupported link",
                    message: "Clearframe did not open the \(scheme) link because this browser foundation supports web links only.",
                    retryable: false
                )
            )
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame?.isMainFrame == true,
           let url = navigationAction.request.url,
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            isShowingStartPage = false
            lastRequestedURL = url
        }
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
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

extension BrowserSession: WKUIDelegate {}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
