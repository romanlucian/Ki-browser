import ClearframeCore
import Foundation
import WebKit
import XCTest
@testable import ClearframeBrowser

@MainActor
final class BrowserBehaviorTests: XCTestCase {
    func testNavigationCancelsAnInFlightAnalysisWithoutRestoringStaleResults() async {
        let session = ControlledAssistantSession(page: Self.page)
        let model = PageAssistantModel()

        let analysisTask = Task { await model.analyzeCurrentPage(session: session) }
        while !session.isWaitingForExtraction { await Task.yield() }

        session.navigationVersion += 1
        session.currentURLString = "https://second.example/new-page"
        model.clearForNavigation()
        session.completeExtraction()
        await analysisTask.value

        XCTAssertEqual(model.state, .idle)
        XCTAssertNil(model.snapshot)
        XCTAssertNil(model.analysis)
    }

    func testAssistantTeardownCancelsWorkAndErasesTabScopedPageData() async {
        let session = ControlledAssistantSession(page: Self.page)
        let model = PageAssistantModel()
        let analysisTask = Task { await model.analyzeCurrentPage(session: session) }
        while !session.isWaitingForExtraction { await Task.yield() }

        model.teardown()
        session.completeExtraction()
        await analysisTask.value

        XCTAssertEqual(model.state, .idle)
        XCTAssertNil(model.snapshot)
        XCTAssertNil(model.analysis)
        XCTAssertNil(model.savedSource)
        XCTAssertNil(model.operationMessage)
    }

    func testOptionalAIErrorKeepsTheValidLocalResultVisible() async {
        let session = ControlledAssistantSession(page: Self.page, waitsForExtraction: false)
        let model = PageAssistantModel(remoteProviderFactory: { _ in FailingProvider() })
        await model.analyzeCurrentPage(session: session)
        let localResult = try? XCTUnwrap(model.analysis)

        await model.improveWithAI(
            configuration: OpenAIProviderConfiguration(apiKey: "test", safetyIdentifier: "test")
        )

        XCTAssertEqual(model.state, .ready)
        XCTAssertEqual(model.analysis, localResult)
        XCTAssertEqual(model.analysis?.mode, .local)
        XCTAssertNotNil(model.operationError)
    }

    func testProviderDefaultMigratesOnlyNonCustomizedModelSettings() throws {
        let suiteName = "clearframe.provider.default-migration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let keychain = KeychainStore(
            service: "clearframe.tests.\(UUID().uuidString)",
            account: "unused"
        )

        defaults.set("retired-default-model", forKey: "clearframe.openAIModel")
        defaults.set(false, forKey: "clearframe.openAIModelCustomized")
        XCTAssertEqual(
            AIConfigurationStore(defaults: defaults, keychain: keychain).model,
            OpenAIProviderDefaults.model
        )

        defaults.set("owner-selected-model", forKey: "clearframe.openAIModel")
        defaults.set(true, forKey: "clearframe.openAIModelCustomized")
        XCTAssertEqual(
            AIConfigurationStore(defaults: defaults, keychain: keychain).model,
            "owner-selected-model"
        )
    }

    func testDataStoreRestoresLastKnownGoodBookmarksAndPreservesCorruptBytes() throws {
        let suiteName = "clearframe.persistence.recovery.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "clearframe.bookmarks.v1"
        let corrupt = Data("not valid bookmark JSON".utf8)
        let expected = [BookmarkRecord(title: "Recovered", url: "https://example.com/recovered")]
        let backup = try JSONEncoder().encode(expected)
        defaults.set(corrupt, forKey: key)
        defaults.set(backup, forKey: "\(key).lastKnownGood")

        let store = BrowserDataStore(defaults: defaults)

        XCTAssertEqual(store.bookmarks, expected)
        XCTAssertNotNil(store.recoveryNotice)
        XCTAssertEqual(defaults.data(forKey: "\(key).unreadable"), corrupt)
        let restoredPrimary = try JSONDecoder().decode(
            [BookmarkRecord].self,
            from: XCTUnwrap(defaults.data(forKey: key))
        )
        XCTAssertEqual(restoredPrimary, expected)
    }

    func testDataStoreDoesNotOverwriteUnreadableBookmarksWhenNoBackupExists() throws {
        let suiteName = "clearframe.persistence.unreadable.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "clearframe.bookmarks.v1"
        let corrupt = Data("unreadable".utf8)
        defaults.set(corrupt, forKey: key)

        let store = BrowserDataStore(defaults: defaults)

        XCTAssertTrue(store.bookmarks.isEmpty)
        XCTAssertNotNil(store.recoveryNotice)
        XCTAssertEqual(defaults.data(forKey: key), corrupt)
        XCTAssertEqual(defaults.data(forKey: "\(key).unreadable"), corrupt)
    }

    func testBrowserSessionRejectsUnsafeMainNavigationInputs() throws {
        let suiteName = "clearframe.navigation.policy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = BrowserSession(
            downloadCenter: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults)
        )
        defer { session.teardown() }

        for value in [
            "data:text/html,private",
            "about:blank",
            "https://user:password@example.com/private",
            "https:///missing-host"
        ] {
            session.load(try XCTUnwrap(URL(string: value)))
            guard case .failed(let failure) = session.loadState else {
                return XCTFail("Unsafe URL was not blocked: \(value)")
            }
            XCTAssertEqual(failure.kind, .blocked)
            XCTAssertTrue(session.currentURLString.isEmpty)
        }
    }

    func testPrivateTabsUseEphemeralStorageAndAreNeverRestored() throws {
        let suiteName = "clearframe.private.tabs.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BrowserDataStore(defaults: defaults)
        let blocking = try Self.makeTestContentBlocking(defaults: defaults)
        defer { blocking.removeStore() }
        let workspace = BrowserWorkspace(
            dataStore: store,
            downloads: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking.provider
        )

        workspace.addTab(isPrivate: true)
        let privateTab = try XCTUnwrap(workspace.selectedTab)
        XCTAssertTrue(privateTab.isPrivate)
        XCTAssertFalse(privateTab.session.webView.configuration.websiteDataStore.isPersistent)
        // Tracker blocking is a web-view setting, so private tabs use it too.
        XCTAssertEqual(blocking.provider.registeredWebViewCount, workspace.tabs.count)
        workspace.persistNow()

        let snapshot = try XCTUnwrap(store.loadWorkspace())
        XCTAssertEqual(snapshot.tabs.count, 1)
        XCTAssertFalse(snapshot.tabs.contains(where: { $0.id == privateTab.id }))
        XCTAssertNotEqual(snapshot.selectedTabID, privateTab.id)

        privateTab.session.onRequestNewTab?(URL(string: "https://example.com/private-popup")!)
        XCTAssertTrue(workspace.selectedTab?.isPrivate == true)

        let tabCountBeforeUnsafeExternalURL = workspace.tabs.count
        workspace.openExternalURL(URL(string: "file:///tmp/private")!)
        XCTAssertEqual(workspace.tabs.count, tabCountBeforeUnsafeExternalURL)
        workspace.openExternalURL(URL(string: "https://example.com/external")!)
        XCTAssertFalse(workspace.selectedTab?.isPrivate == true)
    }

    func testClearLocalBrowsingDataResetsRecordsAndKeepsOneCleanTab() async throws {
        let suiteName = "clearframe.data.reset.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BrowserDataStore(defaults: defaults)
        let blocking = try Self.makeTestContentBlocking(defaults: defaults)
        defer { blocking.removeStore() }
        let workspace = BrowserWorkspace(
            dataStore: store,
            downloads: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking.provider
        )
        _ = store.addBookmark(title: "Saved", url: "https://example.com/saved", folderID: nil)
        store.recordVisit(title: "Visited", url: "https://example.com/visited")
        workspace.addTab(url: URL(string: "https://example.com/open"))
        workspace.persistNow()
        await blocking.provider.setSiteDisabled(true, forHost: "example.com")
        XCTAssertEqual(blocking.provider.settings.disabledHosts, ["example.com"])

        await workspace.resetLocalBrowsingData()

        XCTAssertTrue(store.bookmarks.isEmpty)
        XCTAssertTrue(store.bookmarkFolders.isEmpty)
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertNil(store.loadWorkspace())
        XCTAssertEqual(workspace.tabs.count, 1)
        XCTAssertFalse(try XCTUnwrap(workspace.selectedTab).isPrivate)
        XCTAssertEqual(workspace.selectedTab?.session.currentURLString, "")
        XCTAssertEqual(workspace.selectedTab?.session.pageTitle, "New Tab")
        XCTAssertTrue(blocking.provider.settings.disabledHosts.isEmpty)
        XCTAssertEqual(blocking.provider.status, .active(ruleCount: 2))
    }

    func testContentBlockingSettingsPersistTheGlobalSwitchAndSiteExceptions() throws {
        let suiteName = "clearframe.contentBlocking.settings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = ContentBlockingSettingsStore(defaults: defaults)
        XCTAssertTrue(settings.isEnabled, "tracker blocking is on by default")
        XCTAssertTrue(settings.disabledHosts.isEmpty)

        settings.setDisabled(true, forHost: "WWW.Example.com")
        settings.setDisabled(true, forHost: "news.example.org")
        XCTAssertFalse(settings.setDisabled(true, forHost: "example.com"), "the same site is stored once")
        XCTAssertEqual(settings.disabledHosts, ["example.com", "news.example.org"])
        XCTAssertTrue(settings.isDisabled(forHost: "www.example.com"))
        XCTAssertFalse(settings.isDisabled(forHost: "other.example"))
        settings.setEnabled(false)

        let reloaded = ContentBlockingSettingsStore(defaults: defaults)
        XCTAssertFalse(reloaded.isEnabled)
        XCTAssertEqual(reloaded.disabledHosts, ["example.com", "news.example.org"])

        XCTAssertTrue(reloaded.setDisabled(false, forHost: "example.com"))
        XCTAssertEqual(reloaded.disabledHosts, ["news.example.org"])
        XCTAssertTrue(reloaded.clearExceptions())
        XCTAssertFalse(reloaded.clearExceptions())
        XCTAssertTrue(ContentBlockingSettingsStore(defaults: defaults).disabledHosts.isEmpty)
    }

    func testContentBlockingSettingsNormalizeSiteHostsAndRejectNonWebInput() {
        XCTAssertEqual(
            ContentBlockingSettingsStore.normalizedHost(from: "https://WWW.Example.COM/page?q=1"),
            "example.com"
        )
        XCTAssertEqual(
            ContentBlockingSettingsStore.normalizedHost(from: "http://news.example.co.uk:8080/"),
            "news.example.co.uk"
        )
        for rejected in [
            "",
            "example.com",
            "about:blank",
            "file:///Users/private",
            "data:text/html,private",
            "https://user:password@example.com/"
        ] {
            XCTAssertNil(ContentBlockingSettingsStore.normalizedHost(from: rejected), rejected)
        }
    }

    func testShippedTrackerRuleListCompilesInWebKitWithAndWithoutSiteExceptions() async throws {
        let directory = Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store: WKContentRuleListStore? = WKContentRuleListStore(url: directory)
        let ruleStore = try XCTUnwrap(store, "WebKit could not open a rule store in \(directory.path)")

        let shipped = ContentRuleListSource.make(domains: TrackerBlockerCatalog.current.domains)
        let compiled = try await Self.compile(shipped, identifier: "canary.plain", in: ruleStore)
        XCTAssertEqual(compiled.identifier, "canary.plain")

        let withException = ContentRuleListSource.make(
            domains: TrackerBlockerCatalog.current.domains,
            exceptionHosts: ["example.com"]
        )
        let compiledWithException = try await Self.compile(
            withException,
            identifier: "canary.exception",
            in: ruleStore
        )
        XCTAssertEqual(compiledWithException.identifier, "canary.exception")
    }

    func testContentRuleListProviderCompilesOnceAndAppliesToRegisteredWebViews() async throws {
        let suiteName = "clearframe.contentBlocking.provider.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let blocking = try Self.makeTestContentBlocking(defaults: defaults)
        defer { blocking.removeStore() }
        let provider = blocking.provider

        await provider.refresh()
        XCTAssertEqual(provider.status, .active(ruleCount: 2))
        let firstIdentifier = try XCTUnwrap(provider.appliedIdentifier)

        let webView = WKWebView(frame: .zero)
        provider.register(webView)
        XCTAssertEqual(provider.registeredWebViewCount, 1)

        await provider.setSiteDisabled(true, forHost: "example.com")
        XCTAssertEqual(provider.settings.disabledHosts, ["example.com"])
        XCTAssertEqual(provider.status, .active(ruleCount: 2))
        XCTAssertNotEqual(provider.appliedIdentifier, firstIdentifier)
        let exceptionIdentifier = try XCTUnwrap(provider.appliedIdentifier)
        let storedIdentifiers = await Self.storedIdentifiers(in: blocking.ruleStore)
        XCTAssertEqual(
            storedIdentifiers,
            [exceptionIdentifier],
            "superseded rule lists should not pile up on disk"
        )

        await provider.setEnabled(false)
        XCTAssertEqual(provider.status, .disabled)
        XCTAssertNil(provider.appliedIdentifier)
        let identifiersWhileOff = await Self.storedIdentifiers(in: blocking.ruleStore)
        XCTAssertTrue(identifiersWhileOff.isEmpty, "turning blocking off leaves no compiled list behind")

        await provider.setEnabled(true)
        XCTAssertEqual(provider.status, .active(ruleCount: 2))
        XCTAssertEqual(provider.appliedIdentifier, exceptionIdentifier)

        provider.unregister(webView)
        XCTAssertEqual(provider.registeredWebViewCount, 0)
    }

    func testContentRuleListIdentifierTracksTheListVersionAndSiteExceptions() {
        let base = ContentRuleListProvider.identifier(version: "2026.08.14.1", exceptionHosts: [])
        XCTAssertTrue(base.hasPrefix("clearframe-tracker-block.v2026.08.14.1.x"))
        XCTAssertEqual(base, ContentRuleListProvider.identifier(version: "2026.08.14.1", exceptionHosts: []))
        XCTAssertNotEqual(base, ContentRuleListProvider.identifier(version: "2026.08.14.2", exceptionHosts: []))

        let withExceptions = ContentRuleListProvider.identifier(
            version: "2026.08.14.1",
            exceptionHosts: ["example.com", "news.example.org"]
        )
        XCTAssertNotEqual(withExceptions, base)
        XCTAssertEqual(
            withExceptions,
            ContentRuleListProvider.identifier(
                version: "2026.08.14.1",
                exceptionHosts: ["news.example.org", "example.com", "example.com"]
            ),
            "order and repetition must not change the compiled identity"
        )
    }

    func testBrowserSessionRegistersItsWebViewWithTheContentBlockerUntilTeardown() async throws {
        let suiteName = "clearframe.contentBlocking.session.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let blocking = try Self.makeTestContentBlocking(defaults: defaults)
        defer { blocking.removeStore() }
        await blocking.provider.refresh()

        let session = BrowserSession(
            downloadCenter: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking.provider
        )
        XCTAssertEqual(blocking.provider.registeredWebViewCount, 1)

        session.teardown()
        XCTAssertEqual(blocking.provider.registeredWebViewCount, 0)
    }

    func testShieldStateMapsProviderStatusAndPerSiteExceptionForAllFourStates() {
        XCTAssertEqual(ShieldState.make(status: .active(ruleCount: 2), hostDisabled: false), .activeForSite)
        XCTAssertEqual(ShieldState.make(status: .compiling, hostDisabled: false), .activeForSite)
        XCTAssertEqual(ShieldState.activeForSite.statusLine, "On for this site")
        XCTAssertEqual(ShieldState.activeForSite.symbolName, "shield")

        XCTAssertEqual(ShieldState.make(status: .active(ruleCount: 2), hostDisabled: true), .disabledForSite)
        XCTAssertEqual(ShieldState.make(status: .compiling, hostDisabled: true), .disabledForSite)
        XCTAssertEqual(ShieldState.disabledForSite.statusLine, "Off for this site")
        XCTAssertEqual(ShieldState.disabledForSite.symbolName, "shield.slash")

        // A global off wins over any per-site exception state.
        XCTAssertEqual(ShieldState.make(status: .disabled, hostDisabled: false), .disabledGlobally)
        XCTAssertEqual(ShieldState.make(status: .disabled, hostDisabled: true), .disabledGlobally)
        XCTAssertEqual(ShieldState.disabledGlobally.statusLine, "Off in Settings")
        XCTAssertEqual(ShieldState.disabledGlobally.symbolName, "shield.slash")

        XCTAssertEqual(ShieldState.make(status: .unavailable("store error"), hostDisabled: false), .unavailable)
        XCTAssertEqual(ShieldState.make(status: .unavailable("store error"), hostDisabled: true), .unavailable)
        XCTAssertEqual(ShieldState.unavailable.statusLine, "Filter unavailable")
        XCTAssertEqual(ShieldState.unavailable.symbolName, "shield.slash")
    }

    func testIdentityColorIsDeterministicAcrossCalls() {
        let first = IdentityColor.color(forHost: "example.com")
        let second = IdentityColor.color(forHost: "example.com")
        XCTAssertEqual(first, second)
        // Different call, different host: still deterministic, and not the
        // shared neutral fallback used for empty input.
        XCTAssertEqual(IdentityColor.color(forHost: "example.com"), IdentityColor.color(forHost: "example.com"))
        XCTAssertNotEqual(IdentityColor.color(forHost: "example.com"), IdentityColor.fallback)
    }

    func testIdentityColorTreatsWWWPrefixAsTheSameSite() {
        XCTAssertEqual(
            IdentityColor.color(forHost: "www.example.com"),
            IdentityColor.color(forHost: "example.com")
        )
        XCTAssertEqual(
            IdentityColor.color(forHost: "WWW.Example.COM"),
            IdentityColor.color(forHost: "example.com"),
            "case is normalized the same way host exceptions are"
        )
    }

    func testIdentityColorFallsBackForEmptyOrInvalidHost() {
        XCTAssertEqual(IdentityColor.color(forHost: ""), IdentityColor.fallback)
        XCTAssertEqual(IdentityColor.color(forHost: "   "), IdentityColor.fallback)
    }

    func testTabsStartOnTheAIGuideSurfaceAndRestoredTabsStayThere() throws {
        let suiteName = "clearframe.startSurface.default.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BrowserDataStore(defaults: defaults)
        let record = BrowserTabRecord(
            id: UUID(),
            url: "https://example.com/restored",
            title: "Restored",
            lastActivatedAt: Date()
        )
        store.saveWorkspace(BrowserWorkspaceSnapshot(tabs: [record], selectedTabID: record.id))
        let blocking = try Self.makeTestContentBlocking(defaults: defaults)
        defer { blocking.removeStore() }

        let workspace = BrowserWorkspace(
            dataStore: store,
            downloads: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking.provider
        )

        XCTAssertEqual(workspace.tabs.first?.startSurface, .aiHome, "a restored tab opens on the AI guide")
        workspace.addTab()
        XCTAssertEqual(workspace.selectedTab?.startSurface, .aiHome, "a new tab opens on the AI guide")
        XCTAssertTrue(workspace.tabs.allSatisfy { $0.startSurface == .aiHome })
    }

    func testOpenBookmarksHomeShowsTheBookmarksSurfaceOnTheSelectedTab() throws {
        let workspace = try makeSurfaceTestWorkspace()
        let tab = try XCTUnwrap(workspace.selectedTab)
        tab.session.navigate("https://example.com/page")
        tab.session.stopLoading()
        XCTAssertEqual(tab.session.loadState, .content)

        workspace.openBookmarksHome()

        XCTAssertEqual(tab.startSurface, .bookmarksHome)
        XCTAssertEqual(tab.session.loadState, .startPage)
        XCTAssertEqual(tab.session.currentURLString, "")
        XCTAssertEqual(workspace.tabs.count, 1, "the bookmarks home reuses the selected tab")
    }

    func testRequestBookmarkLibraryKeepsItsCounterAndOpensTheBookmarksHome() throws {
        let workspace = try makeSurfaceTestWorkspace()
        let tab = try XCTUnwrap(workspace.selectedTab)
        let requestsBefore = workspace.bookmarkLibraryRequest

        workspace.requestBookmarkLibrary()

        XCTAssertEqual(workspace.bookmarkLibraryRequest, requestsBefore + 1, "the library request counter is still published")
        XCTAssertEqual(tab.startSurface, .bookmarksHome)
        XCTAssertEqual(tab.session.loadState, .startPage)

        workspace.requestBookmarkLibrary()
        XCTAssertEqual(workspace.bookmarkLibraryRequest, requestsBefore + 2)
    }

    func testGoingHomeReturnsTheTabToTheAIGuideSurface() throws {
        let workspace = try makeSurfaceTestWorkspace()
        let tab = try XCTUnwrap(workspace.selectedTab)
        workspace.openBookmarksHome()
        XCTAssertEqual(tab.startSurface, .bookmarksHome)

        tab.goHome()

        XCTAssertEqual(tab.startSurface, .aiHome, "Home always means the AI guide")
        XCTAssertEqual(tab.session.loadState, .startPage)
    }

    func testBookmarksHomeSearchMatchesFolderTitlesAndBookmarkTitlesOrAddresses() {
        let folders = [
            BookmarkFolderRecord(title: "Web Design", emoji: "🎨"),
            BookmarkFolderRecord(title: "Programming", emoji: "💻"),
            BookmarkFolderRecord(title: "Shopping", emoji: "🛍️")
        ]
        let bookmarks = [
            BookmarkRecord(title: "Swift documentation", url: "https://swift.org/documentation/"),
            BookmarkRecord(title: "Colour palettes", url: "https://example.com/palette")
        ]

        XCTAssertEqual(BookmarksHomeSearch.folders(folders, matching: "desi").map(\.title), ["Web Design"])
        XCTAssertEqual(BookmarksHomeSearch.folders(folders, matching: "PROGRAM").map(\.title), ["Programming"])
        XCTAssertTrue(BookmarksHomeSearch.folders(folders, matching: "photography").isEmpty)
        XCTAssertEqual(
            BookmarksHomeSearch.folders(folders, matching: "   ").count,
            folders.count,
            "a blank query filters nothing out"
        )

        XCTAssertEqual(BookmarksHomeSearch.bookmarks(bookmarks, matching: "SWIFT").map(\.title), ["Swift documentation"])
        XCTAssertEqual(
            BookmarksHomeSearch.bookmarks(bookmarks, matching: "example.com").map(\.title),
            ["Colour palettes"],
            "the web address matches as well as the title"
        )
        XCTAssertTrue(BookmarksHomeSearch.bookmarks(bookmarks, matching: "no such page").isEmpty)
        XCTAssertEqual(BookmarksHomeSearch.bookmarks(bookmarks, matching: "").count, bookmarks.count)
    }

    func testDataStoreForwardsRolledUpFolderCountsForTheBookmarksHome() throws {
        let suiteName = "clearframe.bookmarks.counts.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BrowserDataStore(defaults: defaults)
        let work = try XCTUnwrap(store.createBookmarkFolder(title: "Work", emoji: "💼", parentID: nil))
        let code = try XCTUnwrap(store.createBookmarkFolder(title: "Code", emoji: "💻", parentID: work.id))
        _ = store.addBookmark(title: "Brief", url: "https://example.com/brief", folderID: work.id)
        _ = store.addBookmark(title: "Docs", url: "https://swift.org/documentation/", folderID: code.id)

        let counts = store.bookmarkDescendantCounts()

        XCTAssertEqual(counts[work.id], BookmarkDescendantCounts(bookmarkCount: 2, subfolderCount: 1))
        XCTAssertEqual(counts[code.id], BookmarkDescendantCounts(bookmarkCount: 1, subfolderCount: 0))
        XCTAssertEqual(store.bookmarks(in: work.id).count, 1, "the shallow listing is unchanged")
    }

    private func makeSurfaceTestWorkspace() throws -> BrowserWorkspace {
        let suiteName = "clearframe.startSurface.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let blocking = try Self.makeTestContentBlocking(defaults: defaults)
        addTeardownBlock { blocking.removeStore() }
        return BrowserWorkspace(
            dataStore: BrowserDataStore(defaults: defaults),
            downloads: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking.provider
        )
    }

    private static func makeTemporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clearframe-content-blocking-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// A provider backed by a throwaway rule store and a two-domain list, so
    /// tests never touch the shared WebKit store or pay for the shipped list.
    private static func makeTestContentBlocking(
        defaults: UserDefaults,
        domains: [String] = ["metrics.example", "tracker.example"]
    ) throws -> TestContentBlocking {
        let directory = makeTemporaryDirectory()
        let store: WKContentRuleListStore? = WKContentRuleListStore(url: directory)
        let ruleStore = try XCTUnwrap(store, "WebKit could not open a rule store in \(directory.path)")
        let provider = ContentRuleListProvider(
            settings: ContentBlockingSettingsStore(defaults: defaults),
            blockList: TrackerBlockList(release: TrackerBlockerCatalog.release, domains: domains),
            ruleStore: ruleStore
        )
        return TestContentBlocking(provider: provider, ruleStore: ruleStore, directory: directory)
    }

    private static func compile(
        _ source: String,
        identifier: String,
        in store: WKContentRuleListStore
    ) async throws -> WKContentRuleList {
        try await withCheckedThrowingContinuation { continuation in
            store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: source) { list, error in
                if let list {
                    continuation.resume(returning: list)
                } else {
                    continuation.resume(throwing: error ?? ContentBlockingError.compileFailed)
                }
            }
        }
    }

    private static func storedIdentifiers(in store: WKContentRuleListStore) async -> [String] {
        let identifiers: [String] = await withCheckedContinuation { continuation in
            store.getAvailableContentRuleListIdentifiers { continuation.resume(returning: $0 ?? []) }
        }
        return identifiers.filter { $0.hasPrefix(ContentRuleListProvider.identifierPrefix) }.sorted()
    }

    private static let page = PageSnapshot(
        title: "First page",
        url: "https://first.example/article",
        hostname: "first.example",
        scheme: "https",
        language: "en",
        text: "This first source contains enough readable text to create a local summary. It includes another sentence so the deterministic analyzer can select grounded key points. A final sentence explains that stale results must never appear after navigation.",
        wordCount: 35,
        hasPasswordField: false,
        formActions: []
    )
}

@MainActor
private struct TestContentBlocking {
    let provider: ContentRuleListProvider
    let ruleStore: WKContentRuleListStore
    let directory: URL

    func removeStore() {
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class ControlledAssistantSession: PageAssistantSession {
    var navigationVersion = 1
    var currentURLString: String
    private let page: PageSnapshot
    private let waitsForExtraction: Bool
    private var continuation: CheckedContinuation<PageSnapshot, Error>?
    private(set) var isWaitingForExtraction = false

    init(page: PageSnapshot, waitsForExtraction: Bool = true) {
        self.page = page
        self.waitsForExtraction = waitsForExtraction
        currentURLString = page.url
    }

    func extractPage() async throws -> PageSnapshot {
        guard waitsForExtraction else { return page }
        isWaitingForExtraction = true
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func completeExtraction() {
        continuation?.resume(returning: page)
        continuation = nil
        isWaitingForExtraction = false
    }

    func revealEvidence(_ text: String, expectedNavigationVersion: Int?) async -> Bool {
        expectedNavigationVersion == navigationVersion && !text.isEmpty
    }
}

private struct FailingProvider: PageIntelligenceProviding {
    func analyze(page: PageSnapshot) async throws -> PageAnalysisContent {
        throw PageIntelligenceError.remoteFailure("Deliberate provider failure")
    }

    func translate(text: String, sourceLanguage: String, targetLanguage: String) async throws -> String {
        throw PageIntelligenceError.remoteFailure("Deliberate provider failure")
    }
}
