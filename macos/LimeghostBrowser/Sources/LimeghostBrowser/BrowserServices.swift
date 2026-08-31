import AppKit
import LimeghostCore
import Foundation
import WebKit

/// The identifier for a browser window scene. It lives here rather than on the
/// `App` type because views that ask for a new window need it, and so does the
/// end-to-end smoke harness, which cannot compile the `@main` type without two
/// entry points colliding.
enum BrowserWindowScene {
    static let id = "limeghost-browser"
}

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

    // Shared by every profile: where files land, which search engine the
    // address bar uses, and the WebKit switches. Separating these would mean a
    // download starting in one window and appearing in none.
    let downloads: DownloadCenter
    let searchSettings: SearchSettingsStore
    let webFeatures: WebFeatureSettingsStore

    /// The profiles, and which one new windows open in.
    let profiles: ProfileStore

    /// Built once per profile and kept, because a profile's rule list should
    /// compile once and its icon cache should be one cache.
    private var perProfile: [UUID: ProfileServices] = [:]

    /// Everything one profile owns. Two profiles signed into the same site do
    /// not see each other's session, because these are genuinely separate
    /// stores rather than one store with a label on it.
    @MainActor
    final class ProfileServices {
        let profileID: UUID
        let dataStore: BrowserDataStore
        let favicons: FaviconStore
        let contentBlocking: ContentRuleListProvider
        let websiteDataStore: WKWebsiteDataStore

        init(profileID: UUID) {
            self.profileID = profileID
            let defaults = ProfileStorage.defaults(for: profileID)
            dataStore = BrowserDataStore(defaults: defaults)
            favicons = FaviconStore(directory: ProfileStorage.faviconDirectory(for: profileID))
            contentBlocking = ContentRuleListProvider(
                settings: ContentBlockingSettingsStore(defaults: defaults)
            )
            websiteDataStore = ProfileStorage.websiteDataStore(for: profileID)
        }
    }

    func services(for profileID: UUID) -> ProfileServices {
        if let existing = perProfile[profileID] { return existing }
        let built = ProfileServices(profileID: profileID)
        perProfile[profileID] = built
        return built
    }

    /// Forgets a deleted profile's services so nothing keeps writing to
    /// stores that are being erased.
    func discardServices(for profileID: UUID) {
        perProfile.removeValue(forKey: profileID)
    }

    // The profile new windows open in. Settings edits that profile's
    // bookmarks bar and blocking exceptions, the way a browser with profiles
    // does — those belong to a profile, not to the application.
    var currentServices: ProfileServices { services(for: profiles.currentProfileID) }
    var dataStore: BrowserDataStore { currentServices.dataStore }
    var contentBlocking: ContentRuleListProvider { currentServices.contentBlocking }
    var favicons: FaviconStore { currentServices.favicons }

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

    /// Which profile the window being opened belongs to, left for the scene
    /// to pick up. `openWindow` carries no arguments, so this is how a choice
    /// made in the Profiles menu reaches the window it opens.
    private var nextWindowProfileID: UUID?

    func markNextWindow(profileID: UUID) { nextWindowProfileID = profileID }

    /// Taken once, by the next window. Falls back to the current profile, so
    /// an ordinary New Window opens where the person last was.
    func takeNextWindowProfileID() -> UUID {
        defer { nextWindowProfileID = nil }
        return nextWindowProfileID ?? profiles.currentProfileID
    }

    /// Set when New Private Window is chosen, and taken by the window that
    /// opens next. `openWindow` carries no arguments of its own, so this is
    /// how the scene learns which kind of window it is building.
    private var nextWindowIsPrivate = false

    func markNextWindowPrivate() { nextWindowIsPrivate = true }

    func takeNextWindowIsPrivate() -> Bool {
        defer { nextWindowIsPrivate = false }
        return nextWindowIsPrivate
    }

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

    /// One per window, so a closing window can tear its own tabs down.
    /// `forgetWindow` alone is not enough: it runs from a SwiftUI
    /// `onDisappear`, which says the view went away rather than that the window
    /// did, and it only dropped the pairing above.
    private var windowCloseObservers: [ObjectIdentifier: NSObjectProtocol] = [:]

    func registerWindow(_ window: NSWindow?, for workspace: BrowserWorkspace) {
        let key = ObjectIdentifier(workspace)
        windowsByWorkspace[key] = WeakWindow(window: window)
        guard let window else { return }
        if let existing = windowCloseObservers[key] {
            NotificationCenter.default.removeObserver(existing)
        }
        // Delivered on the main queue, which is where this class lives, so the
        // teardown can run inline rather than being deferred into a Task the
        // closing window might not outlive.
        windowCloseObservers[key] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak workspace] _ in
            MainActor.assumeIsolated {
                workspace?.teardownForWindowClose()
            }
        }
    }

    func forgetWindow(of workspace: BrowserWorkspace) {
        let key = ObjectIdentifier(workspace)
        windowsByWorkspace.removeValue(forKey: key)
        if let observer = windowCloseObservers.removeValue(forKey: key) {
            NotificationCenter.default.removeObserver(observer)
        }
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
        downloads: DownloadCenter? = nil,
        searchSettings: SearchSettingsStore? = nil,
        webFeatures: WebFeatureSettingsStore? = nil,
        profiles: ProfileStore? = nil
    ) {
        self.downloads = downloads ?? DownloadCenter()
        self.searchSettings = searchSettings ?? SearchSettingsStore()
        self.webFeatures = webFeatures ?? WebFeatureSettingsStore()
        self.profiles = profiles ?? ProfileStore()
    }

    /// The first workspace to ask takes the saved session; later ones start
    /// with a blank tab.
    func claimSessionRestore() -> Bool {
        guard !hasRestoredSession else { return false }
        hasRestoredSession = true
        return true
    }

    /// Set when a tab is torn out mid-gesture, with the mouse still down. The
    /// window that opens then follows the pointer for the rest of the drag
    /// rather than appearing where the pointer happened to be and stopping —
    /// which is what Chrome does, and the difference between a tear-out that
    /// feels immediate and one that feels like a delayed result.
    private var nextWindowFollowsPointer = false

    func handOff(tab: BrowserTab, windowTopLeft: CGPoint?, followsPointer: Bool = false) {
        tabAwaitingWindow = tab
        originAwaitingWindow = windowTopLeft
        nextWindowFollowsPointer = followsPointer
    }

    func takeNextWindowFollowsPointer() -> Bool {
        defer { nextWindowFollowsPointer = false }
        return nextWindowFollowsPointer
    }

    /// Pages the window being opened should show. "Open in new window" and
    /// "Open all in new window" both come through here: `openWindow` carries no
    /// arguments, so what to open is left for the new window to collect.
    private var urlsAwaitingWindow: [URL] = []

    func openInNextWindow(_ urls: [URL], profileID: UUID, isPrivate: Bool) {
        urlsAwaitingWindow = urls
        markNextWindow(profileID: profileID)
        if isPrivate { markNextWindowPrivate() }
    }

    func takeURLsAwaitingWindow() -> [URL] {
        defer { urlsAwaitingWindow = [] }
        return urlsAwaitingWindow
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
