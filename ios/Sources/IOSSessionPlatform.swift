import UIKit
import WebKit
import LimeghostShared

/// What a browsing session needs from iOS.
///
/// Every member here is one of the eight things `BrowserSessionPlatform`
/// declares, and three of them do nothing on a phone. That is the protocol
/// working rather than failing: the session does not know which platform it is
/// on, so a difference shows up as an implementation that answers "nothing to
/// do" instead of a conditional inside the browser.
@MainActor
final class IOSSessionPlatform: BrowserSessionPlatform {
    /// The web view this session owns, handed over by `prepareWebView` from
    /// inside the session's own initializer — before its delegates are wired,
    /// so a callback during the first load cannot find this nil.
    fileprivate weak var webView: WKWebView?

    /// Injected by tests so opening a `mailto:` can be observed without asking
    /// the system to launch Mail.
    var openExternalForTesting: ((URL) -> Void)?

    func openExternal(_ url: URL) {
        if let openExternalForTesting {
            openExternalForTesting(url)
            return
        }
        UIApplication.shared.open(url)
    }

    func presentAlert(message: String) async {
        await withCheckedContinuation { continuation in
            let alert = makeAlert(message: message)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                continuation.resume()
            })
            present(alert)
        }
    }

    func presentConfirm(message: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = makeAlert(message: message)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(returning: false)
            })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                continuation.resume(returning: true)
            })
            present(alert)
        }
    }

    func presentPrompt(message: String, defaultText: String?) async -> String? {
        await withCheckedContinuation { continuation in
            let alert = makeAlert(message: message)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(returning: nil)
            })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
                continuation.resume(returning: alert?.textFields?.first?.text)
            })
            present(alert)
        }
    }

    /// Nothing. WebKit presents its own document picker for `<input type=file>`
    /// on iOS, so an app-supplied one would appear on top of it.
    func chooseFiles(allowsMultiple: Bool, allowsDirectories: Bool) async -> [URL]? {
        nil
    }

    /// Nothing. Printing is not in v1, and a silent no-op is honest here in a
    /// way a half-built print sheet would not be.
    func printPage(_ webView: WKWebView) {}

    /// Nothing to observe. iOS hands a view its trait collection and updates it
    /// when the system appearance changes, so there is no notification to watch
    /// and no token for the caller to retain.
    func observeAppearance(_ apply: @escaping () -> Void) -> Any? { nil }

    /// Called from inside `BrowserSession`'s designated initializer, before its
    /// delegates are assigned.
    func prepareWebView(_ webView: WKWebView) {
        self.webView = webView
    }

    // MARK: - Presenting

    private func makeAlert(message: String) -> UIAlertController {
        UIAlertController(
            title: webView?.url?.host.map { "Message from \($0)" } ?? "Message from this page",
            message: String(message.prefix(4_000)),
            preferredStyle: .alert
        )
    }

    /// A page's dialog belongs to the window the page is in. Reaching the root
    /// controller through the active scene rather than a stored reference means
    /// a dialog cannot outlive the screen it belongs to.
    private func present(_ alert: UIAlertController) {
        guard let root = IOSPageSharing.rootViewController else { return }
        root.present(alert, animated: true)
    }
}
