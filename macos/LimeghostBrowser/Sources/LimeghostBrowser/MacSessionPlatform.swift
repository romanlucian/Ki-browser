import AppKit
import LimeghostShared
@preconcurrency import WebKit

/// The macOS implementation of the six things `BrowserSession` needs from the
/// operating system. Every body below is the code that used to sit inline in
/// `BrowserSession` itself, relocated rather than rewritten — see each
/// method's own note for anything that could not stay byte-for-byte identical
/// and why.
@MainActor
final class MacSessionPlatform: BrowserSessionPlatform {
    /// The web view this platform answers for. `BrowserSession.init(platform:...)`
    /// takes `platform` before it has built one — the session, not the
    /// platform, owns web view construction, which has to stay true for a
    /// popup to keep adopting WebKit's own configuration — so nothing here
    /// can know which web view is its own until the convenience initializer
    /// below hands it over, right after `self.init(platform:...)` returns.
    /// Weak, like every other back-reference a delegate holds to the object
    /// that owns it.
    fileprivate weak var webView: WKWebView?

    func openExternal(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func presentAlert(message: String) async {
        let alert = pageAlert(message: message)
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func presentConfirm(message: String) async -> Bool {
        let alert = pageAlert(message: message)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func presentPrompt(message: String, defaultText: String?) async -> String? {
        let alert = pageAlert(message: message)
        let field = NSTextField(string: defaultText ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    /// Satisfies the protocol, but is not today's live path for `<input
    /// type="file">` on macOS: see `BrowserSession.webView(_:runOpenPanelWith:
    /// initiatedByFrame:completionHandler:)` below, which keeps the original
    /// panel-construction code verbatim instead of routing through here. That
    /// method needs `WKOpenPanelParameters`, which carries `allowsDirectories`
    /// — this protocol's narrower `allowsMultiple: Bool` cannot — and it also
    /// has the calling web view in hand directly, rather than through a weak
    /// reference set after the fact. Losing directory-selection support (a
    /// site asking for a folder, not files) to fit this signature would be a
    /// real behaviour change, so that method does not call this one. This
    /// implementation exists to be a faithful, protocol-shaped answer for any
    /// caller that only has `allowsMultiple` to give it.
    func chooseFiles(allowsMultiple: Bool) async -> [URL]? {
        await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = allowsMultiple
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.canCreateDirectories = false
            panel.prompt = "Choose"
            panel.message = webView?.url?.host.map { "Choose what to upload to \($0)." }
                ?? "Choose what to upload to this page."
            if let window = webView?.window {
                panel.beginSheetModal(for: window) { response in
                    continuation.resume(returning: response == .OK ? panel.urls : nil)
                }
            } else {
                continuation.resume(returning: panel.runModal() == .OK ? panel.urls : nil)
            }
        }
    }

    /// ⌘P. WebKit paginates the page the user is looking at; the print panel
    /// runs as a sheet on the browser window when there is one.
    func printPage(_ webView: WKWebView) {
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

    /// macOS posts this when the user switches Light and Dark; the page
    /// should follow without needing a reload.
    func observeAppearance(_ apply: @escaping () -> Void) -> Any? {
        NSApp.observe(\.effectiveAppearance) { [weak self] app, _ in
            Task { @MainActor in
                self?.webView?.appearance = app.effectiveAppearance
                apply()
            }
        }
    }

    private func pageAlert(message: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = webView?.url?.host.map { "Message from \($0)" } ?? "Message from this page"
        alert.informativeText = String(message.prefix(4_000))
        alert.alertStyle = .informational
        return alert
    }
}

extension BrowserSession {
    /// The macOS entry point. Mirrors the designated initializer's own
    /// parameter list exactly, minus `platform` — `LimeghostShared` cannot
    /// supply a default for that parameter itself, since a default value
    /// would have to name `MacSessionPlatform`, an app-target, macOS-only
    /// type it cannot see — so every existing call site (which never named
    /// `platform` to begin with) keeps compiling against this initializer
    /// unchanged.
    convenience init(
        downloadCenter: DownloadTracking,
        searchSettings: SearchSettingsStore,
        initialURL: URL? = nil,
        isPrivate: Bool = false,
        contentBlocking: ContentRuleListProvider? = nil,
        favicons: FaviconStore? = nil,
        webFeatures: WebFeatureSettingsStore? = nil,
        websiteDataStore: WKWebsiteDataStore? = nil,
        initialPageZoom: CGFloat? = nil,
        adoptingPopupConfiguration popupConfiguration: WKWebViewConfiguration? = nil
    ) {
        let platform = MacSessionPlatform()
        self.init(
            platform: platform,
            downloadCenter: downloadCenter,
            searchSettings: searchSettings,
            initialURL: initialURL,
            isPrivate: isPrivate,
            contentBlocking: contentBlocking,
            favicons: favicons,
            webFeatures: webFeatures,
            websiteDataStore: websiteDataStore,
            initialPageZoom: initialPageZoom,
            adoptingPopupConfiguration: popupConfiguration
        )
        // Only possible now: `self.webView` does not exist until the
        // designated initializer above has returned.
        platform.webView = webView
        // The other half of the one-time appearance set that used to sit
        // inline in `init` (`webView.appearance = NSApp.effectiveAppearance`,
        // right beside where the ongoing observation used to register). That
        // observation still gets registered from inside the designated
        // initializer itself — it needs no web view to register, only to
        // react — so this is genuinely the same original code, just now in
        // two places instead of one line.
        webView.appearance = NSApp.effectiveAppearance
        // Trackpad pinch-to-zoom. `WKWebView.allowsMagnification` does not
        // exist on iOS's WKWebView at all, so it cannot be set from
        // `LimeghostShared` regardless of the platform abstraction — this is
        // the one place in the app target that still constructs every
        // session, so it is also the one place that can set it.
        webView.allowsMagnification = true
    }

    /// `<input type="file">` on macOS. `WKOpenPanelParameters` is only
    /// available from iOS 18.4, below this project's iOS 17 floor, so this
    /// method cannot be declared inside `BrowserSession.swift` itself —
    /// *that* file is typechecked against the iOS SDK too, and the parameter
    /// type alone would fail it regardless of what the body did. Declaring it
    /// here instead, in an extension in the app target (a macOS-only
    /// compilation unit), is the one way to keep it without `#if os` inside
    /// `LimeghostShared`. `WKUIDelegate`'s methods are all `@objc optional`,
    /// and Objective-C's selector-based dispatch is what finds an optional
    /// protocol method at runtime — not which file or module declared it —
    /// so this is found and called exactly as if it had been written
    /// alongside `BrowserSession`'s other `WKUIDelegate` methods.
    ///
    /// The body is the original code, unchanged: WebKit keeps the page's
    /// file input suspended until this handler is called, and dropping it
    /// deadlocks uploads for the rest of the session, so every path out —
    /// choose, cancel, no window — answers through one latch that fires
    /// exactly once.
    ///
    /// The explicit `@objc(...)` is load-bearing, not decoration: Objective-C
    /// derives this requirement's real selector from
    /// `-webView:runOpenPanelWithParameters:initiatedByFrame:completionHandler:`
    /// in WebKit's own header, dropping "Parameters" only because Swift's
    /// importer trims a label that repeats its parameter's type name
    /// (`WKOpenPanelParameters`) when it *originally* imports the protocol.
    /// That trim does not run again for a method added afterwards, in a
    /// separate extension, with no `: WKUIDelegate` of its own to re-trigger
    /// it — so Swift's automatic inference would instead synthesize
    /// `webView:runOpenPanelWith:initiatedByFrame:completionHandler:` (no
    /// "Parameters"), which WebKit never calls. Confirmed with a throwaway
    /// `session.responds(to:)` check against the real selector: it failed
    /// before this annotation and passes with it.
    @objc(webView:runOpenPanelWithParameters:initiatedByFrame:completionHandler:)
    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
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
}

/// One-shot latch for WebKit's open-panel completion handler. WebKit treats a
/// second call as a hard error and a missing call as a permanent stall, so the
/// handler is released here once and then forgotten. Moved here with
/// `runOpenPanelWith`, its only caller.
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

/// `DownloadCenter` already has a `track(_:sourceURL:)` method of exactly the
/// shape `BrowserSession` needs; this is the whole of what conforming it to
/// `DownloadTracking` (`LimeghostShared`) takes.
extension DownloadCenter: DownloadTracking {}
