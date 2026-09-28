import LimeghostShared
import UIKit
import WebKit

/// Photographs the tab somebody is leaving, so the switcher's cards can show
/// the page rather than a grey box.
///
/// **Only the tab that was on screen, and only as it leaves.** Two things that
/// look reasonable and are not:
///
/// - *A timer.* It would photograph pages nobody is looking at, and spend
///   battery doing it, for a screen most people open a few times an hour.
/// - *Every tab when the switcher opens.* Twelve `takeSnapshot` calls at once
///   hitch the very animation they are meant to decorate, and a tab that has
///   not been on screen has nothing rendered to photograph anyway — it would
///   hand back a blank.
///
/// So a card shows a picture once its tab has been looked at, and its identity
/// square until then, which is what an unvisited site already shows elsewhere.
///
/// Lives on the phone rather than in `LimeghostShared` because `takeSnapshot`
/// hands back a `UIImage`, which has no Mac twin; the store it feeds holds
/// `CGImage`, which both platforms have. `FaviconStore` documents the same
/// split above its own ImageIO helpers.
@MainActor
enum TabPreviewCamera {
    /// Capture the workspace's selected tab, if there is one with something
    /// drawn in it. Silent and best-effort: a failure leaves the previous
    /// picture in place, and a card with no picture is a card with a square.
    static func captureSelectedTab(of workspace: BrowserWorkspace) {
        guard let tab = workspace.selectedTab else { return }
        let webView = tab.session.webView
        // A web view that has never been laid out returns a blank image, which
        // would replace a good picture with an empty one.
        guard webView.bounds.width > 1, webView.bounds.height > 1 else { return }

        let configuration = WKSnapshotConfiguration()
        // `snapshotWidth` is in points and WebKit renders straight to it, so
        // nothing is captured at full size and thrown away. Divided by the
        // screen's scale because the store's width is in pixels.
        let scale = max(webView.traitCollection.displayScale, 1)
        configuration.snapshotWidth = NSNumber(value: Double(TabPreviewStore.captureWidth / scale))

        let id = tab.id
        // Read here, not inside the task: whether this tab is private decides
        // whether its picture may be written to disk, and it must be the answer
        // for the tab that was photographed.
        let isPrivate = tab.isPrivate
        Task { @MainActor in
            guard let image = try? await webView.takeSnapshot(configuration: configuration),
                  let bitmap = image.cgImage else { return }
            workspace.tabPreviews.store(bitmap, for: id, isPrivate: isPrivate)
        }
    }
}
