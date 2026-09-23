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
/// Answers one page dialog, once. A dialog is answered by the button tapped,
/// or — when it could not be shown — by `unshowable`, and whichever comes
/// first is the answer: a continuation resumed twice ends the app, and one
/// never resumed leaves the page's script waiting forever.
private final class DialogReply<Value> {
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func send(_ value: Value) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}

@MainActor
final class IOSSessionPlatform: BrowserSessionPlatform {
    /// The web view this session owns, handed over by `prepareWebView` from
    /// inside the session's own initializer — before its delegates are wired,
    /// so a callback during the first load cannot find this nil.
    fileprivate weak var webView: WKWebView?

    /// Injected by tests so opening a `mailto:` can be observed without asking
    /// the system to launch Mail.
    var openExternalForTesting: ((URL) -> Void)?

    /// Where a page's dialog is shown. Injected by tests; the app's is the
    /// topmost controller of its window (`topmostPresenter`).
    var presenter: () -> UIViewController? = { IOSSessionPlatform.topmostPresenter() }

    func openExternal(_ url: URL) {
        if let openExternalForTesting {
            openExternalForTesting(url)
            return
        }
        UIApplication.shared.open(url)
    }

    // A page's script stops at `alert()`, `confirm()` and `prompt()` until it
    // is answered, so each of these answers exactly once: from the button
    // tapped, or — when the dialog cannot be shown at all — at once, the way a
    // person dismissing it would. An unanswered dialog froze the page for as
    // long as its tab lived.

    /// This tab's record of which site asked how often; see `PageDialogGuard`.
    /// Every dialog has to be answered before anything else on the screen can
    /// be touched, so a page asking in a loop held the whole app.
    private var dialogs = PageDialogGuard()

    func presentAlert(message: String) async {
        let host = webView?.url?.host
        guard !dialogs.isSilenced(host: host) else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let reply = DialogReply(continuation)
            let alert = makeAlert(message: message)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in reply.send(()) })
            offerToStop(alert, host: host) { reply.send(()) }
            present(alert) { reply.send(()) }
        }
    }

    func presentConfirm(message: String) async -> Bool {
        let host = webView?.url?.host
        guard !dialogs.isSilenced(host: host) else { return false }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let reply = DialogReply(continuation)
            let alert = makeAlert(message: message)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in reply.send(false) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in reply.send(true) })
            offerToStop(alert, host: host) { reply.send(false) }
            present(alert) { reply.send(false) }
        }
    }

    func presentPrompt(message: String, defaultText: String?) async -> String? {
        let host = webView?.url?.host
        guard !dialogs.isSilenced(host: host) else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let reply = DialogReply(continuation)
            let alert = makeAlert(message: message)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in reply.send(nil) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
                reply.send(alert?.textFields?.first?.text)
            })
            offerToStop(alert, host: host) { reply.send(nil) }
            present(alert) { reply.send(nil) }
        }
    }

    /// From a site's second dialog on, a way to stop them: this dialog is
    /// answered as a dismissal would answer it, and the site's later ones are
    /// answered without being shown.
    private func offerToStop(_ alert: UIAlertController, host: String?, answer: @escaping () -> Void) {
        guard dialogs.willShow(host: host) else { return }
        alert.addAction(UIAlertAction(title: "Don’t Allow More Dialogs", style: .destructive) { [weak self] _ in
            self?.dialogs.silence(host: host)
            answer()
        })
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

    /// Shows `alert` over whatever is on top, or calls `unshowable`.
    ///
    /// UIKit refuses a presentation silently — from a controller that is
    /// already presenting, one that is not in a window, or one still arriving
    /// or leaving — and says so only in the console. A sheet in the middle of
    /// appearing is waited for, briefly, since a page does not wait for an
    /// animation before it asks; anything else that cannot present is
    /// answered at once.
    private func present(_ alert: UIAlertController, waitsLeft: Int = 20, unshowable: @escaping () -> Void) {
        guard let host = presenter() else {
            unshowable()
            return
        }
        // A sheet still arriving, or one on its way out — the tab switcher
        // closing as the page asks — settles in a moment, and UIKit refuses
        // to present over either until it has.
        let settling = host.isBeingPresented || host.isBeingDismissed
            || host.presentedViewController?.isBeingDismissed == true
        if settling {
            guard waitsLeft > 0 else {
                unshowable()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self else {
                    unshowable()
                    return
                }
                self.present(alert, waitsLeft: waitsLeft - 1, unshowable: unshowable)
            }
            return
        }
        guard host.viewIfLoaded?.window != nil else {
            unshowable()
            return
        }
        host.present(alert, animated: true)
        if alert.presentingViewController == nil { unshowable() }
    }

    /// A page's dialog belongs to the window the page is in, over whatever
    /// that window is already showing. The root of the window is usually
    /// presenting something here — the tab switcher, the page menu, Bookmarks,
    /// History and the address sheet are all sheets — and UIKit will not
    /// present from a controller that already is, so the dialog goes on the
    /// top of that stack. Reached through the scene rather than a stored
    /// reference, so a dialog cannot outlive the screen it belongs to; an
    /// inactive scene still counts, because Control Center pulled down over
    /// the page is no reason to answer a page's question for the person.
    static func topmostPresenter() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
