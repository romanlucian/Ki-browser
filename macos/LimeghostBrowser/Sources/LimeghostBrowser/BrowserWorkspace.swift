import os
import AppKit
import LimeghostCore
import Combine
import Foundation
import WebKit

/// Which full-page surface a tab shows while `BrowserSession.loadState` is
/// `.startPage` (D6). Deliberately not persisted: a restored or brand-new tab
/// always opens on the AI guide, which is the product's start-page promise.
enum StartSurface {
    case aiHome
    case bookmarksHome
    case historyHome
}

@MainActor
final class BrowserTab: ObservableObject, Identifiable {
    let id: UUID
    let session: BrowserSession
    /// Find in page belongs to the tab, like its page does: two tabs searching
    /// for different words do not share a bar or a result.
    let find: PageFindController
    let isPrivate: Bool
    @Published private(set) var displayTitle: String
    @Published private(set) var lastActivatedAt: Date
    @Published var startSurface: StartSurface = .aiHome
    /// The page as the extractor read it, while Reader is open on this tab.
    ///
    /// Per tab, like `find` and `startSurface`: one tab reading an article and
    /// another on a live page is the ordinary case. Cleared on every
    /// navigation, because the article belongs to the document that produced
    /// it and showing it over a different page would be a quiet lie.
    @Published var readerArticle: ReaderArticle?
    /// The tab group this tab belongs to. `BrowserWorkspace` owns every write
    /// so grouped tabs stay contiguous in the strip.
    @Published fileprivate(set) var groupID: UUID?
    /// Whether this tab is pinned. `BrowserWorkspace` owns every write so the
    /// pinned run stays left of the unpinned one and a pinned tab never ends
    /// up in a group — see `BrowserWorkspace.pinTab`/`unpinTab`.
    @Published fileprivate(set) var isPinned: Bool

    private var pendingRestoreURL: URL?
    private var cancellables: Set<AnyCancellable> = []

    init(
        id: UUID = UUID(),
        title: String = "New Tab",
        initialURL: URL? = nil,
        loadImmediately: Bool = true,
        lastActivatedAt: Date = Date(),
        downloadCenter: DownloadCenter,
        searchSettings: SearchSettingsStore,
        isPrivate: Bool = false,
        groupID: UUID? = nil,
        isPinned: Bool = false,
        contentBlocking: ContentRuleListProvider? = nil,
        favicons: FaviconStore? = nil,
        webFeatures: WebFeatureSettingsStore? = nil,
        websiteDataStore: WKWebsiteDataStore? = nil,
        adoptingPopupConfiguration popupConfiguration: WKWebViewConfiguration? = nil
    ) {
        self.id = id
        self.displayTitle = title
        self.lastActivatedAt = lastActivatedAt
        self.isPrivate = isPrivate
        self.groupID = groupID
        self.isPinned = isPinned
        // Built as a local first: the find controller needs the session's web
        // view, and `self` cannot be read until every stored property is set.
        let resolvedSession: BrowserSession
        if let popupConfiguration {
            // A `window.open()` popup: WebKit built the configuration and owns
            // the first navigation, so this tab adopts that web view rather
            // than making one of its own.
            resolvedSession = BrowserSession(
                downloadCenter: downloadCenter,
                searchSettings: searchSettings,
                isPrivate: isPrivate,
                contentBlocking: contentBlocking,
                favicons: favicons,
                webFeatures: webFeatures,
                websiteDataStore: websiteDataStore,
                adoptingPopupConfiguration: popupConfiguration
            )
        } else if loadImmediately {
            resolvedSession = BrowserSession(
                downloadCenter: downloadCenter,
                searchSettings: searchSettings,
                initialURL: initialURL,
                isPrivate: isPrivate,
                contentBlocking: contentBlocking,
                favicons: favicons,
                webFeatures: webFeatures,
                websiteDataStore: websiteDataStore
            )
        } else {
            resolvedSession = BrowserSession(
                downloadCenter: downloadCenter,
                searchSettings: searchSettings,
                isPrivate: isPrivate,
                contentBlocking: contentBlocking,
                favicons: favicons,
                webFeatures: webFeatures,
                websiteDataStore: websiteDataStore
            )
            pendingRestoreURL = initialURL
        }
        session = resolvedSession
        find = PageFindController(webView: resolvedSession.webView)

        session.$pageTitle
            .dropFirst()
            .sink { [weak self] title in
                guard let self else { return }
                if title != "New Tab" || self.pendingRestoreURL == nil {
                    self.displayTitle = title
                }
            }
            .store(in: &cancellables)

        session.$currentURLString
            .dropFirst()
            .sink { [weak self] value in
                if !value.isEmpty { self?.pendingRestoreURL = nil }
            }
            .store(in: &cancellables)

        // The same counter Copy for AI checks before putting anything on the
        // clipboard. A page that moves invalidates what was read from it.
        session.$navigationVersion
            .dropFirst()
            .sink { [weak self] _ in self?.readerArticle = nil }
            .store(in: &cancellables)
    }

    /// Reads the page in front of the reader, or says why it could not.
    ///
    /// Copy for AI and Reader both arrive here. One extraction, one
    /// `ReaderArticle`, two uses — which is what keeps Reader's claim true:
    /// the text on screen is the text on the clipboard, not a second opinion
    /// about the same page.
    ///
    /// On the tab rather than in a view because two views need it, and because
    /// the article belongs to the page this tab is showing.
    func readCurrentPage(verb: String) async -> ReaderArticle? {
        guard WebURLPolicy.validatedURL(session.currentURLString) != nil else {
            session.showPageNotice("There is no web page in this tab to \(verb).")
            return nil
        }
        // The page can move while it is being read. Acting on what the reader
        // has already navigated away from is worse than doing nothing, because
        // nothing about the result would say so.
        let expectedNavigationVersion = session.navigationVersion
        guard let page = try? await session.extractPage() else {
            session.showPageNotice("Limeghost could not read enough text on this page to \(verb).")
            return nil
        }
        guard session.navigationVersion == expectedNavigationVersion else {
            session.showPageNotice("The page changed while Limeghost was reading it.")
            return nil
        }
        guard let article = ReaderArticle(page: page) else {
            session.showPageNotice("Limeghost found no readable text on this page.")
            return nil
        }
        return article
    }

    /// Puts an article already read on the clipboard.
    ///
    /// Takes the article rather than reading the page again, so Reader's own
    /// Copy button copies precisely the words on screen — the guarantee stops
    /// depending on two extractions agreeing.
    func copyArticleForAI(_ article: ReaderArticle) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(article.clipboardPayload, forType: .string)
        if let notice = article.copyNotice {
            session.showPageNotice(notice)
        }
    }

    var persistenceRecord: BrowserTabRecord {
        // Web addresses only. A tab showing a file the person opened would
        // otherwise write their local path into the saved session — and
        // `restorableURL` refuses to reopen it anyway, so it would be a
        // filesystem path stored on disk for nothing.
        let liveURL = session.currentURLString.nilIfEmpty
            .flatMap { WebURLPolicy.validatedURL($0)?.absoluteString }
        return BrowserTabRecord(
            id: id,
            url: liveURL ?? pendingRestoreURL?.absoluteString,
            title: displayTitle,
            lastActivatedAt: lastActivatedAt,
            groupID: groupID,
            isPinned: isPinned
        )
    }

    /// The host whose icon this tab should show.
    ///
    /// A restored tab knows where it is going before it has been there, and its
    /// icon — if there is one — was already captured on a real visit. Reading
    /// the pending address lets the strip show that cached icon straight away
    /// instead of a grey square, without loading the page and without fetching
    /// anything: it is a cache read, not a request.
    var iconHost: String {
        if let host = URL(string: session.currentURLString)?.host, !host.isEmpty {
            return host
        }
        return pendingRestoreURL?.host ?? ""
    }

    func activate() {
        lastActivatedAt = Date()
        if let pendingRestoreURL {
            self.pendingRestoreURL = nil
            session.load(pendingRestoreURL)
        }
    }

    /// The Home button and the error view's Start Page action. Home always
    /// means the AI guide, whatever surface this tab happened to show last.
    /// The Home button. Where it lands is a preference; a *new tab* is not,
    /// and always opens the AI guide, which is what this browser is for.
    func goHome() {
        let preferences = BrowserPreferences.shared
        switch preferences.homeTarget {
        case .aiGuide:
            startSurface = .aiHome
            session.showStartPage()
        case .bookmarks:
            startSurface = .bookmarksHome
            session.showStartPage()
        case .specificPage:
            // An address that no longer parses must not strand Home on a blank
            // tab: the guide is the honest fallback, and Settings still shows
            // what was typed so it can be corrected.
            if let url = preferences.homeURL {
                session.load(url)
            } else {
                startSurface = .aiHome
                session.showStartPage()
            }
        }
    }

    /// Shows the full-page bookmarks home on this tab's start surface.
    func showBookmarksHome() {
        startSurface = .bookmarksHome
        session.showStartPage()
    }

    /// Shows the full-page history surface on this tab's start surface.
    func showHistoryHome() {
        startSurface = .historyHome
        session.showStartPage()
    }

    func teardown() {
        cancellables.removeAll()
        find.teardown()
        session.teardown()
    }
}

@MainActor
final class BrowserWorkspace: ObservableObject {
    @Published private(set) var tabs: [BrowserTab] = []
    /// Tab groups in creation order. A group exists only while at least one
    /// tab belongs to it; closing or ungrouping the last member removes it.
    @Published private(set) var tabGroups: [TabGroupRecord] = []
    @Published var selectedTabID: UUID?
    /// The group whose editor the strip should present. Set when a group is
    /// created so it can be named straight away, from the Tabs menu as well as
    /// from the strip; the strip clears it when the editor closes.
    @Published var pendingGroupEditorID: UUID?
    @Published var focusAddressRequest = 0
    /// Whether the selected tab currently shows a page the Print command can
    /// send to a printer. Republished from that tab's session so the menu item
    /// disables itself on the start surfaces instead of offering a blank job.
    @Published private(set) var canPrintSelectedPage = false
    /// Mirrors the selected tab's history and loading state so the Back,
    /// Forward, and Stop menu items disable themselves when they cannot act.
    @Published private(set) var canGoBackInSelectedTab = false
    @Published private(set) var canGoForwardInSelectedTab = false
    @Published private(set) var isSelectedTabLoading = false
    @Published private(set) var bookmarkLibraryRequest = 0
    @Published private(set) var bookmarkFolderRequestID = UUID()
    private(set) var requestedBookmarkFolderParentID: UUID?
    /// Bumped by the Bookmarks menu's "Import Bookmarks…" command. The
    /// toolbar — always present regardless of which surface the selected tab
    /// is showing — watches this and presents the import sheet.
    @Published private(set) var bookmarkImportRequestID = UUID()

    let downloads: DownloadCenter
    let dataStore: BrowserDataStore
    let searchSettings: SearchSettingsStore
    let contentBlocking: ContentRuleListProvider
    /// Site icons captured during real visits, shared by every tab so a site
    /// is fetched at most once per run (see `FaviconStore` for the policy).
    let favicons: FaviconStore
    /// HTTPS upgrading and the Web Inspector switch, shared so a change in
    /// Settings reaches tabs that are already open.
    let webFeatures: WebFeatureSettingsStore
    /// The profile this window belongs to. A window keeps it for life:
    /// swapping a live window's cookie store underneath its open pages would
    /// mean tearing down every web view in it.
    let profileID: UUID
    /// This profile's cookies and logins, handed to every ordinary tab.
    private let websiteDataStore: WKWebsiteDataStore?

    /// A tab that was closed and can be brought back. Deliberately in memory
    /// only: a closed tab reappearing after a relaunch is a surprise, and for
    /// a private tab it would be a leak. Private tabs are never recorded.
    struct ClosedTab: Equatable {
        let url: String
        let title: String
        let index: Int
        let groupID: UUID?
    }

    private(set) var closedTabs: [ClosedTab] = []
    private static let closedTabLimit = 10

    private var tabSubscriptions: [UUID: AnyCancellable] = [:]
    /// Whether this window's tabs are the ones written back as the saved
    /// session. Only the window that restored it writes to it, and a private
    /// window never does.
    private let persistsSession: Bool
    /// A private window: every tab it opens is private, so they share the
    /// ephemeral WebKit store, leave no history, and are not written to the
    /// saved session. Opening a normal tab from here is deliberately not
    /// possible — a window is one thing or the other, as it is in Safari.
    let isPrivate: Bool
    private var downloadSubscription: AnyCancellable?
    private var dataStoreSubscription: AnyCancellable?
    private var contentBlockingSubscription: AnyCancellable?
    private var persistenceTask: Task<Void, Never>?
    /// The assistant beside the page. One per window; see `AICompanion`.
    let aiCompanion: AICompanion
    private var aiCompanionSubscription: AnyCancellable?

    init(
        dataStore: BrowserDataStore? = nil,
        downloads: DownloadCenter? = nil,
        searchSettings: SearchSettingsStore? = nil,
        contentBlocking: ContentRuleListProvider? = nil,
        favicons: FaviconStore? = nil,
        webFeatures: WebFeatureSettingsStore? = nil,
        /// Only the first window takes the saved session. A second window
        /// restoring the same tabs would show them twice and then race the
        /// first one writing the session back.
        restoresSession: Bool = true,
        /// A tab dragged out of another window. It arrives alive, so this
        /// window opens showing that page rather than a blank one.
        adopting: BrowserTab? = nil,
        isPrivate: Bool = false,
        profileID: UUID = BrowserProfileRecord.defaultID,
        websiteDataStore: WKWebsiteDataStore? = nil
    ) {
        self.profileID = profileID
        self.websiteDataStore = websiteDataStore
        self.isPrivate = isPrivate
        self.persistsSession = restoresSession && !isPrivate
        let resolvedDataStore = dataStore ?? BrowserDataStore()
        let resolvedDownloads = downloads ?? DownloadCenter()
        let resolvedSearchSettings = searchSettings ?? SearchSettingsStore()
        // Created before any tab so every web view can register with it while
        // the first rule-list compile is still running.
        let resolvedContentBlocking = contentBlocking
            ?? ContentRuleListProvider(settings: ContentBlockingSettingsStore())
        let resolvedFavicons = favicons ?? FaviconStore()
        let resolvedWebFeatures = webFeatures ?? WebFeatureSettingsStore()
        self.webFeatures = resolvedWebFeatures
        self.dataStore = resolvedDataStore
        self.downloads = resolvedDownloads
        self.searchSettings = resolvedSearchSettings
        self.contentBlocking = resolvedContentBlocking
        self.favicons = resolvedFavicons
        let chosenTool = AICompanion.choices.first { $0.id == resolvedDataStore.aiCompanionToolID }
            ?? AICompanion.choices.first
            ?? AIToolCatalog.tools[0]
        aiCompanion = AICompanion(
            tool: chosenTool,
            makeSession: { [downloads = resolvedDownloads, search = resolvedSearchSettings,
                            blocking = resolvedContentBlocking, icons = resolvedFavicons,
                            features = resolvedWebFeatures, store = websiteDataStore, isPrivate] _, url in
                BrowserSession(
                    downloadCenter: downloads,
                    searchSettings: search,
                    initialURL: url,
                    isPrivate: isPrivate,
                    contentBlocking: blocking,
                    favicons: icons,
                    webFeatures: features,
                    websiteDataStore: store
                )
            },
            rememberChoice: { [weak resolvedDataStore] id in resolvedDataStore?.aiCompanionToolID = id }
        )

        downloadSubscription = resolvedDownloads.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        dataStoreSubscription = resolvedDataStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        contentBlockingSubscription = resolvedContentBlocking.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        // A link clicked inside the assistant belongs in a tab, not in the panel:
        // navigating the panel away from ChatGPT is how a conversation is lost.
        // Popups still adopt WebKit's own configuration, because that is what lets
        // a provider's sign-in report back to the page that opened it.
        aiCompanionSubscription = aiCompanion.$live.sink { [weak self] sessions in
            guard let self else { return }
            for session in sessions.values {
                session.onRequestNewTab = { [weak self] url in
                    self?.addTab(url: url, isPrivate: self?.isPrivate ?? false)
                }
                session.onRequestPopupWebView = { [weak self] configuration in
                    self?.adoptPopupTab(configuration: configuration, isPrivate: self?.isPrivate ?? false)
                }
            }
        }

        // A private window opens blank: it adopts nothing and restores
        // nothing, because neither would be private.
        if !isPrivate, let adopting {
            // Its group belongs to the window it came from.
            adopting.groupID = nil
            tabs = [adopting]
            selectedTabID = adopting.id
        } else if !isPrivate, restoresSession,
                  let restored = resolvedDataStore.loadWorkspace(),
                  !restored.tabs.isEmpty {
            let selectedID = restored.selectedTabID ?? restored.tabs.first?.id
            let reloadEverything = resolvedDataStore.reloadsRestoredTabs
            tabGroups = restored.groups
            tabs = restored.tabs.map { record in
                BrowserTab(
                    id: record.id,
                    title: record.title,
                    initialURL: record.restorableURL,
                    loadImmediately: reloadEverything || record.id == selectedID,
                    lastActivatedAt: record.lastActivatedAt,
                    downloadCenter: resolvedDownloads,
                    searchSettings: resolvedSearchSettings,
                    groupID: record.groupID,
                    isPinned: record.isPinned,
                    contentBlocking: resolvedContentBlocking,
                    favicons: resolvedFavicons,
                    webFeatures: resolvedWebFeatures,
                    websiteDataStore: websiteDataStore
                )
            }
            selectedTabID = tabs.contains(where: { $0.id == selectedID }) ? selectedID : tabs.first?.id
            // The restored selection has to be a tab the strip actually shows.
            if let group = selectedTab?.groupID {
                setCollapsed(false, forGroup: group)
            }
        } else {
            // Settings → General can open a chosen page at launch. Never in a
            // private window, which adopts and restores nothing by design, and
            // only once per launch — see `takeStartupURL`.
            let launchURL = isPrivate ? nil : BrowserPreferences.shared.takeStartupURL()
            let tab = BrowserTab(
                initialURL: launchURL,
                downloadCenter: resolvedDownloads,
                searchSettings: resolvedSearchSettings,
                isPrivate: isPrivate,
                contentBlocking: resolvedContentBlocking,
                favicons: resolvedFavicons,
                webFeatures: resolvedWebFeatures,
                websiteDataStore: websiteDataStore
            )
            tabs = [tab]
            selectedTabID = tab.id
        }

        tabs.forEach(configure)
        selectedTab?.activate()
        observeSelectedPagePrintability()
        observeSelectedTabNavigation()
    }

    deinit {
        persistenceTask?.cancel()
    }

    /// Called when this window is closing.
    ///
    /// Nothing else tore a window's tabs down: closing a *tab* calls
    /// `teardown`, but closing the *window* only dropped a dictionary entry, so
    /// every web view in it survived — and a page that was playing kept playing,
    /// audible, with no window left to stop it. The assistant panel is torn down
    /// too, because its web views are just as capable of holding audio.
    /// True from the moment this window's close teardown runs until the window
    /// is visibly on screen again. It makes the teardown idempotent, and it
    /// keeps anything that happens *after* the teardown — the fresh tab created
    /// below fires the ordinary persistence machinery — from overwriting the
    /// session that was saved on the way out.
    private var closedForWindow = false

    func teardownForWindowClose() {
        guard !closedForWindow else { return }
        Logger(subsystem: "com.clearframe.browser", category: "window-close")
            .info("teardownForWindowClose tabs=\(self.tabs.count, privacy: .public)")
        persistNow()
        closedForWindow = true
        persistenceTask?.cancel()
        persistenceTask = nil
        tabs.forEach { $0.teardown() }
        tabSubscriptions.removeAll()
        tabs = []
        aiCompanion.teardown()
        // SwiftUI does not always discard a closed window: the last window of a
        // WindowGroup is merely hidden, and clicking the Dock icon brings the
        // same scene back. What comes back must be a clean window, not a shell
        // of torn-down web views — so the workspace resets to one fresh tab,
        // exactly the state a genuinely new window starts in.
        let fresh = makeTab(url: nil, isPrivate: isPrivate)
        tabs = [fresh]
        configure(fresh)
        selectedTabID = fresh.id
    }

    /// The window is on screen again — a hidden scene SwiftUI revived. From
    /// here on it is an ordinary window: it persists its session and can be
    /// torn down again when it next disappears.
    func windowIsVisibleAgain() {
        closedForWindow = false
    }

    /// Follows the selection, then that tab's load state. Only the print
    /// question is republished here; forwarding every session change would
    /// redraw the whole window on each progress tick.
    private func observeSelectedPagePrintability() {
        $selectedTabID
            .map { [weak self] id -> AnyPublisher<Bool, Never> in
                guard let session = self?.tabs.first(where: { $0.id == id })?.session else {
                    return Just(false).eraseToAnyPublisher()
                }
                return session.$loadState.map { $0 == .content }.eraseToAnyPublisher()
            }
            .switchToLatest()
            .removeDuplicates()
            .assign(to: &$canPrintSelectedPage)
    }

    /// Same shape as the printability observer, for the three values the
    /// Back, Forward, Reload, and Stop menu items read.
    private func observeSelectedTabNavigation() {
        selectedSessionPublisher { $0.$canGoBack.eraseToAnyPublisher() }
            .assign(to: &$canGoBackInSelectedTab)
        selectedSessionPublisher { $0.$canGoForward.eraseToAnyPublisher() }
            .assign(to: &$canGoForwardInSelectedTab)
        selectedSessionPublisher { $0.$isLoading.eraseToAnyPublisher() }
            .assign(to: &$isSelectedTabLoading)
    }

    private func selectedSessionPublisher(
        _ value: @escaping (BrowserSession) -> AnyPublisher<Bool, Never>
    ) -> AnyPublisher<Bool, Never> {
        $selectedTabID
            .map { [weak self] id -> AnyPublisher<Bool, Never> in
                guard let session = self?.tabs.first(where: { $0.id == id })?.session else {
                    return Just(false).eraseToAnyPublisher()
                }
                return value(session)
            }
            .switchToLatest()
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    var selectedTab: BrowserTab? {
        tabs.first { $0.id == selectedTabID }
    }

    var canCloseTab: Bool { !tabs.isEmpty }

    /// - Parameter isPrivate: left unset, a tab is as private as its window.
    ///   A private window has no way to open a normal tab, which is the point
    ///   of it being a window rather than a tab.
    /// The person has asked to see a page.
    ///
    /// One method called from every door that opens one, because there is no
    /// honest single choke point: telling "somebody asked for this" apart from
    /// "the page redirected itself" needs an explicit signal either way. What
    /// stops an eleventh door forgetting the rule is a test per door, not
    /// cleverness here.
    ///
    /// Deliberately not called by: selecting a tab that already exists, a
    /// provider's sign-in popup, or reloading — none of those is a request for
    /// a *different* page, and moving the assistant for them would be the
    /// interface acting on its own.
    func makeRoomForPage() {
        aiCompanion.makeRoomForPage()
    }

    func addTab(url: URL? = nil, select: Bool = true, isPrivate: Bool? = nil) {
        let tab = makeTab(url: url, isPrivate: isPrivate ?? self.isPrivate)
        tabs.append(tab)
        configure(tab)
        if select {
            selectTab(tab.id)
            // Only for a tab somebody is being sent to. Switching between tabs
            // that already exist leaves the assistant exactly as it was.
            makeRoomForPage()
        }
        schedulePersistence()
    }

    /// "New tab to the right". The new tab inherits the anchor's group, so
    /// opening a tab next to a grouped one lands inside that group instead of
    /// splitting its run in two. A new tab is never pinned, so one opened
    /// beside a pinned anchor lands just outside the pinned run rather than
    /// inside it — `enforcePinnedTabsPrecedeUnpinnedTabs` is what guarantees
    /// that instead of a special case here.
    func addTab(after anchorID: UUID) {
        guard let anchorIndex = tabs.firstIndex(where: { $0.id == anchorID }) else {
            addTab()
            return
        }
        let anchor = tabs[anchorIndex]
        let tab = makeTab(url: nil, isPrivate: anchor.isPrivate)
        tab.groupID = anchor.groupID
        tabs.insert(tab, at: anchorIndex + 1)
        enforcePinnedTabsPrecedeUnpinnedTabs()
        configure(tab)
        selectTab(tab.id)
        makeRoomForPage()
        schedulePersistence()
    }

    /// Copy for AI, reached from the Page menu and ⇧⌘C.
    ///
    /// The toolbar carried this on an icon until September 1, 2026.
    /// `doc.on.doc` named neither AI nor copying to anybody who had not been
    /// told, and once Reader existed there were two ways to copy one page a
    /// toolbar apart. The visible, labelled path is now Reader's own button.
    ///
    /// Prefers the article already on screen: while Reader is open, copying
    /// must produce the words being read rather than a second extraction of a
    /// page whose script may have changed it since.
    func copySelectedPageForAI() async {
        guard let tab = selectedTab else { return }
        let article: ReaderArticle?
        if let open = tab.readerArticle {
            article = open
        } else {
            article = await tab.readCurrentPage(verb: "copy")
        }
        guard let article else { return }
        tab.copyArticleForAI(article)
    }

    func selectTab(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        // A tab the strip is hiding cannot be the active one: choosing one
        // from ⌘1-⌘9, a popup, or a menu opens its group back up.
        if let groupID = tab.groupID { setCollapsed(false, forGroup: groupID) }
        selectedTabID = id
        selectedTab?.activate()
        schedulePersistence()
    }

    /// A workspace built on the services the whole application shares, so a
    /// second window sees the same bookmarks, history, downloads and site
    /// icons as the first.
    /// A workspace for one window, in one profile. Bookmarks, history, site
    /// icons, per-site exceptions and logins come from that profile; the
    /// download list, the search choice and the WebKit switches are shared by
    /// all of them.
    convenience init(
        services: BrowserServices,
        restoresSession: Bool,
        adopting: BrowserTab? = nil,
        isPrivate: Bool = false,
        profileID: UUID
    ) {
        let profile = services.services(for: profileID)
        self.init(
            dataStore: profile.dataStore,
            downloads: services.downloads,
            searchSettings: services.searchSettings,
            contentBlocking: profile.contentBlocking,
            favicons: profile.favicons,
            webFeatures: services.webFeatures,
            restoresSession: restoresSession,
            adopting: adopting,
            isPrivate: isPrivate,
            profileID: profileID,
            websiteDataStore: profile.websiteDataStore
        )
        services.register(self)
    }

    /// Whether a tab can leave this window. The last one cannot: pulling it
    /// out would close this window to open an identical one, which is why
    /// Chrome moves the window instead.
    var canDetachTab: Bool { tabs.count > 1 }

    /// Takes a tab out of this window and hands it back **alive**. Unlike
    /// `closeTab` it is not torn down and not remembered as closed, because it
    /// is not closing — it keeps its session, and with it its web view, its
    /// scroll position and its back/forward list, ready to be shown in
    /// another window.
    ///
    /// The caller must give the returned tab to another workspace. A tab
    /// dropped on the floor here takes its web view with it.
    /// - Parameter evenIfLast: allowed when the tab is going to another
    ///   window rather than to a new one. The window it leaves is then empty
    ///   and the caller closes it, which is what dropping a lone tab into
    ///   another window means.
    func detachTab(_ id: UUID, evenIfLast: Bool = false) -> BrowserTab? {
        guard evenIfLast || canDetachTab,
              let index = tabs.firstIndex(where: { $0.id == id })
        else { return nil }
        let wasSelected = selectedTabID == id
        let tab = tabs.remove(at: index)
        tabSubscriptions.removeValue(forKey: id)
        // The group stays with the window that owns it.
        tab.groupID = nil
        if tabs.isEmpty {
            selectedTabID = nil
        } else if wasSelected {
            let nextIndex = min(index, tabs.count - 1)
            selectedTabID = tabs[nextIndex].id
            tabs[nextIndex].activate()
        }
        pruneEmptyGroups()
        if let groupID = selectedTab?.groupID { setCollapsed(false, forGroup: groupID) }
        schedulePersistence()
        return tab
    }

    /// Takes in a tab detached from another window, at `index` if the strip
    /// has a position in mind — a drop lands where the pointer was — or at the
    /// end otherwise. The pinned run still comes first, so a pinned tab
    /// arriving lands inside it and an unpinned one lands after it.
    func adopt(_ tab: BrowserTab, at index: Int? = nil) {
        guard !tabs.contains(where: { $0.id == tab.id }) else { return }
        tab.groupID = nil
        let pinnedCount = tabs.filter(\.isPinned).count
        var target = index ?? (tab.isPinned ? pinnedCount : tabs.count)
        target = tab.isPinned ? min(target, pinnedCount) : max(target, pinnedCount)
        tabs.insert(tab, at: min(max(target, 0), tabs.count))
        configure(tab)
        selectedTabID = tab.id
        tab.activate()
        schedulePersistence()
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = selectedTabID == id
        let removed = tabs.remove(at: index)
        rememberClosedTab(removed, atIndex: index)
        tabSubscriptions.removeValue(forKey: id)
        removed.teardown()

        if tabs.isEmpty {
            let replacement = makeTab(url: nil, isPrivate: false)
            tabs = [replacement]
            configure(replacement)
            selectedTabID = replacement.id
        } else if wasSelected {
            let nextIndex = min(index, tabs.count - 1)
            selectedTabID = tabs[nextIndex].id
            tabs[nextIndex].activate()
        }
        pruneEmptyGroups()
        // Closing the last visible tab of an expanded run can leave the
        // selection inside a collapsed group; open it rather than show a
        // strip with no active tab.
        if let groupID = selectedTab?.groupID { setCollapsed(false, forGroup: groupID) }
        schedulePersistence()
    }

    var canReopenClosedTab: Bool { !closedTabs.isEmpty }

    /// Brings back the most recently closed tab at the position it held, and
    /// back into its group when that group still exists.
    func reopenClosedTab() {
        guard !closedTabs.isEmpty else { return }
        let closed = closedTabs.removeFirst()
        makeRoomForPage()
        let tab = makeTab(url: WebURLPolicy.validatedURL(closed.url), isPrivate: false)
        if let groupID = closed.groupID, group(groupID) != nil {
            tab.groupID = groupID
        }
        let index = min(max(closed.index, 0), tabs.count)
        tabs.insert(tab, at: index)
        // A reopened tab is never pinned, but the position it held can now
        // fall inside a pinned run that grew after it closed.
        enforcePinnedTabsPrecedeUnpinnedTabs()
        configure(tab)
        if let groupID = tab.groupID { regatherGroupRun(groupID) }
        selectTab(tab.id)
        schedulePersistence()
    }

    private func rememberClosedTab(_ tab: BrowserTab, atIndex index: Int) {
        // A private tab leaves no trace anywhere else; it must not leave one here.
        guard !tab.isPrivate else { return }
        let url = tab.session.currentURLString
        guard WebURLPolicy.validatedURL(url) != nil else { return }
        closedTabs.insert(
            ClosedTab(url: url, title: tab.session.pageTitle, index: index, groupID: tab.groupID),
            at: 0
        )
        if closedTabs.count > Self.closedTabLimit {
            closedTabs.removeLast(closedTabs.count - Self.closedTabLimit)
        }
    }

    /// ⌘1-⌘8 select that tab; ⌘9 selects the last one however many are open,
    /// which is what Safari does and what a switching user's fingers expect.
    func selectTab(atOrdinal ordinal: Int) {
        guard !tabs.isEmpty else { return }
        let index = ordinal >= 9 ? tabs.count - 1 : ordinal - 1
        guard tabs.indices.contains(index) else { return }
        selectTab(tabs[index].id)
    }

    /// Opens the same address in a new tab beside this one. WebKit exposes no
    /// public way to copy a tab's back/forward list, so the copy starts fresh.
    /// The copy matches the original's pinned state, so duplicating a pinned
    /// tab stays in the pinned run right beside it instead of jumping past it.
    func duplicateTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let original = tabs[index]
        let url = WebURLPolicy.validatedURL(original.session.currentURLString)
        let copy = makeTab(url: url, isPrivate: original.isPrivate)
        copy.groupID = original.groupID
        copy.isPinned = original.isPinned
        tabs.insert(copy, at: index + 1)
        enforcePinnedTabsPrecedeUnpinnedTabs()
        configure(copy)
        selectTab(copy.id)
        schedulePersistence()
    }

    /// The inspector switch is a live property, so a change in Settings should
    /// reach the tabs already open rather than only the next one.
    func applyDeveloperFeatureSetting() {
        let enabled = webFeatures.showsDeveloperFeatures
        for tab in tabs { tab.session.webView.isInspectable = enabled }
    }

    func duplicateSelectedTab() {
        guard let selectedTabID else { return }
        duplicateTab(selectedTabID)
    }

    func closeSelectedTab() {
        guard let selectedTabID else { return }
        closeTab(selectedTabID)
    }

    /// Closes everything except `id`, which is left selected — and every
    /// pinned tab, which stays open no matter which tab was kept, since
    /// staying open through exactly this kind of cleanup is the point of
    /// pinning it. The always-one-tab invariant in `closeTab` still holds
    /// because `id` is never closed.
    func closeOtherTabs(keeping id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        let closableIDs = tabs.filter { $0.id != id && !$0.isPinned }.map(\.id)
        for other in closableIDs {
            closeTab(other)
        }
        selectTab(id)
    }

    func selectNextTab(direction: Int = 1) {
        guard tabs.count > 1,
              let selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        let next = (index + direction + tabs.count) % tabs.count
        selectTab(tabs[next].id)
    }

    // MARK: - Tab groups

    /// The tabs the strip draws: everything except the members of a collapsed
    /// group, which stay open and loaded but are folded behind their chip.
    var visibleTabs: [BrowserTab] {
        tabs.filter { tab in
            guard let groupID = tab.groupID else { return true }
            return group(groupID)?.isCollapsed != true
        }
    }

    func group(_ id: UUID?) -> TabGroupRecord? {
        guard let id else { return nil }
        return tabGroups.first { $0.id == id }
    }

    func tabs(inGroup id: UUID) -> [BrowserTab] {
        tabs.filter { $0.groupID == id }
    }

    var selectedTabGroup: TabGroupRecord? {
        group(selectedTab?.groupID)
    }

    /// Creates a group around existing tabs and pulls them together so the
    /// group occupies one unbroken run of the strip. Pinned tabs are never
    /// eligible: pinning and grouping are two different ways of organizing
    /// the strip, and a pinned tab already left any group it was in.
    @discardableResult
    func createGroup(withTabs tabIDs: [UUID], title: String = "", colorID: String? = nil) -> TabGroupRecord? {
        let members = tabIDs.compactMap { id in tabs.first { $0.id == id && !$0.isPinned } }
        guard !members.isEmpty else { return nil }
        let record = TabGroupRecord(
            title: title,
            colorID: colorID ?? nextGroupColorID()
        )
        let previousGroupIDs = Set(members.compactMap(\.groupID))
        tabGroups.append(record)
        for member in members { member.groupID = record.id }
        if let anchor = members.first {
            var cursor = tabs.firstIndex { $0.id == anchor.id } ?? 0
            for member in members.dropFirst() {
                placeTab(member, afterIndex: cursor)
                cursor = tabs.firstIndex { $0.id == member.id } ?? cursor
            }
        }
        // Taking tabs out of the middle of another group would otherwise leave
        // that group in two pieces.
        for groupID in previousGroupIDs { regatherGroupRun(groupID) }
        pruneEmptyGroups()
        pendingGroupEditorID = record.id
        schedulePersistence()
        return record
    }

    /// Moves a tab into an existing group, parking it at the end of that
    /// group's run. Adding to a collapsed group opens the group: a tab the
    /// user just filed should not disappear. A pinned tab is never eligible.
    func addTab(_ tabID: UUID, toGroup groupID: UUID) {
        guard let tab = tabs.first(where: { $0.id == tabID }),
              !tab.isPinned,
              group(groupID) != nil,
              tab.groupID != groupID else { return }
        let lastMemberIndex = tabs.lastIndex { $0.groupID == groupID }
        let previousGroupID = tab.groupID
        tab.groupID = groupID
        if let lastMemberIndex { placeTab(tab, afterIndex: lastMemberIndex) }
        if let previousGroupID { regatherGroupRun(previousGroupID) }
        setCollapsed(false, forGroup: groupID)
        pruneEmptyGroups()
        schedulePersistence()
    }

    /// Opens a new tab already inside `groupID`, at the end of its run.
    func addTab(toGroup groupID: UUID) {
        guard group(groupID) != nil else { return }
        let lastMemberIndex = tabs.lastIndex { $0.groupID == groupID }
        let tab = makeTab(url: nil, isPrivate: lastMemberIndex.map { tabs[$0].isPrivate } ?? false)
        tab.groupID = groupID
        tabs.insert(tab, at: lastMemberIndex.map { $0 + 1 } ?? tabs.count)
        configure(tab)
        setCollapsed(false, forGroup: groupID)
        selectTab(tab.id)
        schedulePersistence()
    }

    /// Takes a tab out of its group and parks it just after the group's run,
    /// so it visibly steps outside the enclosure instead of jumping away.
    func removeTabFromGroup(_ tabID: UUID) {
        guard let tab = tabs.first(where: { $0.id == tabID }), let groupID = tab.groupID else { return }
        let lastMemberIndex = tabs.lastIndex { $0.groupID == groupID }
        tab.groupID = nil
        if let lastMemberIndex { placeTab(tab, afterIndex: lastMemberIndex) }
        pruneEmptyGroups()
        schedulePersistence()
    }

    func renameGroup(_ groupID: UUID, title: String) {
        guard let index = tabGroups.firstIndex(where: { $0.id == groupID }) else { return }
        let normalized = TabGroupRecord.normalizedTitle(title)
        guard tabGroups[index].title != normalized else { return }
        tabGroups[index].title = normalized
        schedulePersistence()
    }

    func recolorGroup(_ groupID: UUID, colorID: String) {
        guard let index = tabGroups.firstIndex(where: { $0.id == groupID }) else { return }
        let normalized = TabGroupRecord.normalizedColorID(colorID)
        guard tabGroups[index].colorID != normalized else { return }
        tabGroups[index].colorID = normalized
        schedulePersistence()
    }

    func toggleCollapse(groupID: UUID) {
        guard let group = group(groupID) else { return }
        setCollapsed(!group.isCollapsed, forGroup: groupID)
    }

    /// Keeps the tabs, drops the group.
    func ungroup(groupID: UUID) {
        guard tabGroups.contains(where: { $0.id == groupID }) else { return }
        for tab in tabs where tab.groupID == groupID { tab.groupID = nil }
        tabGroups.removeAll { $0.id == groupID }
        pruneEmptyGroups()
        schedulePersistence()
    }

    /// Closes the group's tabs. If they were the last open tabs, `closeTab`
    /// leaves the usual single empty tab behind.
    func closeGroup(groupID: UUID) {
        let memberIDs = tabs.filter { $0.groupID == groupID }.map(\.id)
        tabGroups.removeAll { $0.id == groupID }
        for id in memberIDs { closeTab(id) }
        pruneEmptyGroups()
        schedulePersistence()
    }

    /// The Tabs menu's "New Tab Group" (⌃⌘P).
    @discardableResult
    func createGroupForSelectedTab() -> TabGroupRecord? {
        guard let selectedTabID else { return nil }
        return createGroup(withTabs: [selectedTabID])
    }

    func removeSelectedTabFromGroup() {
        guard let selectedTabID else { return }
        removeTabFromGroup(selectedTabID)
    }

    /// Grey is the palette's fallback color, so it is handed out last: a group
    /// the user did not color should still look deliberate.
    private static let automaticColorIDs =
        TabGroupRecord.colorIDs.filter { $0 != TabGroupRecord.defaultColorID } + [TabGroupRecord.defaultColorID]

    private func nextGroupColorID() -> String {
        let used = Set(tabGroups.map(\.colorID))
        return Self.automaticColorIDs.first { !used.contains($0) }
            ?? Self.automaticColorIDs[tabGroups.count % Self.automaticColorIDs.count]
    }

    private func setCollapsed(_ collapsed: Bool, forGroup groupID: UUID) {
        guard let index = tabGroups.firstIndex(where: { $0.id == groupID }),
              tabGroups[index].isCollapsed != collapsed else { return }
        if collapsed, selectedTab?.groupID == groupID {
            // Folding the group away must not hide the active tab. Hand focus
            // to the nearest tab outside it, and when there is none, leave the
            // group open rather than leave the strip without an active tab.
            guard let replacement = nearestTab(outsideGroup: groupID) else { return }
            selectedTabID = replacement.id
            replacement.activate()
        }
        tabGroups[index].isCollapsed = collapsed
        schedulePersistence()
    }

    private func nearestTab(outsideGroup groupID: UUID) -> BrowserTab? {
        guard let lastMemberIndex = tabs.lastIndex(where: { $0.groupID == groupID }) else { return nil }
        if let after = tabs[(lastMemberIndex + 1)...].first(where: { $0.groupID != groupID }) { return after }
        return tabs[..<lastMemberIndex].last { $0.groupID != groupID }
    }

    private func pruneEmptyGroups() {
        let liveGroupIDs = Set(tabs.compactMap(\.groupID))
        if tabGroups.contains(where: { !liveGroupIDs.contains($0.id) }) {
            tabGroups.removeAll { !liveGroupIDs.contains($0.id) }
        }
        // A group that no longer exists must not leave its editor waiting.
        if let pendingGroupEditorID, !tabGroups.contains(where: { $0.id == pendingGroupEditorID }) {
            self.pendingGroupEditorID = nil
        }
    }

    /// Pulls a group whose tabs ended up separated back into one run, anchored
    /// where the group already starts.
    private func regatherGroupRun(_ groupID: UUID) {
        let memberIndices = tabs.indices.filter { tabs[$0].groupID == groupID }
        guard let first = memberIndices.first,
              let last = memberIndices.last,
              last - first != memberIndices.count - 1 else { return }
        let members = memberIndices.map { tabs[$0] }
        var cursor = first
        for member in members.dropFirst() {
            placeTab(member, afterIndex: cursor)
            cursor = tabs.firstIndex { $0.id == member.id } ?? cursor
        }
    }

    /// Moves `tab` so it sits immediately after the tab currently at `index`.
    private func placeTab(_ tab: BrowserTab, afterIndex index: Int) {
        guard let current = tabs.firstIndex(where: { $0.id == tab.id }), current != index else { return }
        var reordered = tabs
        reordered.remove(at: current)
        // Removing a tab that sat before the anchor shifts the anchor down one.
        let target = current < index ? index : index + 1
        reordered.insert(tab, at: min(max(target, 0), reordered.count))
        tabs = reordered
    }

    // MARK: - Pinned tabs

    /// Pins a tab. Pinning and grouping are two different ways of organizing
    /// the strip, so a pinned tab leaves its group — the old group is pulled
    /// back into one run rather than left split — and cannot be added to a
    /// group while pinned (`createGroup`/`addTab(_:toGroup:)` already refuse
    /// it; the chip's context menu hides those items too).
    func pinTab(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }), !tab.isPinned else { return }
        let previousGroupID = tab.groupID
        tab.groupID = nil
        tab.isPinned = true
        enforcePinnedTabsPrecedeUnpinnedTabs()
        if let previousGroupID { regatherGroupRun(previousGroupID) }
        pruneEmptyGroups()
        schedulePersistence()
    }

    /// Unpins a tab, returning it to the start of the unpinned run — the
    /// other side of the same boundary `pinTab` moves a tab to.
    func unpinTab(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }), tab.isPinned else { return }
        tab.isPinned = false
        enforcePinnedTabsPrecedeUnpinnedTabs()
        schedulePersistence()
    }

    /// "Pin tab" / "Unpin tab" in the chip's context menu.
    func togglePin(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        tab.isPinned ? unpinTab(id) : pinTab(id)
    }

    /// The single place that keeps the strip's ordering invariant: every
    /// pinned tab sits ahead of every unpinned one. A stable partition, so a
    /// tab already on the correct side of the boundary keeps its position —
    /// only a genuine violation (pinning, unpinning, or a tab inserted or
    /// reopened on the wrong side of a pinned run) reshuffles anything.
    private func enforcePinnedTabsPrecedeUnpinnedTabs() {
        guard let firstUnpinnedIndex = tabs.firstIndex(where: { !$0.isPinned }),
              let lastPinnedIndex = tabs.lastIndex(where: { $0.isPinned }),
              lastPinnedIndex > firstUnpinnedIndex else { return }
        tabs = tabs.filter(\.isPinned) + tabs.filter { !$0.isPinned }
    }

    // MARK: - Reordering

    /// Reorders one tab by drag. Every invariant the strip promises lives
    /// here — the drag gesture itself is a thin caller — so it is testable
    /// without a window.
    ///
    /// - Parameter toIndex: where to drop the tab, as a position in the strip
    ///   *before* the move ("put it where the tab currently at this index
    ///   is"). Clamped into range, then onto the correct side of the pinned
    ///   boundary. Any group the raw move would otherwise split — either the
    ///   dragged tab's own, pulled away from its siblings, or a different
    ///   group it landed in the middle of — is pulled back together with the
    ///   same `regatherGroupRun` a group edit already uses.
    /// - Returns: whether the tab actually moved.
    @discardableResult
    func moveTab(_ id: UUID, toIndex: Int) -> Bool {
        guard let sourceIndex = tabs.firstIndex(where: { $0.id == id }), tabs.count > 1 else { return false }
        let tab = tabs[sourceIndex]
        var target = min(max(toIndex, 0), tabs.count - 1)

        // Invariant: a pinned tab can only land among pinned tabs, and an
        // unpinned tab only among unpinned ones — the two runs never cross.
        let pinnedCount = tabs.filter(\.isPinned).count
        target = tab.isPinned ? min(target, max(pinnedCount - 1, 0)) : max(target, pinnedCount)
        guard target != sourceIndex else { return false }

        let landingGroupID = tabs[target].groupID
        let afterIndex = sourceIndex < target ? target : target - 1
        placeTab(tab, afterIndex: afterIndex)

        if let ownGroupID = tab.groupID { regatherGroupRun(ownGroupID) }
        if let landingGroupID, landingGroupID != tab.groupID { regatherGroupRun(landingGroupID) }

        schedulePersistence()
        return true
    }

    /// Builds the tab a `window.open()` popup will live in and hands its web
    /// view back to WebKit. The tab must adopt that exact instance: it is what
    /// keeps `window.opener` connected, so a popup sign-in can report its
    /// result to the page that opened it instead of finishing in a dead end.
    private func adoptPopupTab(configuration: WKWebViewConfiguration, isPrivate: Bool) -> WKWebView {
        let tab = BrowserTab(
            downloadCenter: downloads,
            searchSettings: searchSettings,
            isPrivate: isPrivate,
            contentBlocking: contentBlocking,
            favicons: favicons,
            adoptingPopupConfiguration: configuration
        )
        tabs.append(tab)
        configure(tab)
        selectTab(tab.id)
        return tab.session.webView
    }

    private func makeTab(url: URL?, isPrivate: Bool) -> BrowserTab {
        BrowserTab(
            initialURL: url,
            downloadCenter: downloads,
            searchSettings: searchSettings,
            isPrivate: isPrivate,
            contentBlocking: contentBlocking,
            favicons: favicons,
            webFeatures: webFeatures,
            websiteDataStore: websiteDataStore
        )
    }

    func open(_ urlString: String, inNewTab: Bool = false) {
        guard let url = WebURLPolicy.validatedURL(urlString) else { return }
        makeRoomForPage()
        if inNewTab || selectedTab == nil {
            addTab(url: url, isPrivate: selectedTab?.isPrivate ?? false)
        } else {
            selectedTab?.session.load(url)
        }
    }

    /// Opens a file the person chose, in a tab of its own so the page they
    /// were on is not replaced by it.
    func openLocalFile(_ url: URL) {
        guard url.isFileURL else { return }
        makeRoomForPage()
        let tab = makeTab(url: nil, isPrivate: false)
        tabs.append(tab)
        configure(tab)
        enforcePinnedTabsPrecedeUnpinnedTabs()
        selectedTabID = tab.id
        tab.activate()
        tab.session.loadLocalFile(url)
        schedulePersistence()
    }

    func openExternalURL(_ url: URL) {
        guard let safeURL = WebURLPolicy.validatedURL(url) else { return }
        addTab(url: safeURL, isPrivate: false)
    }

    func toggleBookmarkForSelectedTab() {
        guard let tab = selectedTab else { return }
        dataStore.toggleBookmark(title: tab.session.pageTitle, url: tab.session.currentURLString)
    }

    func addSelectedPageBookmark(to folderID: UUID?) {
        guard let tab = selectedTab else { return }
        dataStore.addBookmark(
            title: tab.session.pageTitle,
            url: tab.session.currentURLString,
            folderID: folderID
        )
    }

    @discardableResult
    func fileBookmarkFromDrop(_ url: URL, to folderID: UUID?) -> BookmarkDropResult? {
        guard let safeURL = BookmarkURLPolicy.validatedURL(url.absoluteString) else { return nil }
        let normalizedURL = safeURL.absoluteString
        let existing = dataStore.bookmark(for: normalizedURL)
        let sourceTitle: String
        if selectedTab?.session.currentURLString == normalizedURL {
            sourceTitle = selectedTab?.session.pageTitle ?? ""
        } else {
            sourceTitle = existing?.title ?? safeURL.host ?? normalizedURL
        }
        return dataStore.fileBookmarkFromDrop(safeURL, title: sourceTitle, to: folderID)
    }

    /// Opens the full-page bookmarks home on the selected tab, creating a tab
    /// first if the workspace momentarily has none (during a data reset).
    func openBookmarksHome() {
        makeRoomForPage()
        guard let tab = selectedTab else {
            addTab()
            selectedTab?.showBookmarksHome()
            return
        }
        tab.showBookmarksHome()
    }

    /// Opens the full-page history surface on the selected tab, creating a tab
    /// first if the workspace momentarily has none.
    ///
    /// No request counter beside it, unlike `requestBookmarkLibrary`: nothing
    /// listens for one, and a second unused counter is a second thing to keep
    /// alive.
    func openHistoryHome() {
        makeRoomForPage()
        guard let tab = selectedTab else {
            addTab()
            selectedTab?.showHistoryHome()
            return
        }
        tab.showHistoryHome()
    }

    /// D7: ⌘⌥B and the bookmarks-bar entry points open the full-page home. The
    /// counter is kept — the smoke suite pins it — so any surface that still
    /// listens for a library request keeps working.
    func requestBookmarkLibrary() {
        bookmarkLibraryRequest += 1
        openBookmarksHome()
    }

    func requestNewBookmarkFolder(parentID: UUID? = nil) {
        requestedBookmarkFolderParentID = parentID
        bookmarkFolderRequestID = UUID()
    }

    func requestBookmarkImport() {
        bookmarkImportRequestID = UUID()
    }

    func requestAddressFocus() {
        focusAddressRequest += 1
    }

    // MARK: - Page menu commands

    /// ⌘F, ⌘G, ⇧⌘G. Each acts on the tab in front, never on all of them.
    func findInSelectedTab() {
        selectedTab?.find.present()
    }

    func findNextInSelectedTab() {
        selectedTab?.find.step(backwards: false)
    }

    func findPreviousInSelectedTab() {
        selectedTab?.find.step(backwards: true)
    }

    /// ⌘+, ⌘−, ⌘0.
    func zoomInSelectedTab() {
        selectedTab?.session.zoomIn()
    }

    func zoomOutSelectedTab() {
        selectedTab?.session.zoomOut()
    }

    func resetZoomInSelectedTab() {
        selectedTab?.session.resetPageZoom()
    }

    /// ⌘P.
    func printSelectedPage() {
        selectedTab?.session.printPage()
    }

    /// Saves the page in front as a web archive, after the person names it in
    /// a save panel. `status` reports what happened so the caller can say so;
    /// nothing is written if they cancel.
    func saveSelectedPage(status: @escaping (String) -> Void = { _ in }) {
        guard let tab = selectedTab, tab.session.canPrintPage else { return }
        let session = tab.session
        PageFileCommands.savePage(
            named: tab.displayTitle,
            archivedBy: { finished in session.makeWebArchive(completion: finished) },
            completion: { result in
                switch result {
                case .success(let url): status("Saved to \(url.lastPathComponent).")
                case .failure(let error): status("Could not save this page: \(error.localizedDescription)")
                }
            }
        )
    }

    /// Writes the page in front out as a PDF, after the person names it.
    func exportSelectedPageAsPDF(status: @escaping (String) -> Void = { _ in }) {
        guard let tab = selectedTab, tab.session.canPrintPage else { return }
        let session = tab.session
        PageFileCommands.exportPDF(
            named: tab.displayTitle,
            renderedBy: { finished in session.makePDF(completion: finished) },
            completion: { result in
                switch result {
                case .success(let url): status("Exported to \(url.lastPathComponent).")
                case .failure(let error): status("Could not export this page: \(error.localizedDescription)")
                }
            }
        )
    }

    /// A new tab of its own, in a group of its own — Safari's New Empty Tab
    /// Group. Ours starts with one empty tab rather than none, because a group
    /// with no tabs is pruned by design: a group exists while a tab belongs to
    /// it.
    @discardableResult
    func createEmptyGroup() -> TabGroupRecord? {
        addTab()
        guard let newTabID = selectedTabID else { return nil }
        return createGroup(withTabs: [newTabID])
    }

    /// Hands the current page's address to the system share picker. Only a
    /// real web address is offered — there is nothing to share about a start
    /// surface, and a local file's path is not ours to send anywhere.
    func shareSelectedPage() {
        guard let shareable = selectedTab.flatMap({ WebURLPolicy.validatedURL($0.session.currentURLString) })
        else { return }
        PageFileCommands.share(shareable, from: NSApp.keyWindow?.contentView)
    }

    /// Whether there is a page worth saving or sharing.
    var canSaveSelectedPage: Bool { selectedTab?.session.canPrintPage ?? false }

    var canShareSelectedPage: Bool {
        selectedTab.flatMap { WebURLPolicy.validatedURL($0.session.currentURLString) } != nil
    }

    /// ⌘R, ⌘., ⌘[, ⌘]. Each acts on the tab in front, like the toolbar
    /// buttons beside the address bar.
    func reloadSelectedTab() {
        selectedTab?.session.reload()
    }

    func stopLoadingSelectedTab() {
        selectedTab?.session.stopLoading()
    }

    func goBackInSelectedTab() {
        makeRoomForPage()
        selectedTab?.session.goBack()
    }

    func goForwardInSelectedTab() {
        makeRoomForPage()
        selectedTab?.session.goForward()
    }

    func requestAddressFocusForAppActivation() {
        guard selectedTab?.session.shouldFocusAddressOnAppActivation == true else { return }
        requestAddressFocus()
    }

    func selectSearchEngine(_ engine: SearchEngine) {
        searchSettings.selectedEngine = engine
        requestAddressFocus()
    }

    func persistNow() {
        guard persistsSession, !closedForWindow else { return }
        let persistentTabs = tabs.filter { !$0.isPrivate }
        let persistentSelection = persistentTabs.contains(where: { $0.id == selectedTabID })
            ? selectedTabID
            : persistentTabs.first?.id
        // A group whose only members are private tabs is never written out,
        // for the same reason those tabs are not.
        let persistentGroupIDs = Set(persistentTabs.compactMap(\.groupID))
        let snapshot = BrowserWorkspaceSnapshot(
            tabs: persistentTabs.map(\.persistenceRecord),
            selectedTabID: persistentSelection,
            groups: tabGroups.filter { persistentGroupIDs.contains($0.id) }
        )
        dataStore.saveWorkspace(snapshot)
    }

    func resetLocalBrowsingData() async {
        persistenceTask?.cancel()
        persistenceTask = nil
        tabs.forEach { $0.teardown() }
        tabSubscriptions.removeAll()
        tabs = []
        tabGroups = []
        selectedTabID = nil
        dataStore.clearAllBrowserRecords()
        downloads.clearAllRecords()
        // Captured site icons are browsing evidence too: the same reset that
        // erases bookmarks and history erases them from disk and memory.
        favicons.clearAll()

        let dataStore = WKWebsiteDataStore.default()
        await withCheckedContinuation { continuation in
            dataStore.removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: .distantPast
            ) {
                continuation.resume()
            }
        }

        await contentBlocking.clearSiteExceptions()

        let replacement = makeTab(url: nil, isPrivate: false)
        tabs = [replacement]
        selectedTabID = replacement.id
        configure(replacement)
        requestAddressFocus()
    }

    private func configure(_ tab: BrowserTab) {
        let isPrivate = tab.isPrivate
        // A popup that has no address yet opens an empty tab; the script that
        // opened it sets the location a moment later.
        tab.session.onRequestNewTab = { [weak self] url in
            self?.addTab(url: url, isPrivate: isPrivate)
        }
        // A popup inherits the opener's private/normal session along with the
        // configuration WebKit handed over.
        tab.session.onRequestPopupWebView = { [weak self] configuration in
            self?.adoptPopupTab(configuration: configuration, isPrivate: isPrivate)
        }
        tab.session.onCompletedVisit = { [weak self] title, url in
            guard let self else { return }
            guard !isPrivate else { return }
            self.dataStore.recordVisit(title: title, url: url)
            self.schedulePersistence()
        }
        tabSubscriptions[tab.id] = tab.objectWillChange.sink { [weak self] _ in
            self?.schedulePersistence()
        }
    }

    private func schedulePersistence() {
        guard !closedForWindow else { return }
        persistenceTask?.cancel()
        persistenceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
