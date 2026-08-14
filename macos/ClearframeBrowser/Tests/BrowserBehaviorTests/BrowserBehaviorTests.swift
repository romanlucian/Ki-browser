import ClearframeCore
import Foundation
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
        let workspace = BrowserWorkspace(
            dataStore: store,
            downloads: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults)
        )

        workspace.addTab(isPrivate: true)
        let privateTab = try XCTUnwrap(workspace.selectedTab)
        XCTAssertTrue(privateTab.isPrivate)
        XCTAssertFalse(privateTab.session.webView.configuration.websiteDataStore.isPersistent)
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
        let workspace = BrowserWorkspace(
            dataStore: store,
            downloads: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults)
        )
        _ = store.addBookmark(title: "Saved", url: "https://example.com/saved", folderID: nil)
        store.recordVisit(title: "Visited", url: "https://example.com/visited")
        workspace.addTab(url: URL(string: "https://example.com/open"))
        workspace.persistNow()

        await workspace.resetLocalBrowsingData()

        XCTAssertTrue(store.bookmarks.isEmpty)
        XCTAssertTrue(store.bookmarkFolders.isEmpty)
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertNil(store.loadWorkspace())
        XCTAssertEqual(workspace.tabs.count, 1)
        XCTAssertFalse(try XCTUnwrap(workspace.selectedTab).isPrivate)
        XCTAssertEqual(workspace.selectedTab?.session.currentURLString, "")
        XCTAssertEqual(workspace.selectedTab?.session.pageTitle, "New Tab")
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
