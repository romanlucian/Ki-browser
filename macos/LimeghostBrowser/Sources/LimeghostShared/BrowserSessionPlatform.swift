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

    /// Called once, immediately after `BrowserSession` builds its web view.
    /// The one-time setup only the platform can do lives here — macOS sets
    /// the web view's starting appearance and turns on trackpad
    /// pinch-to-zoom, `WKWebView.allowsMagnification`, which does not exist
    /// on iOS's `WKWebView` at all, so neither can be named from
    /// `BrowserSession` itself. It is also the one place a platform that
    /// weakly tracks its own web view — anchoring an alert or a file panel to
    /// the right window needs one — learns which web view that is.
    func prepareWebView(_ webView: WKWebView)
}
