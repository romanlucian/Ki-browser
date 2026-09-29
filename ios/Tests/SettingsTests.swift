import XCTest
import WebKit
import LimeghostCore
@testable import Limeghost
@testable import LimeghostShared

@MainActor
final class SettingsTests: XCTestCase {
    /// A workspace that touches nothing real. These tests run inside the app,
    /// and Settings writes preferences, switches tracker blocking and clears
    /// browsing data, which deletes whatever folders and website data it is
    /// handed. `WorkspaceHost.forTesting` isolates what the other tests
    /// change and no more, so this one isolates everything: its own suite,
    /// its own folders, a website data store that forgets, and a tracker
    /// switch of its own.
    private func makeWorkspace() throws -> (workspace: BrowserWorkspace, preferences: BrowserPreferences) {
        let suiteName = "clearframe.iosSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("limeghost-settings-\(UUID().uuidString)", isDirectory: true)
        let rules = scratch.appendingPathComponent("Rules", isDirectory: true)
        try FileManager.default.createDirectory(at: rules, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: scratch) }

        let blocking = ContentRuleListProvider(
            settings: ContentBlockingSettingsStore(defaults: defaults),
            blockList: TrackerBlockList(release: TrackerBlockerCatalog.release, domains: ["tracker.example"]),
            ruleStore: try XCTUnwrap(WKContentRuleListStore(url: rules))
        )
        let workspace = BrowserWorkspace(
            dataStore: BrowserDataStore(defaults: defaults),
            downloads: NoDownloads(),
            pageSharing: IOSPageSharing.self,
            clipboard: IOSClipboard(),
            makeSessionPlatform: { IOSSessionPlatform() },
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking,
            favicons: FaviconStore(directory: scratch.appendingPathComponent("Favicons", isDirectory: true)),
            tabPreviews: TabPreviewStore(directory: nil),
            webFeatures: WebFeatureSettingsStore(defaults: defaults),
            restoresSession: false,
            websiteDataStore: .nonPersistent(),
            assistantPopups: .overAssistant
        )
        return (workspace, BrowserPreferences(defaults: defaults))
    }

    // MARK: - General

    /// Two of the Mac's three. A page of one's own choosing is left out: an
    /// iPhone app is resumed far more often than it is started.
    func testStartUpOffersTwoChoices() {
        XCTAssertEqual(SettingsModel.startupChoices, [.restore, .newTab])
    }

    /// The choice lands in the store the workspace reads at launch, and
    /// choosing the guide stops the open tabs being kept.
    func testTheStartUpChoiceIsTheOneALaunchReads() throws {
        let (workspace, preferences) = try makeWorkspace()
        let model = SettingsModel(workspace: workspace, preferences: preferences)
        let store = workspace.dataStore

        model.startup = .restore
        let soup = BrowserTabRecord(id: UUID(), url: "https://example.com/soup", title: "Soup", lastActivatedAt: Date())
        store.saveWorkspace(BrowserWorkspaceSnapshot(tabs: [soup], selectedTabID: soup.id))
        XCTAssertNotNil(store.loadWorkspace())

        model.startup = .newTab
        XCTAssertEqual(store.startupBehaviour, .newTab)
        XCTAssertFalse(store.restoresTabs)
        XCTAssertNil(store.loadWorkspace(), "the tabs somebody said not to reopen were kept")
    }

    /// The phone has no ⌘+, so a size chosen here reaches the pages already
    /// open, private ones too, as well as every page opened after.
    func testTextSizeReachesThePagesAlreadyOpen() throws {
        let (workspace, preferences) = try makeWorkspace()
        workspace.addTab(url: URL(string: "https://example.com/one"))
        workspace.addTab(url: URL(string: "https://example.com/two"), isPrivate: true)
        let model = SettingsModel(workspace: workspace, preferences: preferences)

        model.pageZoom = 1.5

        XCTAssertEqual(preferences.defaultPageZoom, 1.5)
        XCTAssertEqual(model.pageZoom, 1.5)
        XCTAssertGreaterThan(workspace.tabs.count, 1)
        for tab in workspace.tabs {
            XCTAssertEqual(tab.session.pageZoom, 1.5)
            XCTAssertEqual(tab.session.webView.pageZoom, 1.5, "the size never reached the web view")
        }
    }

    func testTextSizesReadAsPercentages() {
        XCTAssertEqual(SettingsWording.percent(1.0), "100%")
        XCTAssertEqual(SettingsWording.percent(0.67), "67%")
        XCTAssertEqual(SettingsWording.percent(1.25), "125%")
    }

    // MARK: - Search and privacy

    /// The engine chosen here is the one the address bar searches with.
    func testTheSearchEngineIsTheAddressBarsOwn() throws {
        let (workspace, preferences) = try makeWorkspace()
        let model = SettingsModel(workspace: workspace, preferences: preferences)

        model.searchEngine = .braveSearch

        XCTAssertEqual(workspace.searchSettings.selectedEngine, .braveSearch)
        XCTAssertTrue(SettingsWording.searchFooter(.braveSearch).contains(SearchEngine.braveSearch.displayName))
    }

    /// Turning history off stops new visits being saved and erases none.
    func testTurningHistoryOffKeepsWhatWasSaved() throws {
        let (workspace, preferences) = try makeWorkspace()
        let model = SettingsModel(workspace: workspace, preferences: preferences)
        let store = workspace.dataStore
        model.savesHistory = true
        store.recordVisit(title: "Bread", url: "https://example.com/bread")

        model.savesHistory = false
        store.recordVisit(title: "Soup", url: "https://example.com/soup")

        XCTAssertFalse(store.savesHistory)
        XCTAssertEqual(store.history.map(\.title), ["Bread"])
    }

    /// The switch is the one a new tab's web view is configured from.
    func testTheHTTPSSwitchIsTheOneNewTabsRead() throws {
        let (workspace, preferences) = try makeWorkspace()
        let model = SettingsModel(workspace: workspace, preferences: preferences)

        model.upgradesToHTTPS = false
        workspace.addTab()
        XCTAssertFalse(try XCTUnwrap(workspace.selectedTab).session.webView.configuration.upgradeKnownHostsToHTTPS)

        model.upgradesToHTTPS = true
        workspace.addTab()
        XCTAssertTrue(try XCTUnwrap(workspace.selectedTab).session.webView.configuration.upgradeKnownHostsToHTTPS)
    }

    /// Tracker blocking's switch is the provider's, and turning it off is
    /// applied before the call returns.
    func testTheTrackerSwitchIsTheOneEveryPageUses() async throws {
        let (workspace, preferences) = try makeWorkspace()
        let model = SettingsModel(workspace: workspace, preferences: preferences)

        await model.setBlocksTrackers(false)

        XCTAssertFalse(model.blocksTrackers)
        XCTAssertFalse(workspace.contentBlocking.settings.isEnabled)
        XCTAssertEqual(workspace.contentBlocking.status, .disabled)
    }

    // MARK: - Clearing

    /// Clearing is the Mac's reset, and like Safari's and Chrome's it keeps
    /// bookmarks. It took them until September 29, 2026, and the words said
    /// so; now the words say they stay.
    func testClearingKeepsBookmarksTakesTheRestAndSaysSo() async throws {
        let (workspace, preferences) = try makeWorkspace()
        let model = SettingsModel(workspace: workspace, preferences: preferences)
        let store = workspace.dataStore
        XCTAssertNotNil(store.addBookmark(title: "Bread", url: "https://example.com/bread", folderID: nil))
        store.recordVisit(title: "Soup", url: "https://example.com/soup")
        workspace.addTab(url: URL(string: "https://example.com/cake"))
        model.savesHistory = false

        await model.clearBrowsingData()

        XCTAssertEqual(store.bookmarks.map(\.title), ["Bread"], "the reset took a bookmark")
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertEqual(workspace.tabs.count, 1)
        XCTAssertFalse(store.savesHistory, "a setting was reset along with the data")
        XCTAssertTrue(SettingsWording.clearFooter.contains("Your bookmarks and settings stay."))
        XCTAssertFalse(SettingsWording.clearFooter.contains("history, bookmarks"), "the list of what goes still names bookmarks")
        XCTAssertTrue(SettingsWording.clearMessage.contains("Your bookmarks and settings stay."))
        XCTAssertTrue(SettingsWording.clearFooter.contains("closes the assistant"))
        XCTAssertTrue(SettingsWording.clearFooter.contains("the icons of sites you have not bookmarked"))
    }

    // MARK: - About

    /// The maker's site opens in a tab of its own, through the same door as
    /// any other page, which moves the assistant out of its way.
    func testTheMakersSiteOpensInANewTab() throws {
        let (workspace, preferences) = try makeWorkspace()
        let model = SettingsModel(workspace: workspace, preferences: preferences)
        let before = workspace.tabs.count

        model.openMakersSite()

        XCTAssertEqual(workspace.tabs.count, before + 1)
        XCTAssertEqual(workspace.selectedTab?.session.webView.url?.host(), "zincoo.com")
    }

    /// The version is the app's own, read from its bundle.
    func testTheVersionIsTheBundlesOwn() {
        let version = SettingsWording.version()
        XCTAssertTrue(version.hasPrefix("Version "), version)
        XCTAssertFalse(version.contains("?"))
    }
}
