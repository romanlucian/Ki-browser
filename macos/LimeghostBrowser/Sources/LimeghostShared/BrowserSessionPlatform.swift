import Foundation
import WebKit

/// The handful of things a browsing session needs from the operating system
/// that macOS and iOS do differently: opening an address this browser does not
/// render, the three dialogs a page can raise, a file picker, printing, and
/// following the system's light/dark choice.
///
/// This exists so `BrowserSession` itself contains no AppKit and no UIKit. Its
/// macOS implementation is the code that used to be inline in the session,
/// moved rather than rewritten.
@MainActor
public protocol BrowserSessionPlatform: AnyObject {
    /// A `mailto:`, `tel:` or other scheme the browser does not render.
    func openExternal(_ url: URL)

    /// `window.alert`. Returns when the person has dismissed it.
    func presentAlert(message: String) async

    /// `window.confirm`. `true` only if the person accepted.
    func presentConfirm(message: String) async -> Bool

    /// `window.prompt`. `nil` if the person cancelled.
    func presentPrompt(message: String, defaultText: String?) async -> String?

    /// `<input type="file">`. `allowsDirectories` is the page asking for a
    /// folder (`<input type="file" webkitdirectory>`) rather than files —
    /// carried explicitly because dropping it would be a real behaviour
    /// change, not a cosmetic one. iOS returns `nil`: WebKit presents its own
    /// picker there, so the app must not present a second one.
    func chooseFiles(allowsMultiple: Bool, allowsDirectories: Bool) async -> [URL]?

    /// Print this page. iOS does nothing in v1; printing is not in scope.
    func printPage(_ webView: WKWebView)

    /// Call `apply` whenever the system's appearance changes. The returned
    /// value is the observation to retain, or `nil` where the platform needs
    /// none — iOS follows its trait collection without being asked.
    func observeAppearance(_ apply: @escaping () -> Void) -> Any?

    /// Whether the click behind `action` asked for the link in a tab of its
    /// own, and where. `nil` for everything else — a plain click, a script, a
    /// form — which stays in the tab it happened in.
    func newTabPlacement(for action: WKNavigationAction) -> NewTabPlacement?

    /// Called once, immediately after `BrowserSession` builds its web view.
    /// The one-time setup only the platform can do lives here — macOS sets
    /// the web view's starting appearance and turns on trackpad
    /// pinch-to-zoom, `WKWebView.allowsMagnification`, which does not exist
    /// on iOS's `WKWebView` at all, so neither can be named from
    /// `BrowserSession` itself. It is also the one place a platform that
    /// weakly tracks its own web view — anchoring an alert or a file panel to
    /// the right window needs one — learns which web view that is.
    func prepareWebView(_ webView: WKWebView)

    /// Called once, **before** the web view exists, on the configuration it is
    /// about to be built from. Anything that can only be set before construction
    /// belongs here rather than in `prepareWebView`, which is handed a web view
    /// already made.
    ///
    /// The phone needs it and the Mac does not: iOS defaults a web view to
    /// refusing autoplay and to playing video outside the page, in its own
    /// player with a scrubber and a mute button, and neither default can be
    /// changed afterwards. macOS plays a page's video in the page already.
    ///
    /// Not applied to a popup, which is built from the configuration WebKit
    /// hands over and inherits its opener's settings along with its data store.
    func prepareConfiguration(_ configuration: WKWebViewConfiguration)
}

/// Where a link somebody opened in a tab of its own should go.
public enum NewTabPlacement: Equatable, Sendable {
    /// Behind the page being read.
    case background
    /// In front of it.
    case foreground
}

extension BrowserSessionPlatform {
    public func newTabPlacement(for action: WKNavigationAction) -> NewTabPlacement? { nil }

    /// Nothing, which is right for every platform but the phone — and keeps a
    /// test's stand-in platform from having to know this exists at all.
    public func prepareConfiguration(_ configuration: WKWebViewConfiguration) {}
}
