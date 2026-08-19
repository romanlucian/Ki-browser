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
        let work = try XCTUnwrap(store.createBookmarkFolder(title: "Work", iconID: "briefcase", parentID: nil))
        let code = try XCTUnwrap(store.createBookmarkFolder(title: "Code", iconID: "terminal", parentID: work.id))
        _ = store.addBookmark(title: "Brief", url: "https://example.com/brief", folderID: work.id)
        _ = store.addBookmark(title: "Docs", url: "https://swift.org/documentation/", folderID: code.id)

        let counts = store.bookmarkDescendantCounts()

        XCTAssertEqual(counts[work.id], BookmarkDescendantCounts(bookmarkCount: 2, subfolderCount: 1))
        XCTAssertEqual(counts[code.id], BookmarkDescendantCounts(bookmarkCount: 1, subfolderCount: 0))
        XCTAssertEqual(store.bookmarks(in: work.id).count, 1, "the shallow listing is unchanged")
    }

    func testDataStoreSavesAnEditedBookmarkAndRefusesAnUnsafeAddress() throws {
        let suiteName = "clearframe.bookmarks.edit.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BrowserDataStore(defaults: defaults)
        let design = try XCTUnwrap(store.createBookmarkFolder(title: "Web Design", iconID: "palette", parentID: nil))
        let saved = try XCTUnwrap(
            store.addBookmark(title: "Palette", url: "https://example.com/palette", folderID: design.id)
        )

        XCTAssertTrue(
            store.updateBookmark(id: saved.id, title: "Colour palettes", url: "https://example.com/colour")
        )
        let edited = try XCTUnwrap(store.bookmarks.first { $0.id == saved.id })
        XCTAssertEqual(edited.title, "Colour palettes")
        XCTAssertEqual(edited.url, "https://example.com/colour")
        XCTAssertEqual(edited.folderID, design.id)
        XCTAssertEqual(edited.createdAt, saved.createdAt)

        XCTAssertFalse(
            store.updateBookmark(id: saved.id, title: "Broken", url: "javascript:alert(1)"),
            "the store refuses an address the browser would never open"
        )
        XCTAssertEqual(store.bookmarks.first { $0.id == saved.id }?.url, "https://example.com/colour")

        let reloaded = BrowserDataStore(defaults: defaults)
        XCTAssertEqual(reloaded.bookmarks.first { $0.id == saved.id }?.title, "Colour palettes",
                       "the edit is written to this Mac user profile, not just held in memory")
    }

    /// A bar item is drawn shorter than the bar so it reads as a chip, but it
    /// must still be pointable across the bar's whole height. When it was not,
    /// the few points above and below each item belonged to the bar, and a
    /// right-click aimed at a folder opened the bar's own menu instead.
    /// A bare WebKit user agent gets Clearframe the page sites keep for
    /// clients they cannot identify. Presenting Safari's is a claim about the
    /// engine, and it has to keep both tokens sites actually read.
    func testClearframeAsksForThePageSafariWouldGet() {
        let name = BrowserUserAgent.applicationName

        XCTAssertTrue(name.hasPrefix("Version/"), "sites read the Version token")
        XCTAssertTrue(name.hasSuffix("Safari/\(BrowserUserAgent.safariBuild)"), "and the Safari build")
        XCTAssertFalse(
            BrowserUserAgent.installedSafariVersion.isEmpty,
            "an empty version would produce a malformed user agent"
        )
    }

    func testTheSafariVersionIsReadFromTheMacRatherThanFrozenInTheApp() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let plist = directory.appendingPathComponent("Info.plist")
        try (["CFBundleShortVersionString": "99.9"] as NSDictionary).write(to: plist)

        XCTAssertEqual(BrowserUserAgent.version(fromInfoPlistAt: plist.path), "99.9")
        XCTAssertNil(
            BrowserUserAgent.version(fromInfoPlistAt: directory.appendingPathComponent("missing.plist").path),
            "a Mac without a readable Safari falls back instead of sending nothing"
        )
    }

    func testBookmarksBarItemsArePointableAcrossTheWholeBarHeight() {
        XCTAssertGreaterThan(
            BookmarkBarMetrics.barHeight,
            BookmarkBarMetrics.itemHeight,
            "the chip is meant to sit inside a taller bar"
        )
        XCTAssertEqual(BookmarkBarMetrics.barHeight, 28)
        XCTAssertEqual(BookmarkBarMetrics.itemHeight, 22)
    }

    func testBookmarksBarItemsHugTheirOwnNameAndCapLongOnes() {
        let short = BookmarkBarMetrics.naturalWidth(label: "🤖 AI")
        let longer = BookmarkBarMetrics.naturalWidth(label: "🎨 Design")
        let padding = BookmarkBarMetrics.itemPadding * 2

        XCTAssertEqual(short, BookmarkBarMetrics.labelWidth("🤖 AI") + padding)
        XCTAssertLessThan(short, longer, "a shorter name makes a narrower item — no fixed chip width")
        XCTAssertLessThan(longer, BookmarkBarMetrics.maximumItemWidth)

        let veryLong = "📷 Photography references and colour grading experiments"
        XCTAssertEqual(
            BookmarkBarMetrics.naturalWidth(label: veryLong),
            BookmarkBarMetrics.maximumItemWidth,
            "a long name stops at the cap instead of taking the row"
        )
        XCTAssertNil(
            BookmarkBarMetrics.cappedWidth(label: "🤖 AI"),
            "a name that fits is left to hug its content"
        )
        XCTAssertEqual(BookmarkBarMetrics.cappedWidth(label: veryLong), BookmarkBarMetrics.maximumItemWidth)

        // An icon is part of what has to fit inside the same cap.
        XCTAssertGreaterThan(
            BookmarkBarMetrics.naturalWidth(label: "Clearframe", iconWidth: 13),
            BookmarkBarMetrics.naturalWidth(label: "Clearframe")
        )
        XCTAssertEqual(BookmarkBarMetrics.itemGap, 2, "adjacent bar items sit 2pt apart")
    }

    func testBookmarkMenuCopyNamesWhatTheActionWillDo() {
        XCTAssertEqual(BookmarkMenuCopy.openAll(count: 4), "Open all (4)")
        XCTAssertEqual(BookmarkMenuCopy.openAll(count: 0), "Open all (0)")
        XCTAssertEqual(BookmarkMenuCopy.addCurrentPage(isSavedElsewhere: false), "Add current page")
        XCTAssertEqual(BookmarkMenuCopy.addCurrentPage(isSavedElsewhere: true), "Move current page here")
    }

    func testBookmarkEditorExplainsAnAddressItCannotSave() {
        XCTAssertNil(BookmarkAddressValidation.problem(with: "  https://example.com/page  "))
        XCTAssertNil(BookmarkAddressValidation.problem(with: "http://127.0.0.1:8765/test"))
        XCTAssertEqual(
            BookmarkAddressValidation.problem(with: "javascript:alert(1)"),
            BookmarkAddressValidation.guidance
        )
        XCTAssertEqual(
            BookmarkAddressValidation.problem(with: "https://user:password@example.com/private"),
            BookmarkAddressValidation.guidance
        )
        XCTAssertNotNil(BookmarkAddressValidation.problem(with: "   "))
    }

    func testCurrentPageStateTellsAFolderMenuWhereTheOpenPageIsFiled() {
        let folderID = UUID()
        let saved = BookmarkRecord(title: "Saved", url: "https://example.com/saved", folderID: folderID)

        let filed = CurrentPageBookmarkState(canSave: true, currentBookmark: saved)
        XCTAssertTrue(filed.isSaved)
        XCTAssertEqual(filed.savedFolderID, folderID)

        let unsaved = CurrentPageBookmarkState(canSave: true, currentBookmark: nil)
        XCTAssertFalse(unsaved.isSaved)
        XCTAssertNil(unsaved.savedFolderID)

        let startPage = CurrentPageBookmarkState(canSave: false, currentBookmark: nil)
        XCTAssertFalse(startPage.canSave)
    }

    // MARK: - Tab strip width distribution

    func testTabStripSharesTheWidthAndCapsEveryTabAtTheMaximum() {
        let roomy = TabStripMetrics.widths(availableWidth: 1200, tabCount: 5, selectedIndex: 2)
        XCTAssertEqual(roomy, Array(repeating: TabStripMetrics.maximumTabWidth, count: 5))

        let resolution = TabStripMetrics.resolve(availableWidth: 1200, tabCount: 5, hasSelectedTab: true)
        XCTAssertFalse(resolution.scrolls)
        XCTAssertLessThanOrEqual(resolution.contentWidth, 1200, "tabs stop growing instead of filling the strip")

        XCTAssertTrue(TabStripMetrics.widths(availableWidth: 800, tabCount: 0, selectedIndex: nil).isEmpty)
    }

    func testTabStripCompressesTabsAndKeepsTheSelectedOneWider() {
        // Wide enough that the active tab is at its maximum and the rest share
        // what is left.
        let widths = TabStripMetrics.widths(availableWidth: 800, tabCount: 5, selectedIndex: 0)
        XCTAssertEqual(widths[0], TabStripMetrics.maximumTabWidth)
        XCTAssertEqual(Set(widths.dropFirst()).count, 1, "every unselected tab gets the same width")
        XCTAssertEqual(widths.reduce(0, +) + TabStripMetrics.spacing * 4, 800, accuracy: 4)

        // Tight enough that nothing is at the maximum: the selected tab is
        // still the wider one, by the priority factor.
        let tight = TabStripMetrics.widths(availableWidth: 600, tabCount: 6, selectedIndex: 3)
        let selected = tight[3]
        let unselected = tight[0]
        XCTAssertGreaterThan(selected, unselected)
        XCTAssertEqual(selected / unselected, TabStripMetrics.selectedTabPriority, accuracy: 0.05)
        XCTAssertEqual(Set(tight.enumerated().filter { $0.offset != 3 }.map(\.element)).count, 1)
        XCTAssertLessThanOrEqual(
            TabStripMetrics.resolve(availableWidth: 600, tabCount: 6, hasSelectedTab: true).contentWidth,
            600
        )
    }

    func testTabStripStopsCompressingAtTheComfortableMinimumAndScrolls() {
        let resolution = TabStripMetrics.resolve(availableWidth: 400, tabCount: 12, hasSelectedTab: true)

        XCTAssertTrue(resolution.scrolls, "past the comfortable minimum the strip scrolls instead of shrinking")
        XCTAssertEqual(resolution.unselectedTabWidth, TabStripMetrics.comfortableMinimumTabWidth)
        XCTAssertGreaterThan(resolution.selectedTabWidth, resolution.unselectedTabWidth)
        XCTAssertGreaterThanOrEqual(
            resolution.selectedTabWidth,
            TabStripMetrics.comfortableMinimumTabWidth,
            "the active tab never drops below icon plus close"
        )
        XCTAssertGreaterThan(resolution.contentWidth, 400, "the content overflows, which is what scrolls")

        // One tab either side of the threshold: 8 tabs still fit, 9 do not.
        XCTAssertFalse(TabStripMetrics.resolve(availableWidth: 520, tabCount: 8, hasSelectedTab: true).scrolls)
        XCTAssertTrue(TabStripMetrics.resolve(availableWidth: 520, tabCount: 12, hasSelectedTab: true).scrolls)
    }

    func testTabStripReservesRoomForGroupChipsBeforeSharingWidth() {
        let plain = TabStripMetrics.resolve(availableWidth: 500, tabCount: 4, hasSelectedTab: true)
        let withGroupChip = TabStripMetrics.resolve(
            availableWidth: 500,
            tabCount: 4,
            hasSelectedTab: true,
            reservedWidth: 100
        )

        XCTAssertLessThan(withGroupChip.unselectedTabWidth, plain.unselectedTabWidth)
        XCTAssertLessThanOrEqual(withGroupChip.contentWidth, 500, "a group chip never pushes the strip into scrolling early")
    }

    func testTabChipShowsMoreDetailAsItGetsWider() {
        XCTAssertEqual(TabChipDensity.forWidth(200), .full)
        XCTAssertEqual(TabChipDensity.forWidth(140), .full)
        XCTAssertEqual(TabChipDensity.forWidth(139), .compact)
        XCTAssertEqual(TabChipDensity.forWidth(100), .compact)
        XCTAssertEqual(TabChipDensity.forWidth(99), .tight)
        XCTAssertEqual(TabChipDensity.forWidth(70), .tight)
        XCTAssertEqual(TabChipDensity.forWidth(69), .iconOnly)
        XCTAssertEqual(TabChipDensity.forWidth(TabStripMetrics.comfortableMinimumTabWidth), .iconOnly)

        XCTAssertTrue(TabChipDensity.full.showsTitle)
        XCTAssertTrue(TabChipDensity.tight.showsTitle)
        XCTAssertFalse(TabChipDensity.iconOnly.showsTitle)
        XCTAssertTrue(TabChipDensity.compact.pinsCloseButton)
        XCTAssertFalse(TabChipDensity.tight.pinsCloseButton, "a tight chip shows close only for the tab in play")
    }

    // MARK: - Tab groups

    func testCreatingAGroupPullsItsTabsIntoOneRunAndOffersTheEditor() throws {
        let workspace = try makeTabGroupWorkspace()
        let first = try XCTUnwrap(workspace.tabs.first)
        workspace.addTab()
        workspace.addTab()
        let second = workspace.tabs[1]
        let third = workspace.tabs[2]

        let group = try XCTUnwrap(workspace.createGroup(withTabs: [first.id, third.id]))

        XCTAssertEqual(workspace.tabGroups.map(\.id), [group.id])
        XCTAssertEqual(
            workspace.tabs.map(\.id),
            [first.id, third.id, second.id],
            "the tabs of a group are pulled next to each other"
        )
        XCTAssertEqual(workspace.tabs(inGroup: group.id).map(\.id), [first.id, third.id])
        XCTAssertEqual(workspace.group(group.id)?.colorID, group.colorID)
        XCTAssertNotEqual(group.colorID, TabGroupRecord.defaultColorID, "a new group gets a real color, not the fallback")
        XCTAssertEqual(workspace.pendingGroupEditorID, group.id, "a new group offers its editor so it can be named")
    }

    func testMovingATabBetweenGroupsKeepsRunsTogetherAndDropsTheEmptyGroup() throws {
        let workspace = try makeTabGroupWorkspace()
        workspace.addTab()
        workspace.addTab()
        workspace.addTab()
        let tabIDs = workspace.tabs.map(\.id)
        let left = try XCTUnwrap(workspace.createGroup(withTabs: [tabIDs[0], tabIDs[1]]))
        let right = try XCTUnwrap(workspace.createGroup(withTabs: [tabIDs[3]]))

        workspace.addTab(tabIDs[1], toGroup: right.id)

        XCTAssertEqual(workspace.tabs(inGroup: left.id).map(\.id), [tabIDs[0]])
        XCTAssertEqual(workspace.tabs(inGroup: right.id).map(\.id), [tabIDs[3], tabIDs[1]], "a moved tab joins the end of its new group")
        XCTAssertEqual(workspace.tabs.map(\.id), [tabIDs[0], tabIDs[2], tabIDs[3], tabIDs[1]])
        XCTAssertNotNil(workspace.group(left.id))

        workspace.addTab(tabIDs[0], toGroup: right.id)

        XCTAssertNil(workspace.group(left.id), "a group with no tabs left stops existing")
        XCTAssertEqual(workspace.tabGroups.map(\.id), [right.id])
    }

    func testGroupingTabsOutOfAnotherGroupLeavesThatGroupInOneRun() throws {
        let workspace = try makeTabGroupWorkspace()
        workspace.addTab()
        workspace.addTab()
        workspace.addTab()
        let tabIDs = workspace.tabs.map(\.id)
        let first = try XCTUnwrap(workspace.createGroup(withTabs: [tabIDs[0], tabIDs[1], tabIDs[2]]))

        // Takes the middle tab of an existing group and pairs it with a tab
        // from outside — the group it left must not end up in two pieces.
        let second = try XCTUnwrap(workspace.createGroup(withTabs: [tabIDs[1], tabIDs[3]]))

        let groupOfTab = workspace.tabs.map { $0.groupID }
        let firstRun = groupOfTab.enumerated().filter { $0.element == first.id }.map(\.offset)
        XCTAssertEqual(firstRun.count, 2)
        XCTAssertEqual(firstRun[1] - firstRun[0], 1, "the group left behind is still one unbroken run")
        XCTAssertEqual(workspace.tabs(inGroup: second.id).map(\.id), [tabIDs[1], tabIDs[3]])
        XCTAssertEqual(workspace.tabs.count, 4, "regrouping never closes a tab")
    }

    func testRemovingATabFromAGroupKeepsItOpenNextToTheGroup() throws {
        let workspace = try makeTabGroupWorkspace()
        workspace.addTab()
        workspace.addTab()
        let tabIDs = workspace.tabs.map(\.id)
        let group = try XCTUnwrap(workspace.createGroup(withTabs: [tabIDs[0], tabIDs[1]]))

        workspace.removeTabFromGroup(tabIDs[0])

        XCTAssertNil(workspace.tabs.first { $0.id == tabIDs[0] }?.groupID)
        XCTAssertEqual(workspace.tabs.count, 3, "the tab is still open")
        XCTAssertEqual(workspace.tabs.map(\.id), [tabIDs[1], tabIDs[0], tabIDs[2]], "it steps out just after the group")
        XCTAssertEqual(workspace.tabs(inGroup: group.id).map(\.id), [tabIDs[1]])

        workspace.removeTabFromGroup(tabIDs[1])
        XCTAssertNil(workspace.group(group.id), "removing the last member removes the group")
        XCTAssertEqual(workspace.tabs.count, 3)
    }

    func testUngroupKeepsEveryTabAndDropsOnlyTheGroup() throws {
        let workspace = try makeTabGroupWorkspace()
        workspace.addTab()
        let tabIDs = workspace.tabs.map(\.id)
        let group = try XCTUnwrap(workspace.createGroup(withTabs: tabIDs))

        workspace.ungroup(groupID: group.id)

        XCTAssertTrue(workspace.tabGroups.isEmpty)
        XCTAssertEqual(workspace.tabs.map(\.id), tabIDs)
        XCTAssertTrue(workspace.tabs.allSatisfy { $0.groupID == nil })
        XCTAssertNil(workspace.pendingGroupEditorID)
    }

    func testClosingAGroupClosesItsTabsAndStillLeavesOneOpenTab() throws {
        let workspace = try makeTabGroupWorkspace()
        workspace.addTab()
        workspace.addTab()
        let tabIDs = workspace.tabs.map(\.id)
        let group = try XCTUnwrap(workspace.createGroup(withTabs: [tabIDs[0], tabIDs[1]]))

        workspace.closeGroup(groupID: group.id)

        XCTAssertTrue(workspace.tabGroups.isEmpty)
        XCTAssertEqual(workspace.tabs.map(\.id), [tabIDs[2]])
        XCTAssertEqual(workspace.selectedTabID, tabIDs[2])

        // Closing the group that holds every tab still leaves the workspace
        // with the one empty tab it always guarantees.
        let survivingID = try XCTUnwrap(workspace.tabs.first?.id)
        let onlyGroup = try XCTUnwrap(workspace.createGroup(withTabs: [survivingID]))
        workspace.closeGroup(groupID: onlyGroup.id)

        XCTAssertEqual(workspace.tabs.count, 1)
        XCTAssertNotEqual(workspace.tabs.first?.id, survivingID, "the closed tab was replaced, not kept")
        XCTAssertNil(workspace.tabs.first?.groupID)
        XCTAssertEqual(workspace.selectedTabID, workspace.tabs.first?.id)
        XCTAssertTrue(workspace.tabGroups.isEmpty)
    }

    func testCollapsedGroupHidesItsTabsAndSelectingOneOpensItAgain() throws {
        let workspace = try makeTabGroupWorkspace()
        workspace.addTab()
        workspace.addTab()
        let tabIDs = workspace.tabs.map(\.id)
        let group = try XCTUnwrap(workspace.createGroup(withTabs: [tabIDs[0], tabIDs[1]]))
        workspace.selectTab(tabIDs[0])

        workspace.toggleCollapse(groupID: group.id)

        XCTAssertEqual(workspace.group(group.id)?.isCollapsed, true)
        XCTAssertEqual(workspace.visibleTabs.map(\.id), [tabIDs[2]], "collapsed tabs stay open but leave the strip")
        XCTAssertEqual(workspace.tabs.count, 3)
        XCTAssertEqual(workspace.selectedTabID, tabIDs[2], "collapsing hands the active tab to one still on the strip")

        workspace.selectTab(tabIDs[1])

        XCTAssertEqual(workspace.group(group.id)?.isCollapsed, false, "choosing a hidden tab opens its group")
        XCTAssertEqual(workspace.selectedTabID, tabIDs[1])
        XCTAssertEqual(workspace.visibleTabs.count, 3)
    }

    func testAGroupHoldingEveryTabStaysOpenSoTheStripAlwaysHasAnActiveTab() throws {
        let workspace = try makeTabGroupWorkspace()
        workspace.addTab()
        let group = try XCTUnwrap(workspace.createGroup(withTabs: workspace.tabs.map(\.id)))

        workspace.toggleCollapse(groupID: group.id)

        XCTAssertEqual(workspace.group(group.id)?.isCollapsed, false)
        XCTAssertEqual(workspace.visibleTabs.count, 2)
        XCTAssertNotNil(workspace.selectedTab)
    }

    func testNewTabInAGroupAndToTheRightOfAGroupedTabJoinTheSameGroup() throws {
        let workspace = try makeTabGroupWorkspace()
        let first = try XCTUnwrap(workspace.tabs.first)
        workspace.addTab()
        let outsider = try XCTUnwrap(workspace.tabs.last)
        let group = try XCTUnwrap(workspace.createGroup(withTabs: [first.id]))

        workspace.addTab(toGroup: group.id)
        let inGroup = try XCTUnwrap(workspace.selectedTab)
        XCTAssertEqual(inGroup.groupID, group.id)
        XCTAssertEqual(workspace.tabs.map(\.id), [first.id, inGroup.id, outsider.id])

        workspace.addTab(after: first.id)
        let toTheRight = try XCTUnwrap(workspace.selectedTab)
        XCTAssertEqual(toTheRight.groupID, group.id, "a tab opened next to a grouped tab joins that group")
        XCTAssertEqual(workspace.tabs.map(\.id), [first.id, toTheRight.id, inGroup.id, outsider.id])

        workspace.addTab(after: outsider.id)
        XCTAssertNil(workspace.selectedTab?.groupID, "next to an ungrouped tab it stays ungrouped")
    }

    func testRenamingAndRecoloringAGroupStoresNormalizedValues() throws {
        let workspace = try makeTabGroupWorkspace()
        let group = try XCTUnwrap(workspace.createGroup(withTabs: workspace.tabs.map(\.id)))

        workspace.renameGroup(group.id, title: "  Client work  ")
        workspace.recolorGroup(group.id, colorID: "PINK")
        XCTAssertEqual(workspace.group(group.id)?.title, "Client work")
        XCTAssertEqual(workspace.group(group.id)?.colorID, "pink")

        workspace.recolorGroup(group.id, colorID: "not-a-color")
        XCTAssertEqual(workspace.group(group.id)?.colorID, TabGroupRecord.defaultColorID)
    }

    func testCloseOtherTabsLeavesOnlyTheChosenTab() throws {
        let workspace = try makeTabGroupWorkspace()
        workspace.addTab()
        workspace.addTab()
        let keeper = workspace.tabs[1].id
        _ = workspace.createGroup(withTabs: [workspace.tabs[0].id, workspace.tabs[2].id])

        workspace.closeOtherTabs(keeping: keeper)

        XCTAssertEqual(workspace.tabs.map(\.id), [keeper])
        XCTAssertEqual(workspace.selectedTabID, keeper)
        XCTAssertTrue(workspace.tabGroups.isEmpty, "a group whose tabs are all closed stops existing")
    }

    func testTabGroupsSurviveASavedSessionAndRestoreCollapsedTabsOpen() throws {
        let suiteName = "clearframe.tabGroups.restore.\(UUID().uuidString)"
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
        workspace.addTab(url: URL(string: "https://example.com/one"))
        workspace.addTab(url: URL(string: "https://example.com/two"))
        let groupedIDs = [workspace.tabs[0].id, workspace.tabs[1].id]
        let group = try XCTUnwrap(workspace.createGroup(withTabs: groupedIDs, title: "Research", colorID: "cyan"))
        workspace.selectTab(workspace.tabs[2].id)
        workspace.toggleCollapse(groupID: group.id)
        workspace.persistNow()

        let restored = BrowserWorkspace(
            dataStore: BrowserDataStore(defaults: defaults),
            downloads: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking.provider
        )

        XCTAssertEqual(restored.tabGroups.map(\.title), ["Research"])
        XCTAssertEqual(restored.tabGroups.first?.colorID, "cyan")
        XCTAssertEqual(restored.tabGroups.first?.isCollapsed, true)
        XCTAssertEqual(restored.tabs.filter { $0.groupID == group.id }.map(\.id), groupedIDs)
        XCTAssertEqual(restored.visibleTabs.count, 1, "a collapsed group restores collapsed")

        // A selection inside a collapsed group would leave the strip with no
        // active chip, so restoring opens that group back up.
        restored.selectTab(groupedIDs[0])
        restored.persistNow()
        let reopened = BrowserWorkspace(
            dataStore: BrowserDataStore(defaults: defaults),
            downloads: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking.provider
        )
        XCTAssertEqual(reopened.selectedTabID, groupedIDs[0])
        XCTAssertEqual(reopened.group(group.id)?.isCollapsed, false)
        XCTAssertEqual(reopened.visibleTabs.count, 3)
    }

    private func makeTabGroupWorkspace() throws -> BrowserWorkspace {
        let suiteName = "clearframe.tabGroups.\(UUID().uuidString)"
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

    // MARK: - Site icons

    func testFaviconCaptureStoresOneFilePerNormalizedHostAndReadsItBack() async throws {
        let directory = Self.makeFaviconDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fetcher = RecordingFaviconFetcher(response: Self.pngFixture())
        let store = FaviconStore(directory: directory, fetch: fetcher.fetch)

        await store.capture(
            pageURL: try XCTUnwrap(URL(string: "https://WWW.Example.com/articles/one")),
            declaredIconURLs: [],
            isPrivate: false
        )

        // No declared icon leaves exactly one same-origin attempt.
        XCTAssertEqual(fetcher.requestedURLs.map(\.absoluteString), ["https://www.example.com/favicon.ico"])
        XCTAssertNotNil(store.icon(forHost: "example.com"))
        XCTAssertNotNil(store.icon(forHost: "WWW.Example.COM"), "www and case never split one site in two")

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files, ["example.com.png"])

        // A second store proves the round-trip is the file, not the memory cache.
        let reopened = FaviconStore(directory: directory, fetch: Self.forbiddenFaviconFetcher)
        XCTAssertNotNil(reopened.icon(forHost: "example.com"))
        XCTAssertNil(reopened.icon(forHost: "never-visited.example"))
    }

    func testFaviconLookupNeverReachesTheNetwork() {
        let directory = Self.makeFaviconDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // Any fetch from a plain lookup fails the test outright.
        let store = FaviconStore(directory: directory, fetch: Self.forbiddenFaviconFetcher)

        XCTAssertNil(store.icon(forHost: "example.com"))
        XCTAssertNil(store.icon(forHost: ""))
        XCTAssertNil(store.icon(forHost: "never-visited.example"))
    }

    func testFaviconCandidatesStayOnTheVisitedSiteOwnOrigin() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/story"))

        XCTAssertEqual(
            FaviconStore.iconCandidates(for: pageURL, declared: ["/assets/icon.png", "https://example.com/other.png"])
                .map(\.absoluteString),
            ["https://example.com/assets/icon.png", "https://example.com/favicon.ico"],
            "a same-origin declared icon is tried first, then the origin's own /favicon.ico"
        )
        XCTAssertEqual(
            FaviconStore.iconCandidates(
                for: pageURL,
                declared: [
                    "https://www.google.com/s2/favicons?domain=example.com",
                    "https://cdn.example.net/icon.png",
                    "http://example.com/insecure.png",
                    "https://images.example.com/icon.png"
                ]
            ).map(\.absoluteString),
            ["https://example.com/favicon.ico"],
            "icon services, CDNs, other subdomains, and scheme downgrades are all dropped"
        )
        XCTAssertTrue(
            FaviconStore.iconCandidates(
                for: try XCTUnwrap(URL(string: "file:///Users/private/page.html")),
                declared: ["file:///Users/private/icon.png"]
            ).isEmpty,
            "only real web pages are ever candidates"
        )
        XCTAssertNil(FaviconStore.captureHost(for: try XCTUnwrap(URL(string: "about:blank"))))
    }

    func testPrivateFaviconCaptureKeepsTheIconInMemoryAndOffTheDisk() async throws {
        let directory = Self.makeFaviconDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fetcher = RecordingFaviconFetcher(response: Self.pngFixture())
        let store = FaviconStore(directory: directory, fetch: fetcher.fetch)

        await store.capture(
            pageURL: try XCTUnwrap(URL(string: "https://private.example/page")),
            declaredIconURLs: ["https://private.example/icon.png"],
            isPrivate: true
        )

        XCTAssertNotNil(store.icon(forHost: "private.example"), "the open private tab still shows its icon")
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory.path),
            [],
            "a private tab writes nothing to disk"
        )
        XCTAssertNil(
            FaviconStore(directory: directory, fetch: Self.forbiddenFaviconFetcher).icon(forHost: "private.example"),
            "nothing survives the private tab for another session to read"
        )
    }

    func testClearAllErasesStoredIconsFromDiskAndMemory() async throws {
        let directory = Self.makeFaviconDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FaviconStore(directory: directory, fetch: RecordingFaviconFetcher(response: Self.pngFixture()).fetch)
        await store.capture(
            pageURL: try XCTUnwrap(URL(string: "https://example.com/page")),
            declaredIconURLs: [],
            isPrivate: false
        )
        XCTAssertNotNil(store.icon(forHost: "example.com"))

        store.clearAll()

        XCTAssertNil(store.icon(forHost: "example.com"))
        XCTAssertEqual(
            (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [],
            [],
            "the favicon directory is wiped with the rest of the local browsing data"
        )
    }

    func testFailedFaviconCaptureIsNotRetriedForTheSameHostInThisSession() async throws {
        let directory = Self.makeFaviconDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // What a 404 from the smoke fixture server looks like: no bytes.
        let fetcher = RecordingFaviconFetcher(response: nil)
        let store = FaviconStore(directory: directory, fetch: fetcher.fetch)
        let pageURL = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/index.html"))

        await store.capture(pageURL: pageURL, declaredIconURLs: [], isPrivate: false)
        await store.capture(pageURL: pageURL, declaredIconURLs: [], isPrivate: false)

        XCTAssertEqual(fetcher.requestedURLs.count, 1, "one silent attempt per host per session, then nothing")
        XCTAssertNil(store.icon(forHost: "127.0.0.1"))
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [], [])
    }

    private static func makeFaviconDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clearframe-favicons-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// A 2×2 PNG: enough for ImageIO to decode, downscale, and re-encode.
    private static func pngFixture() -> Data {
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        representation?.setColor(.systemGreen, atX: 0, y: 0)
        representation?.setColor(.systemGreen, atX: 1, y: 0)
        representation?.setColor(.systemGreen, atX: 0, y: 1)
        representation?.setColor(.systemGreen, atX: 1, y: 1)
        return representation?.representation(using: .png, properties: [:]) ?? Data()
    }

    private static let forbiddenFaviconFetcher: FaviconStore.Fetcher = { url in
        XCTFail("a favicon lookup reached the network for \(url.absoluteString)")
        return nil
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

/// Stands in for the network so favicon capture is exercised without one.
/// Main-actor isolated to match `FaviconStore.Fetcher`, so its bookkeeping
/// and the assertions that read it run on the same actor.
@MainActor
private final class RecordingFaviconFetcher {
    private(set) var requestedURLs: [URL] = []
    private let response: Data?

    init(response: Data?) {
        self.response = response
    }

    func fetch(_ url: URL) async -> Data? {
        requestedURLs.append(url)
        return response
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
