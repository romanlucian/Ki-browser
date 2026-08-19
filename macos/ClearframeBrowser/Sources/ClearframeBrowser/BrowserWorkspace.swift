import ClearframeCore
import Combine
import Foundation
import WebKit

/// Which full-page surface a tab shows while `BrowserSession.loadState` is
/// `.startPage` (D6). Deliberately not persisted: a restored or brand-new tab
/// always opens on the AI guide, which is the product's start-page promise.
enum StartSurface {
    case aiHome
    case bookmarksHome
}

@MainActor
final class BrowserTab: ObservableObject, Identifiable {
    let id: UUID
    let session: BrowserSession
    let assistant: PageAssistantModel
    /// Find in page belongs to the tab, like its page does: two tabs searching
    /// for different words do not share a bar or a result.
    let find: PageFindController
    let isPrivate: Bool
    @Published private(set) var displayTitle: String
    @Published private(set) var lastActivatedAt: Date
    @Published var startSurface: StartSurface = .aiHome
    /// The tab group this tab belongs to. `BrowserWorkspace` owns every write
    /// so grouped tabs stay contiguous in the strip.
    @Published fileprivate(set) var groupID: UUID?

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
        contentBlocking: ContentRuleListProvider? = nil,
        favicons: FaviconStore? = nil,
        adoptingPopupConfiguration popupConfiguration: WKWebViewConfiguration? = nil
    ) {
        self.id = id
        self.displayTitle = title
        self.lastActivatedAt = lastActivatedAt
        self.isPrivate = isPrivate
        self.groupID = groupID
        assistant = PageAssistantModel()
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
                adoptingPopupConfiguration: popupConfiguration
            )
        } else if loadImmediately {
            resolvedSession = BrowserSession(
                downloadCenter: downloadCenter,
                searchSettings: searchSettings,
                initialURL: initialURL,
                isPrivate: isPrivate,
                contentBlocking: contentBlocking,
                favicons: favicons
            )
        } else {
            resolvedSession = BrowserSession(
                downloadCenter: downloadCenter,
                searchSettings: searchSettings,
                isPrivate: isPrivate,
                contentBlocking: contentBlocking,
                favicons: favicons
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
    }

    var persistenceRecord: BrowserTabRecord {
        let liveURL = session.currentURLString.nilIfEmpty
        return BrowserTabRecord(
            id: id,
            url: liveURL ?? pendingRestoreURL?.absoluteString,
            title: displayTitle,
            lastActivatedAt: lastActivatedAt,
            groupID: groupID
        )
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
    func goHome() {
        startSurface = .aiHome
        session.showStartPage()
    }

    /// Shows the full-page bookmarks home on this tab's start surface.
    func showBookmarksHome() {
        startSurface = .bookmarksHome
        session.showStartPage()
    }

    func teardown() {
        cancellables.removeAll()
        assistant.teardown()
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

    let downloads: DownloadCenter
    let dataStore: BrowserDataStore
    let searchSettings: SearchSettingsStore
    let contentBlocking: ContentRuleListProvider
    /// Site icons captured during real visits, shared by every tab so a site
    /// is fetched at most once per run (see `FaviconStore` for the policy).
    let favicons: FaviconStore

    private var tabSubscriptions: [UUID: AnyCancellable] = [:]
    private var downloadSubscription: AnyCancellable?
    private var dataStoreSubscription: AnyCancellable?
    private var contentBlockingSubscription: AnyCancellable?
    private var persistenceTask: Task<Void, Never>?

    init(
        dataStore: BrowserDataStore? = nil,
        downloads: DownloadCenter? = nil,
        searchSettings: SearchSettingsStore? = nil,
        contentBlocking: ContentRuleListProvider? = nil,
        favicons: FaviconStore? = nil
    ) {
        let resolvedDataStore = dataStore ?? BrowserDataStore()
        let resolvedDownloads = downloads ?? DownloadCenter()
        let resolvedSearchSettings = searchSettings ?? SearchSettingsStore()
        // Created before any tab so every web view can register with it while
        // the first rule-list compile is still running.
        let resolvedContentBlocking = contentBlocking
            ?? ContentRuleListProvider(settings: ContentBlockingSettingsStore())
        let resolvedFavicons = favicons ?? FaviconStore()
        self.dataStore = resolvedDataStore
        self.downloads = resolvedDownloads
        self.searchSettings = resolvedSearchSettings
        self.contentBlocking = resolvedContentBlocking
        self.favicons = resolvedFavicons
        downloadSubscription = resolvedDownloads.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        dataStoreSubscription = resolvedDataStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        contentBlockingSubscription = resolvedContentBlocking.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        if let restored = resolvedDataStore.loadWorkspace(), !restored.tabs.isEmpty {
            let selectedID = restored.selectedTabID ?? restored.tabs.first?.id
            tabGroups = restored.groups
            tabs = restored.tabs.map { record in
                BrowserTab(
                    id: record.id,
                    title: record.title,
                    initialURL: record.restorableURL,
                    loadImmediately: record.id == selectedID,
                    lastActivatedAt: record.lastActivatedAt,
                    downloadCenter: resolvedDownloads,
                    searchSettings: resolvedSearchSettings,
                    groupID: record.groupID,
                    contentBlocking: resolvedContentBlocking,
                    favicons: resolvedFavicons
                )
            }
            selectedTabID = tabs.contains(where: { $0.id == selectedID }) ? selectedID : tabs.first?.id
            // The restored selection has to be a tab the strip actually shows.
            if let group = selectedTab?.groupID {
                setCollapsed(false, forGroup: group)
            }
        } else {
            let tab = BrowserTab(
                downloadCenter: resolvedDownloads,
                searchSettings: resolvedSearchSettings,
                contentBlocking: resolvedContentBlocking,
                favicons: resolvedFavicons
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

    func addTab(url: URL? = nil, select: Bool = true, isPrivate: Bool = false) {
        let tab = makeTab(url: url, isPrivate: isPrivate)
        tabs.append(tab)
        configure(tab)
        if select { selectTab(tab.id) }
        schedulePersistence()
    }

    /// "New tab to the right". The new tab inherits the anchor's group, so
    /// opening a tab next to a grouped one lands inside that group instead of
    /// splitting its run in two.
    func addTab(after anchorID: UUID) {
        guard let anchorIndex = tabs.firstIndex(where: { $0.id == anchorID }) else {
            addTab()
            return
        }
        let anchor = tabs[anchorIndex]
        let tab = makeTab(url: nil, isPrivate: anchor.isPrivate)
        tab.groupID = anchor.groupID
        tabs.insert(tab, at: anchorIndex + 1)
        configure(tab)
        selectTab(tab.id)
        schedulePersistence()
    }

    func selectTab(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        // A tab the strip is hiding cannot be the active one: choosing one
        // from ⌘1-9, a popup, or a menu opens its group back up.
        if let groupID = tab.groupID { setCollapsed(false, forGroup: groupID) }
        selectedTabID = id
        selectedTab?.activate()
        schedulePersistence()
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = selectedTabID == id
        let removed = tabs.remove(at: index)
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

    func closeSelectedTab() {
        guard let selectedTabID else { return }
        closeTab(selectedTabID)
    }

    /// Closes everything except `id`, which is left selected. The always-one-tab
    /// invariant in `closeTab` still holds because `id` is never closed.
    func closeOtherTabs(keeping id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        for other in tabs.map(\.id) where other != id {
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
    /// group occupies one unbroken run of the strip.
    @discardableResult
    func createGroup(withTabs tabIDs: [UUID], title: String = "", colorID: String? = nil) -> TabGroupRecord? {
        let members = tabIDs.compactMap { id in tabs.first { $0.id == id } }
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
    /// user just filed should not disappear.
    func addTab(_ tabID: UUID, toGroup groupID: UUID) {
        guard let tab = tabs.first(where: { $0.id == tabID }),
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
            favicons: favicons
        )
    }

    func open(_ urlString: String, inNewTab: Bool = false) {
        guard let url = WebURLPolicy.validatedURL(urlString) else { return }
        if inNewTab || selectedTab == nil {
            addTab(url: url, isPrivate: selectedTab?.isPrivate ?? false)
        } else {
            selectedTab?.session.load(url)
        }
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
        guard let tab = selectedTab else {
            addTab()
            selectedTab?.showBookmarksHome()
            return
        }
        tab.showBookmarksHome()
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

    /// ⌘R, ⌘., ⌘[, ⌘]. Each acts on the tab in front, like the toolbar
    /// buttons beside the address bar.
    func reloadSelectedTab() {
        selectedTab?.session.reload()
    }

    func stopLoadingSelectedTab() {
        selectedTab?.session.stopLoading()
    }

    func goBackInSelectedTab() {
        selectedTab?.session.goBack()
    }

    func goForwardInSelectedTab() {
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
