import ClearframeCore
import Combine
import Foundation
import WebKit

@MainActor
final class BrowserTab: ObservableObject, Identifiable {
    let id: UUID
    let session: BrowserSession
    let assistant: PageAssistantModel
    let isPrivate: Bool
    @Published private(set) var displayTitle: String
    @Published private(set) var lastActivatedAt: Date

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
        contentBlocking: ContentRuleListProvider? = nil
    ) {
        self.id = id
        self.displayTitle = title
        self.lastActivatedAt = lastActivatedAt
        self.isPrivate = isPrivate
        assistant = PageAssistantModel()
        if loadImmediately {
            session = BrowserSession(
                downloadCenter: downloadCenter,
                searchSettings: searchSettings,
                initialURL: initialURL,
                isPrivate: isPrivate,
                contentBlocking: contentBlocking
            )
        } else {
            session = BrowserSession(
                downloadCenter: downloadCenter,
                searchSettings: searchSettings,
                isPrivate: isPrivate,
                contentBlocking: contentBlocking
            )
            pendingRestoreURL = initialURL
        }

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
            lastActivatedAt: lastActivatedAt
        )
    }

    func activate() {
        lastActivatedAt = Date()
        if let pendingRestoreURL {
            self.pendingRestoreURL = nil
            session.load(pendingRestoreURL)
        }
    }

    func teardown() {
        cancellables.removeAll()
        assistant.teardown()
        session.teardown()
    }
}

@MainActor
final class BrowserWorkspace: ObservableObject {
    @Published private(set) var tabs: [BrowserTab] = []
    @Published var selectedTabID: UUID?
    @Published var focusAddressRequest = 0
    @Published private(set) var bookmarkLibraryRequest = 0
    @Published private(set) var bookmarkFolderRequestID = UUID()
    private(set) var requestedBookmarkFolderParentID: UUID?

    let downloads: DownloadCenter
    let dataStore: BrowserDataStore
    let searchSettings: SearchSettingsStore
    let contentBlocking: ContentRuleListProvider

    private var tabSubscriptions: [UUID: AnyCancellable] = [:]
    private var downloadSubscription: AnyCancellable?
    private var dataStoreSubscription: AnyCancellable?
    private var contentBlockingSubscription: AnyCancellable?
    private var persistenceTask: Task<Void, Never>?

    init(
        dataStore: BrowserDataStore? = nil,
        downloads: DownloadCenter? = nil,
        searchSettings: SearchSettingsStore? = nil,
        contentBlocking: ContentRuleListProvider? = nil
    ) {
        let resolvedDataStore = dataStore ?? BrowserDataStore()
        let resolvedDownloads = downloads ?? DownloadCenter()
        let resolvedSearchSettings = searchSettings ?? SearchSettingsStore()
        // Created before any tab so every web view can register with it while
        // the first rule-list compile is still running.
        let resolvedContentBlocking = contentBlocking
            ?? ContentRuleListProvider(settings: ContentBlockingSettingsStore())
        self.dataStore = resolvedDataStore
        self.downloads = resolvedDownloads
        self.searchSettings = resolvedSearchSettings
        self.contentBlocking = resolvedContentBlocking
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
            tabs = restored.tabs.map { record in
                BrowserTab(
                    id: record.id,
                    title: record.title,
                    initialURL: record.restorableURL,
                    loadImmediately: record.id == selectedID,
                    lastActivatedAt: record.lastActivatedAt,
                    downloadCenter: resolvedDownloads,
                    searchSettings: resolvedSearchSettings,
                    contentBlocking: resolvedContentBlocking
                )
            }
            selectedTabID = tabs.contains(where: { $0.id == selectedID }) ? selectedID : tabs.first?.id
        } else {
            let tab = BrowserTab(
                downloadCenter: resolvedDownloads,
                searchSettings: resolvedSearchSettings,
                contentBlocking: resolvedContentBlocking
            )
            tabs = [tab]
            selectedTabID = tab.id
        }

        tabs.forEach(configure)
        selectedTab?.activate()
    }

    deinit {
        persistenceTask?.cancel()
    }

    var selectedTab: BrowserTab? {
        tabs.first { $0.id == selectedTabID }
    }

    var canCloseTab: Bool { !tabs.isEmpty }

    func addTab(url: URL? = nil, select: Bool = true, isPrivate: Bool = false) {
        let tab = BrowserTab(
            initialURL: url,
            downloadCenter: downloads,
            searchSettings: searchSettings,
            isPrivate: isPrivate,
            contentBlocking: contentBlocking
        )
        tabs.append(tab)
        configure(tab)
        if select { selectTab(tab.id) }
        schedulePersistence()
    }

    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
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
            let replacement = BrowserTab(
                downloadCenter: downloads,
                searchSettings: searchSettings,
                contentBlocking: contentBlocking
            )
            tabs = [replacement]
            configure(replacement)
            selectedTabID = replacement.id
        } else if wasSelected {
            let nextIndex = min(index, tabs.count - 1)
            selectedTabID = tabs[nextIndex].id
            tabs[nextIndex].activate()
        }
        schedulePersistence()
    }

    func closeSelectedTab() {
        guard let selectedTabID else { return }
        closeTab(selectedTabID)
    }

    func selectNextTab(direction: Int = 1) {
        guard tabs.count > 1,
              let selectedTabID,
              let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        let next = (index + direction + tabs.count) % tabs.count
        selectTab(tabs[next].id)
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

    func requestBookmarkLibrary() {
        bookmarkLibraryRequest += 1
    }

    func requestNewBookmarkFolder(parentID: UUID? = nil) {
        requestedBookmarkFolderParentID = parentID
        bookmarkFolderRequestID = UUID()
    }

    func requestAddressFocus() {
        focusAddressRequest += 1
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
        let snapshot = BrowserWorkspaceSnapshot(
            tabs: persistentTabs.map(\.persistenceRecord),
            selectedTabID: persistentSelection
        )
        dataStore.saveWorkspace(snapshot)
    }

    func resetLocalBrowsingData() async {
        persistenceTask?.cancel()
        persistenceTask = nil
        tabs.forEach { $0.teardown() }
        tabSubscriptions.removeAll()
        tabs = []
        selectedTabID = nil
        dataStore.clearAllBrowserRecords()
        downloads.clearAllRecords()

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

        let replacement = BrowserTab(
            downloadCenter: downloads,
            searchSettings: searchSettings,
            contentBlocking: contentBlocking
        )
        tabs = [replacement]
        selectedTabID = replacement.id
        configure(replacement)
        requestAddressFocus()
    }

    private func configure(_ tab: BrowserTab) {
        let isPrivate = tab.isPrivate
        tab.session.onRequestNewTab = { [weak self] url in
            self?.addTab(url: url, isPrivate: isPrivate)
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
