import AppKit
import Foundation

/// The parts of the browser that belong to the application rather than to any
/// one window: bookmarks and history, the download list, the search choice,
/// the compiled tracker rules, the site-icon cache, and the WebKit switches.
///
/// Each window owns its own `BrowserWorkspace` — its own tabs, its own
/// selection — but they all read and write these. Giving a second window its
/// own copies would mean bookmarking a page in one window and not seeing it in
/// the other, and would compile the rule list a second time for nothing.
@MainActor
final class BrowserServices {
    /// Created on first use and never replaced. Windows come and go; these do
    /// not, and a tab torn into a new window has to keep the same download
    /// list and the same cookie/website data behind it.
    static let shared = BrowserServices()

    let dataStore: BrowserDataStore
    let downloads: DownloadCenter
    let searchSettings: SearchSettingsStore
    let contentBlocking: ContentRuleListProvider
    let favicons: FaviconStore
    let webFeatures: WebFeatureSettingsStore

    /// A tab in mid-air: removed from the window it was dragged out of and
    /// waiting for the window being opened to take it. SwiftUI's `openWindow`
    /// carries only values, and a live tab is an object holding a web view, so
    /// it is handed over here instead.
    private var tabAwaitingWindow: BrowserTab?
    /// Where that window's top-left should sit, in screen coordinates: under
    /// the pointer that dragged the tab out, not wherever macOS would cascade
    /// it. Read as a top-left because the window's height is not known until
    /// it exists.
    private var originAwaitingWindow: CGPoint?

    /// Set once the first window has taken the saved session, so a second
    /// window opens empty instead of restoring the same tabs twice.
    private(set) var hasRestoredSession = false

    /// Every open window's workspace, weakly. Settings changes and the
    /// browsing-data reset are application-wide: they have to reach the tabs
    /// in every window, not only the one that happened to be in front.
    private var registeredWorkspaces: [WeakWorkspace] = []

    private struct WeakWorkspace {
        weak var workspace: BrowserWorkspace?
    }

    func register(_ workspace: BrowserWorkspace) {
        registeredWorkspaces.removeAll { $0.workspace == nil }
        guard !registeredWorkspaces.contains(where: { $0.workspace === workspace }) else { return }
        registeredWorkspaces.append(WeakWorkspace(workspace: workspace))
    }

    var liveWorkspaces: [BrowserWorkspace] {
        registeredWorkspaces.compactMap(\.workspace)
    }

    /// Which window each workspace is showing in, so a tab dragged out of one
    /// window can be dropped into another's strip. A drag belongs to the
    /// window it started in — no other window is told about it — so the drop
    /// is resolved by asking who owns the point the pointer was let go at.
    ///
    /// Only the pairing is stored. Where the strip is on screen is read from
    /// the window's own frame at the moment of the drop, so moving or
    /// resizing a window needs no bookkeeping here.
    private var windowsByWorkspace: [ObjectIdentifier: WeakWindow] = [:]

    private struct WeakWindow {
        weak var window: NSWindow?
    }

    func registerWindow(_ window: NSWindow?, for workspace: BrowserWorkspace) {
        windowsByWorkspace[ObjectIdentifier(workspace)] = WeakWindow(window: window)
    }

    func forgetWindow(of workspace: BrowserWorkspace) {
        windowsByWorkspace.removeValue(forKey: ObjectIdentifier(workspace))
    }

    func window(for workspace: BrowserWorkspace) -> NSWindow? {
        windowsByWorkspace[ObjectIdentifier(workspace)]?.window
    }

    /// The window whose tab strip covers `point`, in screen coordinates,
    /// ignoring the one the tab came from. `stripHeight` is the strip's
    /// height in points; it sits along the top edge of the window.
    func dropTarget(
        at point: CGPoint,
        excluding source: BrowserWorkspace,
        stripHeight: CGFloat
    ) -> (BrowserWorkspace, NSWindow?)? {
        for workspace in liveWorkspaces where workspace !== source {
            guard let window = window(for: workspace), window.isVisible else { continue }
            let frame = window.frame
            let strip = CGRect(
                x: frame.minX,
                y: frame.maxY - stripHeight,
                width: frame.width,
                height: stripHeight
            )
            if strip.contains(point) { return (workspace, window) }
        }
        return nil
    }

    init(
        dataStore: BrowserDataStore? = nil,
        downloads: DownloadCenter? = nil,
        searchSettings: SearchSettingsStore? = nil,
        contentBlocking: ContentRuleListProvider? = nil,
        favicons: FaviconStore? = nil,
        webFeatures: WebFeatureSettingsStore? = nil
    ) {
        self.dataStore = dataStore ?? BrowserDataStore()
        self.downloads = downloads ?? DownloadCenter()
        self.searchSettings = searchSettings ?? SearchSettingsStore()
        self.contentBlocking = contentBlocking
            ?? ContentRuleListProvider(settings: ContentBlockingSettingsStore())
        self.favicons = favicons ?? FaviconStore()
        self.webFeatures = webFeatures ?? WebFeatureSettingsStore()
    }

    /// The first workspace to ask takes the saved session; later ones start
    /// with a blank tab.
    func claimSessionRestore() -> Bool {
        guard !hasRestoredSession else { return false }
        hasRestoredSession = true
        return true
    }

    func handOff(tab: BrowserTab, windowTopLeft: CGPoint?) {
        tabAwaitingWindow = tab
        originAwaitingWindow = windowTopLeft
    }

    /// Taken exactly once, by the next window to open.
    func takeTabAwaitingWindow() -> BrowserTab? {
        defer { tabAwaitingWindow = nil }
        return tabAwaitingWindow
    }

    /// Whether a handed-over tab is still waiting. A tab that no window ever
    /// claimed would be lost along with its web view, so the window it came
    /// from checks this and takes it back.
    var isTabStillAwaitingWindow: Bool { tabAwaitingWindow != nil }

    func takeWindowTopLeftAwaitingWindow() -> CGPoint? {
        defer { originAwaitingWindow = nil }
        return originAwaitingWindow
    }
}
