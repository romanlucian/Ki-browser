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
    /// can know which web view is its own until `prepareWebView(_:)` below
    /// sets it. That happens from inside the designated initializer itself,
    /// immediately after the web view is built and before
    /// `webView.navigationDelegate`/`uiDelegate` are even assigned — not
    /// after that initializer returns, and not from the convenience
    /// initializer below. Doing it that early closed a real gap: a
    /// UI-delegate callback arriving during the first load could otherwise
    /// have found this reference still nil. Weak, like every other
    /// back-reference a delegate holds to the object that owns it.
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

    /// `<input type="file">`. This is the live macOS path: `BrowserSession
    /// .webView(_:runOpenPanelWith:initiatedByFrame:completionHandler:)`
    /// below calls `BrowserSession.chooseFiles(allowsMultiple:
    /// allowsDirectories:)`, which calls this. Both `WKOpenPanelParameters`
    /// flags — including `allowsDirectories`, the page asking for a folder
    /// rather than files — survive that trip intact, since the protocol
    /// carries both explicitly, and `webView` here is the very web view that
    /// delegate method already has in hand: set by `prepareWebView(_:)`
    /// below, from inside `BrowserSession`'s designated initializer, before
    /// this delegate method could ever be invoked. Nothing is lost by
    /// routing through the protocol.
    func chooseFiles(allowsMultiple: Bool, allowsDirectories: Bool) async -> [URL]? {
        await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = allowsMultiple
            panel.canChooseFiles = true
            panel.canChooseDirectories = allowsDirectories
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

    /// `BrowserSession.init` calls this once, right after the web view it
    /// answers for exists. Three things only macOS can do: the weak
    /// back-reference every other method above reads through `webView`, the
    /// starting appearance (the ongoing observation above only reacts to a
    /// *later* change), and trackpad pinch-to-zoom, which is not part of
    /// `BrowserSessionPlatform` because `WKWebView.allowsMagnification` does
    /// not exist on iOS's `WKWebView` at all.
    func prepareWebView(_ webView: WKWebView) {
        self.webView = webView
        webView.appearance = NSApp.effectiveAppearance
        webView.allowsMagnification = true
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
    /// type it cannot see. `BrowserWorkspace` and `BrowserTab` (also
    /// `LimeghostShared`, as of the workspace's move there) build their own
    /// `MacSessionPlatform` and call the designated initializer directly for
    /// the same reason; this convenience initializer remains for callers —
    /// tests among them — that have no reason to name a platform at all.
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
        self.init(
            platform: MacSessionPlatform(),
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
    /// The body routes through `BrowserSession.chooseFiles(allowsMultiple:
    /// allowsDirectories:)` (`MacSessionPlatform.chooseFiles(allowsMultiple:
    /// allowsDirectories:)` above does the actual `NSOpenPanel` work) rather
    /// than building the panel inline: `async`/`await` already guarantees
    /// `completionHandler` fires exactly once, so the one-shot latch the
    /// original inline version needed no longer has a job.
    ///
    /// The explicit `@objc(...)` is load-bearing, not decoration — and what
    /// it guards against is starker than a wrong selector name. Per
    /// SE-0160, a member of an extension declared outside its type's own
    /// module is not a protocol witness at all; because every `WKUIDelegate`
    /// requirement is `@objc optional`, nothing here fails to compile
    /// without the annotation — the method just becomes ordinary Swift,
    /// invisible to `objc_msgSend`. Implicit `@objc` inference does not run
    /// for it: no selector is emitted, not a differently-named one — no
    /// `__objc_catlist` section, no method list, no thunk symbol, no
    /// `runOpenPanel` selector string of any spelling. WebKit's
    /// selector-based dispatch has nothing to find, and `<input
    /// type="file">` would silently stop working with every test still
    /// green. A *bare* `@objc`, with no parentheses, is worse than no
    /// annotation at all here: inference does fire for it, but only from
    /// this extension's own Swift signature. The label-trim that drops
    /// "Parameters" runs once, when the compiler originally imports
    /// `WKUIDelegate` from WebKit's header, and does not run again for a
    /// method added afterwards, in a separate extension, with no `:
    /// WKUIDelegate` of its own to re-trigger it — so a bare `@objc` would
    /// synthesize `webView:runOpenPanelWith:initiatedByFrame:completionHandler:`
    /// (no "Parameters"), a selector WebKit never calls. Only the explicit
    /// form below matches the real one, which WebKit's own header declares
    /// as `-webView:runOpenPanelWithParameters:initiatedByFrame:completionHandler:`.
    /// Confirmed by
    /// `BrowserBehaviorTests.testASessionAnswersWebKitsOpenPanelRequest`,
    /// which asserts `responds(to:)` the real selector: it failed before this
    /// annotation and passes with it.
    @objc(webView:runOpenPanelWithParameters:initiatedByFrame:completionHandler:)
    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        Task { @MainActor in
            completionHandler(await chooseFiles(
                allowsMultiple: parameters.allowsMultipleSelection,
                allowsDirectories: parameters.allowsDirectories
            ))
        }
    }
}

/// `DownloadCenter` already has a `track(_:sourceURL:)` method of exactly the
/// shape `BrowserSession` needs; this is the whole of what conforming it to
/// `DownloadTracking` (`LimeghostShared`) takes.
extension DownloadCenter: DownloadTracking {}
