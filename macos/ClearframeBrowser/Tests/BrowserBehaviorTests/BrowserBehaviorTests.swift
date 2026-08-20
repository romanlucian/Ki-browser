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

    /// Analyze page is enabled and prominent on a brand-new tab. Extraction of
    /// the start surface succeeds, so the identity check downstream used to
    /// fail and abandon the work while the panel still said "Reading the
    /// visible page…", with no timeout and no way back.
    func testAnalyzingATabWithNoWebPageRefusesInsteadOfLoadingForever() async {
        let session = ControlledAssistantSession(page: Self.page, waitsForExtraction: false)
        session.currentURLString = ""
        let model = PageAssistantModel()

        await model.analyzeCurrentPage(session: session)

        XCTAssertEqual(model.state, .needsPage)
        XCTAssertNil(model.analysis)
        XCTAssertNil(model.snapshot)
    }

    func testAnalyzingRecoversOnceTheTabHoldsARealPage() async {
        let session = ControlledAssistantSession(page: Self.page, waitsForExtraction: false)
        session.currentURLString = ""
        let model = PageAssistantModel()
        await model.analyzeCurrentPage(session: session)
        XCTAssertEqual(model.state, .needsPage)

        session.currentURLString = Self.page.url
        await model.analyzeCurrentPage(session: session)

        XCTAssertEqual(model.state, .ready)
        XCTAssertEqual(model.analysis?.mode, .local)
    }

    /// The page moving out from under a read is the other way the panel could
    /// be abandoned mid-load. It has to settle on something the reader can act
    /// on, never on a spinner.
    func testAPageThatMovesDuringAnalysisSettlesOnAStateTheReaderCanActOn() async {
        let session = ControlledAssistantSession(page: Self.page)
        let model = PageAssistantModel()

        let analysisTask = Task { await model.analyzeCurrentPage(session: session) }
        while !session.isWaitingForExtraction { await Task.yield() }
        session.currentURLString = "https://second.example/other-article"
        session.completeExtraction()
        await analysisTask.value

        XCTAssertEqual(model.state, .failed(PageAssistantModel.pageChangedMessage))
        XCTAssertNil(model.analysis)
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

    /// `window.open()` hands over a configuration; the popup's tab has to build
    /// its web view from that exact configuration, or `window.opener` is null
    /// in the new tab and a popup sign-in can never report back.
    func testAPopupSessionAdoptsWebKitsConfigurationAndLeavesTheFirstNavigationToIt() throws {
        let suiteName = "clearframe.popup.adoption.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let openerConfiguration = WKWebViewConfiguration()
        openerConfiguration.applicationNameForUserAgent = "AdoptedPopupProbe"
        let popup = BrowserSession(
            downloadCenter: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults),
            adoptingPopupConfiguration: openerConfiguration
        )
        defer { popup.teardown() }

        XCTAssertEqual(popup.webView.configuration.applicationNameForUserAgent, "AdoptedPopupProbe")
        // Nothing is loaded into a popup here: WebKit owns its first
        // navigation, and loading the start document would throw it away.
        XCTAssertEqual(popup.loadState, .startPage)
        XCTAssertTrue(popup.currentURLString.isEmpty)

        let ordinary = BrowserSession(
            downloadCenter: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults)
        )
        defer { ordinary.teardown() }
        XCTAssertEqual(
            ordinary.webView.configuration.applicationNameForUserAgent,
            BrowserUserAgent.applicationName
        )
    }

    func testAPopupRequestOpensATabThatAdoptsTheReturnedWebView() throws {
        let suiteName = "clearframe.popup.tab.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let blocking = try Self.makeTestContentBlocking(defaults: defaults)
        defer { blocking.removeStore() }
        let workspace = BrowserWorkspace(
            dataStore: BrowserDataStore(defaults: defaults),
            downloads: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking.provider
        )
        let opener = try XCTUnwrap(workspace.selectedTab)

        let popupWebView = opener.session.onRequestPopupWebView?(WKWebViewConfiguration())

        XCTAssertEqual(workspace.tabs.count, 2)
        let popupTab = try XCTUnwrap(workspace.tabs.last)
        XCTAssertTrue(popupWebView === popupTab.session.webView, "WebKit was handed a web view no tab owns")
        XCTAssertEqual(workspace.selectedTabID, popupTab.id)
        // A popup inherits the opener's private/normal session.
        XCTAssertFalse(popupTab.isPrivate)
    }

    /// A popup with no address of its own — `const w = window.open()` — is an
    /// ordinary pattern. It used to open nothing at all, with no feedback.
    func testAPopupWithNoAddressYetStillOpensATab() throws {
        let suiteName = "clearframe.popup.blank.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let blocking = try Self.makeTestContentBlocking(defaults: defaults)
        defer { blocking.removeStore() }
        let workspace = BrowserWorkspace(
            dataStore: BrowserDataStore(defaults: defaults),
            downloads: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking.provider
        )
        let opener = try XCTUnwrap(workspace.selectedTab)

        opener.session.onRequestNewTab?(nil)

        XCTAssertEqual(workspace.tabs.count, 2)
        XCTAssertEqual(workspace.selectedTab?.session.loadState, .startPage)
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
        // The reset under test erases captured site icons from disk. Without a
        // directory of its own the workspace builds a `FaviconStore` pointing at
        // the real profile, and running this test deleted whatever icons the
        // person running it had collected. Every other store here is already
        // isolated; this one has to be too.
        let iconDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clearframe.favicons.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: iconDirectory) }
        let workspace = BrowserWorkspace(
            dataStore: store,
            downloads: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking.provider,
            favicons: FaviconStore(directory: iconDirectory, fetch: Self.forbiddenFaviconFetcher)
        )
        _ = store.addBookmark(title: "Saved", url: "https://example.com/saved", folderID: nil)
        store.recordVisit(title: "Visited", url: "https://example.com/visited")
        workspace.addTab(url: URL(string: "https://example.com/open"))
        workspace.persistNow()
        await blocking.provider.setSiteDisabled(true, forHost: "example.com")
        XCTAssertEqual(blocking.provider.settings.disabledHosts, ["example.com"])

        await workspace.resetLocalBrowsingData()

        // The icons it erased were the ones it was given. Asserting this is
        // what keeps the reset pointed at a directory the test owns rather
        // than at whatever profile happens to be on the machine running it.
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: iconDirectory.path),
            "the reset must erase the icon directory it was handed"
        )
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

    /// Evidence Mode finds a key point by searching the live page for that exact text.
    /// Real pages put reading text outside article prose - a Hacker News title lives in
    /// a span inside a td - and the matcher used to search only h1-h3, p, li and
    /// blockquote, so it found nothing there even when the sentence was verbatim.
    @MainActor
    func testEvidenceScriptFindsTitleInsideTableSpanAndToleratesTrailingStop() async throws {
        let html = """
        <html><body style="margin:0">
          <table width="100%"><tr>
            <td class="title" style="display:block;width:600px;height:40px">
              <span class="titleline"><a href="https://example.com">A tale of two compilers</a></span>
            </td>
          </tr></table>
          <p style="width:600px;height:40px">Ordinary prose that already matched before this change.</p>
        </body></html>
        """
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 900, height: 600))
        try await Self.loadForEvidence(html, into: webView)

        let prose = try XCTUnwrap(
            BrowserSession.evidenceScript(for: "Ordinary prose that already matched before this change.")
        )
        let foundProse = try await Self.runEvidence(prose, in: webView)
        XCTAssertTrue(foundProse, "a paragraph must still match - this guards the widened selector")

        let inSpan = try XCTUnwrap(BrowserSession.evidenceScript(for: "A tale of two compilers"))
        let foundInSpan = try await Self.runEvidence(inSpan, in: webView)
        XCTAssertTrue(foundInSpan, "a title inside a span in a td must be findable")

        let withStop = try XCTUnwrap(BrowserSession.evidenceScript(for: "A tale of two compilers."))
        let foundWithStop = try await Self.runEvidence(withStop, in: webView)
        XCTAssertTrue(foundWithStop, "a trailing stop the page does not have must not block a match")
    }

    /// Stripping a trailing stop must never turn a miss into a confident wrong
    /// highlight. "The senator denied the report." is not on a page that says "denied
    /// the reporters access", and claiming otherwise would put words in the page's
    /// mouth under a label that says this is extracted page text.
    @MainActor
    func testEvidenceScriptRefusesAMidWordMatchAndAnOversizedContainer() async throws {
        let html = """
        <html><body style="margin:0"><div id="page-root">
          <p style="width:600px;height:40px">The senator denied the reporters access to the hearing room.</p>
          <span style="display:block;width:600px;height:40px">First half of a split sentence</span>
          <span style="display:block;width:600px;height:40px">and the second half of it.</span>
        </div></body></html>
        """
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 900, height: 600))
        try await Self.loadForEvidence(html, into: webView)

        let midWord = try XCTUnwrap(BrowserSession.evidenceScript(for: "The senator denied the report."))
        let foundMidWord = try await Self.runEvidence(midWord, in: webView)
        XCTAssertFalse(foundMidWord, "a match inside a longer word must not count as evidence")

        let spanning = try XCTUnwrap(
            BrowserSession.evidenceScript(for: "First half of a split sentence and the second half of it.")
        )
        let foundSpanning = try await Self.runEvidence(spanning, in: webView)
        XCTAssertFalse(foundSpanning, "a sentence spanning two elements must miss, not outline their wrapper")
    }

    @MainActor
    private static func loadForEvidence(_ html: String, into webView: WKWebView) async throws {
        webView.loadHTMLString(html, baseURL: URL(string: "https://example.test/"))
        for _ in 0..<120 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            // innerText and getBoundingClientRect both need layout, and an offscreen
            // web view lays out asynchronously. Wait for a real element to have a box,
            // not just for readyState.
            let ready = try? await webView.evaluateJavaScript(
                "document.readyState === 'complete' && [...document.querySelectorAll('p,span,td')].length > 0 && [...document.querySelectorAll('p,span,td')].every(e => e.getBoundingClientRect().height > 0)"
            )
            if (ready as? Bool) == true { return }
        }
        throw NSError(domain: "BrowserBehaviorTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "test page never finished laying out"
        ])
    }

    @MainActor
    private static func runEvidence(_ script: String, in webView: WKWebView) async throws -> Bool {
        let value = try await webView.evaluateJavaScript(script)
        return (value as? Bool) ?? false
    }

    func testShieldStateMapsProviderStatusAndPerSiteExceptionForAllFiveStates() {
        XCTAssertEqual(ShieldState.make(status: .active(ruleCount: 2), hostDisabled: false), .activeForSite)
        XCTAssertEqual(ShieldState.activeForSite.statusLine, "On for this site")
        XCTAssertEqual(ShieldState.activeForSite.symbolName, "shield")

        // While the rule list is still compiling it is attached to nothing, so
        // the shield must not claim the site is protected.
        XCTAssertEqual(ShieldState.make(status: .compiling, hostDisabled: false), .preparing)
        XCTAssertNotEqual(ShieldState.make(status: .compiling, hostDisabled: false), .activeForSite)
        XCTAssertEqual(ShieldState.preparing.statusLine, "Not blocking yet")
        XCTAssertEqual(ShieldState.preparing.symbolName, "shield.slash")

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

    func testConnectionSecurityReadsWebKitsSecureContentReportAndNotJustTheScheme() {
        // The bug this exists for: an HTTPS page pulling part of itself over
        // HTTP used to show a full green lock, because only the scheme was read.
        XCTAssertEqual(
            ConnectionSecurity.make(
                urlString: "https://example.com/article",
                hasOnlySecureContent: true,
                hasCommittedNavigation: true
            ),
            .secure
        )
        XCTAssertEqual(
            ConnectionSecurity.make(
                urlString: "https://example.com/article",
                hasOnlySecureContent: false,
                hasCommittedNavigation: true
            ),
            .mixedContent
        )
        XCTAssertEqual(
            ConnectionSecurity.mixedContent.statusLine,
            "Parts of this page were loaded over an unencrypted connection"
        )
        XCTAssertNotEqual(ConnectionSecurity.mixedContent.symbolName, ConnectionSecurity.secure.symbolName)

        // Plain HTTP is never secure, whatever WebKit says about subresources.
        for onlySecure in [true, false] {
            XCTAssertEqual(
                ConnectionSecurity.make(
                    urlString: "http://example.com/",
                    hasOnlySecureContent: onlySecure,
                    hasCommittedNavigation: true
                ),
                .notSecure
            )
        }

        // Before the navigation commits, `hasOnlySecureContent` still describes
        // the document being replaced, so there is nothing truthful to say yet.
        XCTAssertEqual(
            ConnectionSecurity.make(
                urlString: "https://example.com/",
                hasOnlySecureContent: false,
                hasCommittedNavigation: false
            ),
            .checking
        )

        // A Clearframe surface is not a website.
        XCTAssertEqual(
            ConnectionSecurity.make(urlString: "", hasOnlySecureContent: true, hasCommittedNavigation: true),
            .noPage
        )
        XCTAssertEqual(
            ConnectionSecurity.make(urlString: "about:blank", hasOnlySecureContent: true, hasCommittedNavigation: true),
            .noPage
        )

        for state: ConnectionSecurity in [.noPage, .checking, .secure, .mixedContent, .notSecure] {
            XCTAssertFalse(state.statusLine.isEmpty)
            XCTAssertFalse(state.detail.isEmpty)
            XCTAssertFalse(state.symbolName.isEmpty)
        }
    }

    func testSiteDataKindsNameEveryWebKitTypeInPlainWordsAndDegradeForUnknownOnes() {
        XCTAssertEqual(SiteDataKind.kind(forDataType: WKWebsiteDataTypeCookies), .cookies)
        XCTAssertEqual(SiteDataKind.kind(forDataType: WKWebsiteDataTypeDiskCache), .cachedFiles)
        XCTAssertEqual(SiteDataKind.kind(forDataType: WKWebsiteDataTypeMemoryCache), .cachedFiles)
        XCTAssertEqual(SiteDataKind.kind(forDataType: WKWebsiteDataTypeFetchCache), .cachedFiles)
        XCTAssertEqual(SiteDataKind.kind(forDataType: WKWebsiteDataTypeLocalStorage), .localStorage)
        XCTAssertEqual(SiteDataKind.kind(forDataType: WKWebsiteDataTypeSessionStorage), .localStorage)
        XCTAssertEqual(SiteDataKind.kind(forDataType: WKWebsiteDataTypeIndexedDBDatabases), .databases)
        XCTAssertEqual(SiteDataKind.kind(forDataType: WKWebsiteDataTypeWebSQLDatabases), .databases)
        XCTAssertEqual(SiteDataKind.kind(forDataType: WKWebsiteDataTypeServiceWorkerRegistrations), .serviceWorkers)
        XCTAssertEqual(SiteDataKind.kind(forDataType: WKWebsiteDataTypeFileSystem), .storedFiles)
        XCTAssertEqual(SiteDataKind.kind(forDataType: WKWebsiteDataTypeMediaKeys), .mediaKeys)
        XCTAssertEqual(SiteDataKind.kind(forDataType: WKWebsiteDataTypeSearchFieldRecentSearches), .recentSearches)
        XCTAssertEqual(SiteDataKind.kind(forDataType: WKWebsiteDataTypeHashSalt), .deviceIdentifiers)
        XCTAssertEqual(SiteDataKind.kind(forDataType: "WKWebsiteDataTypeScreenTime"), .screenTime)

        // A constant a future macOS adds must degrade to words, not crash and
        // not leak WebKit's identifier into the interface.
        XCTAssertEqual(SiteDataKind.kind(forDataType: "WKWebsiteDataTypeSomethingNotInventedYet"), .other)
        XCTAssertEqual(SiteDataKind.kind(forDataType: ""), .other)
        XCTAssertEqual(SiteDataKind.other.label, "other site data")

        for kind in SiteDataKind.allCases {
            XCTAssertFalse(kind.label.isEmpty)
            XCTAssertFalse(
                kind.label.contains("WKWebsiteData"),
                "\(kind) leaked a WebKit identifier into user-facing text"
            )
        }

        // Whatever this Mac's WebKit actually offers is covered by words too.
        for rawValue in WKWebsiteDataStore.allWebsiteDataTypes() {
            let label = SiteDataKind.kind(forDataType: rawValue).label
            XCTAssertFalse(label.contains("WKWebsiteData"), "\(rawValue) had no plain-words name")
        }
    }

    func testSiteDataKindsCollapseRepeatedGroupsAndReadAsOneOrderedLine() {
        let kinds = SiteDataKind.kinds(for: [
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeFetchCache,
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeLocalStorage
        ])
        XCTAssertEqual(kinds, [.cookies, .cachedFiles, .localStorage], "three caches are one everyday idea")
        XCTAssertEqual(SiteDataKind.summary(of: kinds), "Cookies, cached files, local storage")
        XCTAssertEqual(SiteDataKind.summary(of: []), "Site data")

        // Nothing anywhere in this vocabulary is a size or a count: WebKit
        // reports neither, so neither can appear.
        let everyLabel = SiteDataKind.allCases.map(\.label).joined(separator: " ")
        XCTAssertFalse(everyLabel.contains(where: \.isNumber))
    }

    func testSiteDataRemovalMatchesTheRegistrableDomainWebKitReportsForASite() {
        // WebKit names a record by its registrable domain, so a page on
        // `www.example.com` must still find and remove the `example.com` record.
        XCTAssertTrue(SiteDataInventory.matches(displayName: "example.com", host: "example.com"))
        XCTAssertTrue(SiteDataInventory.matches(displayName: "example.com", host: "www.example.com"))
        XCTAssertTrue(SiteDataInventory.matches(displayName: "example.com", host: "shop.eu.example.com"))
        XCTAssertTrue(SiteDataInventory.matches(displayName: "EXAMPLE.com", host: "www.Example.COM"))

        XCTAssertFalse(SiteDataInventory.matches(displayName: "example.com", host: "example.org"))
        XCTAssertFalse(
            SiteDataInventory.matches(displayName: "example.com", host: "notexample.com"),
            "a shared suffix is not the same site"
        )
        XCTAssertFalse(SiteDataInventory.matches(displayName: "", host: "example.com"))
        XCTAssertFalse(SiteDataInventory.matches(displayName: "example.com", host: ""))
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

    // MARK: - Wave 1 browser basics

    func testClosingATabRecordsItSoItCanBeReopenedWhereItWas() throws {
        let workspace = try makeSurfaceTestWorkspace()
        workspace.addTab(url: URL(string: "https://example.com/one"))
        workspace.addTab(url: URL(string: "https://example.com/two"))
        workspace.addTab(url: URL(string: "https://example.com/three"))
        let middle = try XCTUnwrap(workspace.tabs.first { $0.session.currentURLString.contains("two") })
        let middleIndex = try XCTUnwrap(workspace.tabs.firstIndex(where: { $0.id == middle.id }))

        XCTAssertFalse(workspace.canReopenClosedTab, "nothing has been closed yet")
        workspace.closeTab(middle.id)

        XCTAssertTrue(workspace.canReopenClosedTab)
        workspace.reopenClosedTab()

        let restored = try XCTUnwrap(workspace.tabs.firstIndex { $0.session.currentURLString.contains("two") })
        XCTAssertEqual(restored, middleIndex, "the tab comes back where it was, not at the end")
        XCTAssertFalse(workspace.canReopenClosedTab, "reopening consumes the record")
    }

    func testAClosedPrivateTabIsNeverRecorded() throws {
        let workspace = try makeSurfaceTestWorkspace()
        workspace.addTab(url: URL(string: "https://example.com/regular"))
        workspace.addTab(url: URL(string: "https://example.com/secret"), isPrivate: true)
        let priv = try XCTUnwrap(workspace.tabs.first { $0.isPrivate })

        workspace.closeTab(priv.id)

        XCTAssertFalse(
            workspace.canReopenClosedTab,
            "a private tab leaves no trace anywhere else and must leave none here"
        )
    }

    func testTheClosedTabListStopsAtTenSoItCannotGrowForever() throws {
        let workspace = try makeSurfaceTestWorkspace()
        for index in 0..<14 {
            workspace.addTab(url: URL(string: "https://example.com/page\(index)"))
        }
        let closable = workspace.tabs.filter { !$0.session.currentURLString.isEmpty }.map(\.id)
        for id in closable.prefix(13) { workspace.closeTab(id) }

        XCTAssertEqual(workspace.closedTabs.count, 10)
        XCTAssertTrue(
            workspace.closedTabs.first?.url.contains("page") ?? false,
            "the most recently closed tab is first"
        )
    }

    func testReopeningRejoinsTheGroupWhenItStillExists() throws {
        let workspace = try makeSurfaceTestWorkspace()
        workspace.addTab(url: URL(string: "https://example.com/grouped"))
        let tab = try XCTUnwrap(workspace.tabs.first { $0.session.currentURLString.contains("grouped") })
        workspace.addTab(url: URL(string: "https://example.com/other"))
        let other = try XCTUnwrap(workspace.tabs.first { $0.session.currentURLString.contains("other") })
        workspace.createGroup(withTabs: [tab.id, other.id])
        let groupID = try XCTUnwrap(tab.groupID)

        workspace.closeTab(tab.id)
        workspace.reopenClosedTab()

        let restored = try XCTUnwrap(workspace.tabs.first { $0.session.currentURLString.contains("grouped") })
        XCTAssertEqual(restored.groupID, groupID, "the tab returns to the group it came from")
    }

    func testCommandNineSelectsTheLastTabAndNotTheNinth() throws {
        let workspace = try makeSurfaceTestWorkspace()
        for index in 0..<4 {
            workspace.addTab(url: URL(string: "https://example.com/tab\(index)"))
        }
        let last = try XCTUnwrap(workspace.tabs.last)

        workspace.selectTab(atOrdinal: 9)
        XCTAssertEqual(workspace.selectedTabID, last.id, "Command-9 means last, as it does in Safari")

        workspace.selectTab(atOrdinal: 2)
        XCTAssertEqual(workspace.selectedTabID, workspace.tabs[1].id, "Command-2 means the second tab")

        let previous = workspace.selectedTabID
        workspace.selectTab(atOrdinal: 8)
        XCTAssertEqual(workspace.selectedTabID, previous, "an ordinal past the end changes nothing")
    }

    func testSelectingAnOrdinalOpensACollapsedGroupSoTheTabIsVisible() throws {
        let workspace = try makeSurfaceTestWorkspace()
        workspace.addTab(url: URL(string: "https://example.com/inside"))
        let inside = try XCTUnwrap(workspace.tabs.first { $0.session.currentURLString.contains("inside") })
        workspace.addTab(url: URL(string: "https://example.com/outside"))
        workspace.createGroup(withTabs: [inside.id])
        let groupID = try XCTUnwrap(inside.groupID)
        workspace.selectTab(try XCTUnwrap(workspace.tabs.first { $0.groupID == nil }).id)
        workspace.toggleCollapse(groupID: groupID)
        XCTAssertEqual(workspace.group(groupID)?.isCollapsed, true)

        let ordinal = try XCTUnwrap(workspace.tabs.firstIndex(where: { $0.id == inside.id })) + 1
        workspace.selectTab(atOrdinal: ordinal)

        XCTAssertEqual(workspace.selectedTabID, inside.id)
        XCTAssertEqual(workspace.group(groupID)?.isCollapsed, false, "a hidden tab cannot be the active one")
    }

    func testDuplicatingATabPlacesTheCopyBesideItAndKeepsItsGroup() throws {
        let workspace = try makeSurfaceTestWorkspace()
        workspace.addTab(url: URL(string: "https://example.com/original"))
        let original = try XCTUnwrap(workspace.tabs.first { $0.session.currentURLString.contains("original") })
        workspace.createGroup(withTabs: [original.id])
        let originalIndex = try XCTUnwrap(workspace.tabs.firstIndex(where: { $0.id == original.id }))
        let countBefore = workspace.tabs.count

        workspace.duplicateTab(original.id)

        XCTAssertEqual(workspace.tabs.count, countBefore + 1)
        let copy = workspace.tabs[originalIndex + 1]
        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.groupID, original.groupID, "the copy stays in the same group")
        XCTAssertEqual(workspace.selectedTabID, copy.id, "the copy takes focus")
    }

    func testWebFeatureSettingsPersistAcrossStoreInstances() throws {
        let suiteName = "clearframe.webfeatures.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }

        let store = WebFeatureSettingsStore(defaults: defaults)
        XCTAssertTrue(store.upgradesToHTTPS, "HTTPS upgrading is on unless turned off")
        XCTAssertFalse(store.showsDeveloperFeatures, "the inspector stays off until asked for")

        store.setUpgradesToHTTPS(false)
        store.setShowsDeveloperFeatures(true)

        let reopened = WebFeatureSettingsStore(defaults: defaults)
        XCTAssertFalse(reopened.upgradesToHTTPS)
        XCTAssertTrue(reopened.showsDeveloperFeatures)
    }

    // MARK: - Pinned tabs and reordering

    private func pinnedLayout(of workspace: BrowserWorkspace) -> String {
        workspace.tabs.map { $0.isPinned ? "P" : "u" }.joined()
    }

    func testPinningMovesATabAheadOfEveryUnpinnedTab() throws {
        let workspace = try makeSurfaceTestWorkspace()
        for index in 0..<3 { workspace.addTab(url: URL(string: "https://example.com/\(index)")) }
        let last = try XCTUnwrap(workspace.tabs.last)

        workspace.pinTab(last.id)

        XCTAssertTrue(last.isPinned)
        XCTAssertEqual(workspace.tabs.first?.id, last.id, "a pinned tab moves to the front")
        XCTAssertEqual(pinnedLayout(of: workspace), "Puuu")
    }

    func testUnpinningReturnsTheTabAfterTheOnesStillPinned() throws {
        let workspace = try makeSurfaceTestWorkspace()
        for index in 0..<3 { workspace.addTab(url: URL(string: "https://example.com/\(index)")) }
        let a = try XCTUnwrap(workspace.tabs.last)
        let b = try XCTUnwrap(workspace.tabs.dropLast().last)
        workspace.pinTab(a.id)
        workspace.pinTab(b.id)
        XCTAssertEqual(pinnedLayout(of: workspace), "PPuu")

        workspace.unpinTab(a.id)

        XCTAssertEqual(pinnedLayout(of: workspace), "Puuu", "the unpinned tab lands after the pinned run")
        XCTAssertEqual(workspace.tabs.first?.id, b.id)
    }

    func testPinningAGroupedTabLeavesTheGroupAndKeepsItContiguous() throws {
        let workspace = try makeSurfaceTestWorkspace()
        for index in 0..<4 { workspace.addTab(url: URL(string: "https://example.com/\(index)")) }
        let members = Array(workspace.tabs.suffix(3))
        workspace.createGroup(withTabs: members.map(\.id))
        let groupID = try XCTUnwrap(members.first?.groupID)
        let middle = members[1]

        workspace.pinTab(middle.id)

        XCTAssertNil(middle.groupID, "pinning takes a tab out of its group")
        XCTAssertTrue(middle.isPinned)
        let groupPositions = workspace.tabs.enumerated()
            .filter { $0.element.groupID == groupID }
            .map(\.offset)
        XCTAssertEqual(
            groupPositions, Array(groupPositions.first!...groupPositions.last!),
            "the group the tab left is still one unbroken run"
        )
    }

    func testClosingOtherTabsKeepsThePinnedOnes() throws {
        let workspace = try makeSurfaceTestWorkspace()
        for index in 0..<4 { workspace.addTab(url: URL(string: "https://example.com/\(index)")) }
        let pinned = try XCTUnwrap(workspace.tabs.last)
        workspace.pinTab(pinned.id)
        let keep = try XCTUnwrap(workspace.tabs.last(where: { !$0.isPinned }))

        workspace.closeOtherTabs(keeping: keep.id)

        XCTAssertTrue(
            workspace.tabs.contains { $0.id == pinned.id },
            "closing other tabs must not close a pinned one — that is what pinning is for"
        )
        XCTAssertTrue(workspace.tabs.contains { $0.id == keep.id })
    }

    func testAPinnedTabCannotBeDraggedIntoTheUnpinnedRun() throws {
        let workspace = try makeSurfaceTestWorkspace()
        for index in 0..<4 { workspace.addTab(url: URL(string: "https://example.com/\(index)")) }
        let pinned = try XCTUnwrap(workspace.tabs.last)
        workspace.pinTab(pinned.id)
        XCTAssertEqual(pinnedLayout(of: workspace), "Puuuu")

        workspace.moveTab(pinned.id, toIndex: 4)

        XCTAssertEqual(workspace.tabs.first?.id, pinned.id, "it stays in the pinned run")
        XCTAssertEqual(pinnedLayout(of: workspace), "Puuuu")
    }

    func testAnUnpinnedTabCannotBeDraggedAmongThePinnedOnes() throws {
        let workspace = try makeSurfaceTestWorkspace()
        for index in 0..<4 { workspace.addTab(url: URL(string: "https://example.com/\(index)")) }
        let first = try XCTUnwrap(workspace.tabs.first)
        let second = try XCTUnwrap(workspace.tabs.dropFirst().first)
        workspace.pinTab(first.id)
        workspace.pinTab(second.id)
        XCTAssertEqual(pinnedLayout(of: workspace), "PPuuu")
        let loose = try XCTUnwrap(workspace.tabs.last)

        workspace.moveTab(loose.id, toIndex: 0)

        XCTAssertEqual(pinnedLayout(of: workspace), "PPuuu", "the pinned run is not breached")
        XCTAssertTrue(workspace.tabs[0].isPinned && workspace.tabs[1].isPinned)
        XCTAssertEqual(workspace.tabs[2].id, loose.id, "it lands at the head of the unpinned run instead")
    }

    func testDroppingATabIntoAGroupDoesNotSplitThatGroup() throws {
        let workspace = try makeSurfaceTestWorkspace()
        for index in 0..<5 { workspace.addTab(url: URL(string: "https://example.com/\(index)")) }
        let members = Array(workspace.tabs.suffix(3))
        workspace.createGroup(withTabs: members.map(\.id))
        let groupID = try XCTUnwrap(members.first?.groupID)
        let outsider = try XCTUnwrap(workspace.tabs.first(where: { $0.groupID == nil }))
        let middleOfGroup = try XCTUnwrap(workspace.tabs.firstIndex(where: { $0.id == members[1].id }))

        workspace.moveTab(outsider.id, toIndex: middleOfGroup)

        let positions = workspace.tabs.enumerated()
            .filter { $0.element.groupID == groupID }
            .map(\.offset)
        XCTAssertFalse(positions.isEmpty)
        XCTAssertEqual(
            positions, Array(positions.first!...positions.last!),
            "a drop inside a group must never leave that group in two pieces"
        )
    }

    func testReorderingDoesNotChangeWhichTabIsSelected() throws {
        let workspace = try makeSurfaceTestWorkspace()
        for index in 0..<4 { workspace.addTab(url: URL(string: "https://example.com/\(index)")) }
        let selected = try XCTUnwrap(workspace.selectedTabID)
        let mover = try XCTUnwrap(workspace.tabs.first)

        workspace.moveTab(mover.id, toIndex: workspace.tabs.count - 1)

        XCTAssertEqual(workspace.selectedTabID, selected, "a reorder is not a selection change")
    }

    func testASavedSessionRestoresPinnedTabsAndTheirOrder() throws {
        let suiteName = "clearframe.pinned.restore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let store = BrowserDataStore(defaults: defaults)
        let pinned = BrowserTabRecord(
            id: UUID(), url: "https://example.com/pinned", title: "Pinned",
            lastActivatedAt: Date(), isPinned: true
        )
        let loose = BrowserTabRecord(
            id: UUID(), url: "https://example.com/loose", title: "Loose",
            lastActivatedAt: Date()
        )
        store.saveWorkspace(BrowserWorkspaceSnapshot(tabs: [pinned, loose], selectedTabID: loose.id))

        let restored = try XCTUnwrap(store.loadWorkspace())

        XCTAssertEqual(restored.tabs.first?.isPinned, true)
        XCTAssertEqual(restored.tabs.last?.isPinned, false)
    }

    func testASessionSavedBeforePinningExistedStillRestoresUnpinned() throws {
        let legacy = """
        {"tabs":[{"id":"\(UUID().uuidString)","url":"https://example.com/old",        "title":"Old","lastActivatedAt":760000000}],"selectedTabID":null}
        """
        let snapshot = try JSONDecoder().decode(
            BrowserWorkspaceSnapshot.self,
            from: try XCTUnwrap(legacy.data(using: .utf8))
        )

        XCTAssertEqual(snapshot.tabs.count, 1)
        XCTAssertEqual(
            snapshot.tabs.first?.isPinned, false,
            "a session saved before pinning existed restores exactly as it did then"
        )
    }

    func testPinnedTabsAreReservedAtAFixedWidthBeforeTheRestShare() throws {
        // 500 points across three tabs leaves them short of the 200-point cap,
        // so the reservation genuinely changes the share. At a comfortable
        // width both cases would simply hit the cap and prove nothing.
        let twoPinned = 2 * TabStripMetrics.pinnedTabWidth + 2 * TabStripMetrics.spacing
        let withPins = TabStripMetrics.resolve(
            availableWidth: 500, tabCount: 3, hasSelectedTab: true, reservedWidth: twoPinned
        )
        let withoutPins = TabStripMetrics.resolve(
            availableWidth: 500, tabCount: 3, hasSelectedTab: true
        )
        XCTAssertLessThan(
            withPins.unselectedTabWidth, withoutPins.unselectedTabWidth,
            "pinned tabs take their width off the top, leaving less for the rest"
        )
    }

    func testAStripOfOnlyPinnedTabsResolvesWithoutDividingByZero() throws {
        let resolution = TabStripMetrics.resolve(
            availableWidth: 400,
            tabCount: 0,
            hasSelectedTab: false,
            reservedWidth: 3 * TabStripMetrics.pinnedTabWidth
        )
        XCTAssertFalse(resolution.scrolls, "three pinned tabs fit in 400 points")
        XCTAssertGreaterThan(resolution.contentWidth, 0)
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
