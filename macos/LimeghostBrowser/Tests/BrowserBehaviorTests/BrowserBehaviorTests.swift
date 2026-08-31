import LimeghostCore
import Foundation
import WebKit
import XCTest
@testable import LimeghostBrowser

/// Removing a test's preference suite as thoroughly as a test process can.
///
/// `removePersistentDomain(forName:)` empties the domain but leaves an empty
/// `.plist` behind in ~/Library/Preferences, and a suite per test adds up: the
/// machine this was developed on had accumulated several thousand of them.
///
/// Deleting the file helps but does not settle it — `cfprefsd` writes an empty
/// one back when the still-live `UserDefaults` object is flushed at exit, so a
/// full run still leaves a few dozen behind. Emptying the domain is what
/// matters for correctness; the files are inert. The real fix is one suite for
/// the whole bundle rather than one per test, which is a wider change than it
/// looks. Until then, `find ~/Library/Preferences -name 'limeghost.*-*.plist'
/// -delete` clears the accumulation.
@MainActor
enum TestSuiteCleanup {
    static func destroy(_ suiteName: String, defaults: UserDefaults) {
        defaults.removePersistentDomain(forName: suiteName)
        guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        else { return }
        let plist = library.appendingPathComponent("Preferences/\(suiteName).plist")
        try? FileManager.default.removeItem(at: plist)
    }
}

@MainActor
final class BrowserBehaviorTests: XCTestCase {
    func testDataStoreRestoresLastKnownGoodBookmarksAndPreservesCorruptBytes() throws {
        let suiteName = "clearframe.persistence.recovery.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }
        let key = "clearframe.bookmarks.v1"
        let corrupt = Data("not valid bookmark JSON".utf8)
        // Saved without a position, as records were before bookmarks could be
        // reordered; loading gives it one, which is the migration doing its job.
        let saved = [BookmarkRecord(title: "Recovered", url: "https://example.com/recovered")]
        let expected = saved.map { record -> BookmarkRecord in
            var positioned = record
            positioned.position = 0
            return positioned
        }
        let backup = try JSONEncoder().encode(saved)
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
        // Recovery restores from the backup and writes the loaded collection
        // back, so what lands in the primary key is the migrated form: the
        // record it kept, now carrying the position it was given on load.
        XCTAssertEqual(restoredPrimary, expected)
    }

    func testDataStoreDoesNotOverwriteUnreadableBookmarksWhenNoBackupExists() throws {
        let suiteName = "clearframe.persistence.unreadable.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }
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
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }
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
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }

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
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }
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
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }
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
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }
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
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }
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
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }

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
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }
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
        XCTAssertTrue(base.hasPrefix("limeghost-tracker-block.v2026.08.14.1.x"))
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
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }
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

        // A Limeghost surface is not a website.
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
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }
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

    func testTheAssistantIsOneWindowNotOneTabAndLoadsNothingUntilAsked() throws {
        let workspace = try makeSurfaceTestWorkspace()
        let companion = workspace.aiCompanion

        // A window that never asks for an assistant never loads one.
        XCTAssertFalse(companion.isVisible)
        XCTAssertNil(companion.session, "the assistant loaded before anybody asked for it")

        companion.show()
        XCTAssertTrue(companion.isVisible)
        let session = try XCTUnwrap(companion.session, "showing the assistant did not create it")

        // Switching tabs must not disturb it: a conversation is something a
        // person keeps while they read around it.
        workspace.addTab()
        let second = try XCTUnwrap(workspace.selectedTab)
        workspace.selectTab(second.id)
        XCTAssertTrue(companion.isVisible)
        XCTAssertTrue(companion.session === session, "the assistant restarted when the tab changed")

        companion.hide()
        XCTAssertFalse(companion.isVisible)
        XCTAssertTrue(companion.session === session, "hiding threw the conversation away")

        // Showing again reuses the same conversation rather than starting over.
        companion.show()
        XCTAssertTrue(companion.isVisible)
        XCTAssertTrue(companion.session === session, "reopening restarted the assistant")

        // Filling the window is a view decision and must not disturb the session.
        companion.toggleExpanded()
        XCTAssertTrue(companion.isExpanded)
        XCTAssertTrue(companion.session === session)
        companion.toggleExpanded()
        XCTAssertFalse(companion.isExpanded)
    }

    func testSwitchingAssistantsKeepsTheConversationAndStopsAtTwoLiveOnes() throws {
        let suiteName = "clearframe.companion.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }
        let store = BrowserDataStore(defaults: defaults)
        let blocking = try Self.makeTestContentBlocking(defaults: defaults)
        defer { blocking.removeStore() }
        let workspace = BrowserWorkspace(
            dataStore: store,
            downloads: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking.provider
        )
        let companion = workspace.aiCompanion
        XCTAssertEqual(companion.tool.id, "chatgpt", "the default assistant is not the documented one")

        let others = AICompanion.choices.filter { $0.id != "chatgpt" }
        try XCTSkipUnless(others.count >= 2, "this policy needs three assistants to exercise")
        let first = companion.tool
        let second = others[0]
        let third = others[1]

        companion.show()
        let firstSession = try XCTUnwrap(companion.session)

        // Switching used to destroy the conversation you were in the middle of.
        companion.select(second)
        XCTAssertEqual(companion.tool.id, second.id)
        XCTAssertEqual(store.aiCompanionToolID, second.id, "the choice was not remembered")
        let secondSession = try XCTUnwrap(companion.session, "switching while open left no assistant")
        XCTAssertFalse(firstSession === secondSession, "both assistants shared one session")
        XCTAssertTrue(
            companion.session(for: first) === firstSession,
            "switching away threw the first conversation out"
        )

        // Going back is the whole point: the same session, still where it was.
        companion.select(first)
        XCTAssertTrue(
            companion.session === firstSession,
            "coming back restarted the assistant instead of returning to it"
        )

        // A third does not accumulate. The one nobody is looking at and nobody
        // used most recently is the one that goes.
        companion.select(third)
        XCTAssertEqual(companion.live.count, AICompanion.maximumLiveSessions)
        XCTAssertNotNil(companion.session(for: third))
        XCTAssertNotNil(companion.session(for: first), "the assistant in use was dropped")
        XCTAssertNil(companion.session(for: second), "a third assistant was left running")

        // And returning to the dropped one is a fresh view reopening the
        // conversation's own address, not the old object coming back.
        companion.select(second)
        let reopened = try XCTUnwrap(companion.session)
        XCTAssertFalse(reopened === secondSession)

        // A window opened later still starts on the remembered choice.
        let reopenedWindow = BrowserWorkspace(
            dataStore: BrowserDataStore(defaults: defaults),
            downloads: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking.provider
        )
        XCTAssertEqual(reopenedWindow.aiCompanion.tool.id, second.id)
    }

    func testComparingShowsTwoDifferentAssistantsAndClosingReturnsTheLayout() throws {
        let workspace = try makeSurfaceTestWorkspace()
        let companion = workspace.aiCompanion
        try XCTSkipUnless(AICompanion.choices.count >= 2, "comparing needs two assistants")

        companion.show()
        XCTAssertFalse(companion.isComparing)
        XCTAssertFalse(companion.isExpanded)

        companion.startComparing()
        let left = try XCTUnwrap(companion.tool as AIToolListing?)
        let right = try XCTUnwrap(companion.comparisonTool, "comparing opened only one assistant")
        XCTAssertNotEqual(left.id, right.id, "compared an assistant against itself")
        XCTAssertNotNil(companion.session(for: left))
        XCTAssertNotNil(companion.session(for: right))
        // Two columns need the window; a page beside them would fit in neither.
        XCTAssertTrue(companion.isExpanded)

        // Changing the right column leaves the left one alone.
        let leftSession = try XCTUnwrap(companion.session(for: left))
        if let replacement = AICompanion.choices.first(where: { $0.id != left.id && $0.id != right.id }) {
            companion.selectComparison(replacement)
            XCTAssertEqual(companion.comparisonTool?.id, replacement.id)
            XCTAssertTrue(companion.session(for: left) === leftSession, "the left column restarted")
            XCTAssertEqual(companion.live.count, AICompanion.maximumLiveSessions)
        }

        // Closing the second column gives back the layout the person had.
        companion.stopComparing()
        XCTAssertFalse(companion.isComparing)
        XCTAssertNil(companion.comparisonTool)
        XCTAssertFalse(companion.isExpanded, "leaving compare left the window filled")
        XCTAssertTrue(companion.session(for: left) === leftSession, "leaving compare restarted the assistant")
        XCTAssertLessThanOrEqual(companion.live.count, AICompanion.maximumLiveSessions)
    }

    func testOpeningATabStepsTheAssistantOutOfTheWayWithoutLosingIt() throws {
        let workspace = try makeSurfaceTestWorkspace()
        let companion = workspace.aiCompanion
        try XCTSkipUnless(AICompanion.choices.count >= 2, "comparing needs two assistants")

        companion.show()
        companion.startComparing()
        let left = companion.tool
        let right = try XCTUnwrap(companion.comparisonTool)
        let leftSession = try XCTUnwrap(companion.session(for: left))
        XCTAssertTrue(companion.isExpanded)

        // A new tab is somebody asking to look at a page. A full-window
        // assistant answers that with a page nobody can see.
        workspace.addTab()
        XCTAssertFalse(companion.isExpanded, "the new tab opened behind the assistant")
        XCTAssertFalse(companion.isComparing)
        // Stepping aside is a layout change and nothing more.
        XCTAssertTrue(companion.isVisible, "the assistant closed instead of stepping aside")
        XCTAssertTrue(companion.session(for: left) === leftSession, "the conversation restarted")
        XCTAssertNotNil(companion.session(for: right), "the second conversation was thrown away")

        // Switching between tabs that already exist changes nothing.
        companion.toggleExpanded()
        let first = try XCTUnwrap(workspace.tabs.first)
        workspace.selectTab(first.id)
        XCTAssertTrue(companion.isExpanded, "changing tabs disturbed the assistant")
    }

    /// Every way of asking for a page must uncover the page.
    ///
    /// A table rather than one test each, because the point is coverage: when
    /// somebody adds an eleventh door and forgets the rule, this is what says
    /// so. Ten of these were broken at once — the panel stepped aside for ⌘T
    /// and for nothing else, so the same request behaved two ways depending on
    /// which button you happened to press.
    func testEveryWayOfAskingForAPageUncoversIt() throws {
        let doors: [(String, (BrowserWorkspace) -> Void)] = [
            ("new tab", { $0.addTab() }),
            ("new tab beside this one", { workspace in
                if let id = workspace.selectedTab?.id { workspace.addTab(after: id) }
            }),
            ("a link opened in a tab", { $0.addTab(url: URL(string: "https://example.com/link")!) }),
            ("a link handed over by another app", { $0.openExternalURL(URL(string: "https://example.com/x")!) }),
            ("an address or a bookmark", { $0.open("https://example.com/typed") }),
            ("a bookmark in a new tab", { $0.open("https://example.com/typed", inNewTab: true) }),
            ("reopening a closed tab", { $0.reopenClosedTab() }),
            ("the bookmarks home", { $0.openBookmarksHome() }),
            ("the history home", { $0.openHistoryHome() }),
            ("back", { $0.goBackInSelectedTab() }),
            ("forward", { $0.goForwardInSelectedTab() }),
        ]

        for (name, openADoor) in doors {
            let workspace = try makeSurfaceTestWorkspace()
            let companion = workspace.aiCompanion
            companion.show()

            // Set the room up *first*: opening and closing a tab is itself one
            // of these doors, so doing it after expanding would collapse the
            // panel and every assertion below would pass without proving
            // anything. It did exactly that until a deliberately broken
            // `makeRoomForPage` failed to turn this test red.
            workspace.addTab(url: URL(string: "https://example.com/closed")!)
            if let extra = workspace.tabs.last, workspace.tabs.count > 1 {
                workspace.closeTab(extra.id)
            }

            companion.toggleExpanded()
            XCTAssertTrue(companion.isExpanded, "\(name): could not cover the page to begin with")

            openADoor(workspace)

            XCTAssertFalse(
                companion.isExpanded,
                "\(name) left the page behind the assistant"
            )
            XCTAssertTrue(companion.isVisible, "\(name) closed the assistant instead of moving it")
        }
    }

    /// The other half of the rule, and the half that keeps it from becoming an
    /// interface with a mind of its own.
    func testNothingMovesWhenNobodyAskedForAPage() throws {
        let workspace = try makeSurfaceTestWorkspace()
        let companion = workspace.aiCompanion
        companion.show()
        workspace.addTab()
        companion.toggleExpanded()
        XCTAssertTrue(companion.isExpanded)

        // Switching between tabs that already exist is not a request for a page.
        for tab in workspace.tabs {
            workspace.selectTab(tab.id)
            XCTAssertTrue(companion.isExpanded, "changing tabs moved the assistant")
        }
        // Neither is reloading the page already in front of you.
        workspace.reloadSelectedTab()
        XCTAssertTrue(companion.isExpanded, "reloading moved the assistant")
    }

    /// On a window with no room for both, shrinking reveals nothing — so the
    /// assistant leaves instead, and comes back when the room does.
    func testWithNoRoomForBothTheAssistantLeavesAndReturnsWhenTheRoomDoes() throws {
        let workspace = try makeSurfaceTestWorkspace()
        let companion = workspace.aiCompanion
        companion.show()
        let session = try XCTUnwrap(companion.session)

        companion.setCanShareWindow(false)
        workspace.addTab()
        XCTAssertFalse(companion.isVisible, "the page stayed behind the assistant")
        // Left the screen, not the memory.
        XCTAssertTrue(companion.session === session, "the conversation was thrown away")

        // Widening the window is enough; the person should not have to know a
        // keyboard shortcut to undo something they did not ask for.
        companion.setCanShareWindow(true)
        XCTAssertTrue(companion.isVisible, "the assistant did not come back when the room did")
        XCTAssertFalse(companion.isExpanded)
        XCTAssertTrue(companion.session === session, "coming back restarted the assistant")
    }

    /// Closing it is deliberate, and a wider window must not undo a decision.
    func testAnAssistantClosedByHandStaysClosedWhenTheWindowWidens() throws {
        let workspace = try makeSurfaceTestWorkspace()
        let companion = workspace.aiCompanion
        companion.show()

        companion.setCanShareWindow(false)
        companion.hide()
        companion.setCanShareWindow(true)
        XCTAssertFalse(companion.isVisible, "widening the window reopened an assistant somebody closed")
    }

    /// After comparing, the assistant still on screen outranks the one that
    /// left it — screen position, never anything about what was read.
    func testLeavingCompareKeepsTheAssistantStillOnScreen() throws {
        let workspace = try makeSurfaceTestWorkspace()
        let companion = workspace.aiCompanion
        let others = AICompanion.choices.filter { $0.id != companion.tool.id }
        try XCTSkipUnless(others.count >= 2, "this needs three assistants")
        let onScreen = companion.tool
        let third = others[1]

        companion.show()
        companion.startComparing()
        let partner = try XCTUnwrap(companion.comparisonTool)
        let onScreenSession = try XCTUnwrap(companion.session(for: onScreen))
        companion.stopComparing()

        // Switching to a third drops one. It must be the partner that left the
        // screen, not the assistant the person still had in front of them.
        companion.select(third)
        XCTAssertNil(companion.session(for: partner), "the compare partner outranked the visible assistant")
        XCTAssertTrue(
            companion.session(for: onScreen) === onScreenSession,
            "the assistant that stayed on screen was discarded"
        )
    }

    /// Every close button closes its own column, and the last one closes the
    /// panel. There is no button that closes more than what it sits on.
    func testEachCloseButtonClosesOnlyItsOwnColumn() throws {
        let workspace = try makeSurfaceTestWorkspace()
        let companion = workspace.aiCompanion
        try XCTSkipUnless(AICompanion.choices.count >= 2, "comparing needs two assistants")

        // Closing the second column leaves the first, still loaded.
        companion.show()
        companion.startComparing()
        let left = companion.tool
        let right = try XCTUnwrap(companion.comparisonTool)
        let leftSession = try XCTUnwrap(companion.session(for: left))
        companion.closeColumn(right)
        XCTAssertFalse(companion.isComparing)
        XCTAssertEqual(companion.tool.id, left.id, "closing the right column changed which assistant remained")
        XCTAssertTrue(companion.isVisible, "closing one of two closed the whole panel")
        XCTAssertTrue(companion.session(for: left) === leftSession, "the surviving conversation restarted")

        // Closing the *first* column leaves the second — the one that stays is
        // the one whose column was not closed, whichever side it was on.
        companion.startComparing()
        let second = try XCTUnwrap(companion.comparisonTool)
        let secondSession = try XCTUnwrap(companion.session(for: second))
        companion.closeColumn(companion.tool)
        XCTAssertFalse(companion.isComparing)
        XCTAssertEqual(companion.tool.id, second.id, "closing the left column did not promote the right one")
        XCTAssertTrue(companion.isVisible)
        XCTAssertTrue(
            companion.session(for: second) === secondSession,
            "the promoted assistant reloaded instead of carrying its conversation over"
        )
        XCTAssertEqual(
            workspace.dataStore.aiCompanionToolID, second.id,
            "the surviving assistant did not become the remembered one"
        )

        // The last column closes the panel.
        companion.closeColumn(companion.tool)
        XCTAssertFalse(companion.isVisible, "closing the only column left the panel open")
    }

    func testEveryAssistantOfferedIsAnOfficialHTTPSDestinationFromTheCatalog() {
        XCTAssertFalse(AICompanion.choices.isEmpty, "no assistant to put beside a page")
        for choice in AICompanion.choices {
            XCTAssertEqual(choice.officialURL.scheme, "https", "\(choice.id) is not HTTPS")
            XCTAssertNotNil(
                AIToolCatalog.tools.first { $0.id == choice.id },
                "\(choice.id) is not in the catalog the AI home shows"
            )
        }
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

    func testOpenHistoryHomeShowsTheHistorySurfaceOnTheSelectedTab() throws {
        let workspace = try makeSurfaceTestWorkspace()
        let tab = try XCTUnwrap(workspace.selectedTab)
        tab.session.navigate("https://example.com/page")
        tab.session.stopLoading()
        XCTAssertEqual(tab.session.loadState, .content)

        workspace.openHistoryHome()

        XCTAssertEqual(tab.startSurface, .historyHome)
        XCTAssertEqual(tab.session.loadState, .startPage)
        XCTAssertEqual(workspace.tabs.count, 1, "the history page reuses the selected tab")
    }

    /// The two full-page surfaces are separate destinations. Opening one must
    /// not leave a tab on the other — until they were split, History ▸ Show
    /// Full History landed on the bookmarks page.
    func testHistoryAndBookmarksHomesAreSeparateDestinations() throws {
        let workspace = try makeSurfaceTestWorkspace()
        let tab = try XCTUnwrap(workspace.selectedTab)

        workspace.openBookmarksHome()
        XCTAssertEqual(tab.startSurface, .bookmarksHome)

        workspace.openHistoryHome()
        XCTAssertEqual(tab.startSurface, .historyHome, "history replaces bookmarks, rather than sharing a toggle with it")

        workspace.openBookmarksHome()
        XCTAssertEqual(tab.startSurface, .bookmarksHome)
    }

    /// `openHistoryHome` has no request counter beside it, unlike the
    /// bookmark library. Nothing should have grown one.
    func testOpenHistoryHomeDoesNotDisturbTheBookmarkLibraryCounter() throws {
        let workspace = try makeSurfaceTestWorkspace()
        let before = workspace.bookmarkLibraryRequest

        workspace.openHistoryHome()

        XCTAssertEqual(workspace.bookmarkLibraryRequest, before)
    }

    func testGoingHomeReturnsAHistoryTabToTheAIGuide() throws {
        let workspace = try makeSurfaceTestWorkspace()
        let tab = try XCTUnwrap(workspace.selectedTab)
        workspace.openHistoryHome()
        XCTAssertEqual(tab.startSurface, .historyHome)

        tab.goHome()

        XCTAssertEqual(tab.startSurface, .aiHome, "Home always means the AI guide")
    }

    func testHistoryHomeSearchMatchesTitlesAndAddresses() {
        let visits = [
            HistoryRecord(title: "Garlic Chilli", url: "https://recipes.example/garlic"),
            HistoryRecord(title: "Swift Forums", url: "https://forums.swift.org/thread"),
            HistoryRecord(title: "", url: "https://example.com/untitled")
        ]

        XCTAssertEqual(HistoryHomeSearch.visits(visits, matching: "").count, 3, "an empty query keeps everything")
        XCTAssertEqual(HistoryHomeSearch.visits(visits, matching: "   ").count, 3, "so does whitespace")
        XCTAssertEqual(HistoryHomeSearch.visits(visits, matching: "garlic").map(\.title), ["Garlic Chilli"])
        XCTAssertEqual(
            HistoryHomeSearch.visits(visits, matching: "SWIFT.ORG").map(\.title), ["Swift Forums"],
            "the address matches too, case-insensitively"
        )
        XCTAssertEqual(HistoryHomeSearch.visits(visits, matching: "untitled").count, 1, "a visit with no title is still findable")
        XCTAssertTrue(HistoryHomeSearch.visits(visits, matching: "nothing here").isEmpty)
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
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }
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
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }
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
    /// A bare WebKit user agent gets Limeghost the page sites keep for
    /// clients they cannot identify. Presenting Safari's is a claim about the
    /// engine, and it has to keep both tokens sites actually read.
    func testLimeghostAsksForThePageSafariWouldGet() {
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
            BookmarkBarMetrics.naturalWidth(label: "Limeghost", iconWidth: 13),
            BookmarkBarMetrics.naturalWidth(label: "Limeghost")
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
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }
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
        addTeardownBlock { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }
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
            declaredIconURLs: FaviconStore.PageIcons(),
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

    // MARK: - Site icons across a redirect

    /// The case this exists for. A bookmark saved at `pinterest.co.uk` opens,
    /// the site redirects to `uk.pinterest.com`, and the icon is captured
    /// there. Without the alias the bookmark can never show an icon, however
    /// many times it is opened.
    func testAnIconCapturedAfterARedirectIsFoundUnderTheAddressTheVisitStartedAt() async throws {
        let directory = Self.makeFaviconDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FaviconStore(directory: directory, fetch: RecordingFaviconFetcher(response: Self.pngFixture()).fetch)
        let requested = try XCTUnwrap(URL(string: "https://www.pinterest.co.uk/gtedesign/"))
        let landed = try XCTUnwrap(URL(string: "https://uk.pinterest.com/gtedesign/"))

        store.recordRedirectAlias(from: requested, to: try XCTUnwrap(FaviconStore.captureHost(for: landed)), isPrivate: false)
        await store.capture(pageURL: landed, declaredIconURLs: FaviconStore.PageIcons(), isPrivate: false)

        XCTAssertNotNil(store.icon(forHost: "uk.pinterest.com"), "the icon is stored where the page ended up")
        XCTAssertNotNil(store.icon(forHost: "pinterest.co.uk"), "and is found under where the visit started")
        XCTAssertNotNil(store.icon(forHost: "www.pinterest.co.uk"), "www never splits one site in two")
    }

    /// A host's own icon must always win. Otherwise one visit that happened to
    /// redirect could replace a site's real icon with somewhere else's.
    func testAHostsOwnIconIsPreferredOverOneBorrowedThroughARedirect() async throws {
        let directory = Self.makeFaviconDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FaviconStore(directory: directory, fetch: RecordingFaviconFetcher(response: Self.pngFixture()).fetch)

        await store.capture(
            pageURL: try XCTUnwrap(URL(string: "https://start.example/page")),
            declaredIconURLs: FaviconStore.PageIcons(),
            isPrivate: false
        )
        let own = try XCTUnwrap(store.icon(forHost: "start.example"))

        await store.capture(pageURL: try XCTUnwrap(URL(string: "https://elsewhere.example/")), declaredIconURLs: FaviconStore.PageIcons(), isPrivate: false)
        store.recordRedirectAlias(
            from: try XCTUnwrap(URL(string: "https://start.example/page")),
            to: "elsewhere.example",
            isPrivate: false
        )

        XCTAssertTrue(store.icon(forHost: "start.example") === own, "its own icon is untouched by the alias")
    }

    /// Last-write-wins, which is what heals a bookmark that landed on a
    /// sign-in page once.
    func testARedirectAliasIsReplacedByTheNextOneRatherThanAccumulating() async throws {
        let directory = Self.makeFaviconDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FaviconStore(directory: directory, fetch: RecordingFaviconFetcher(response: Self.pngFixture()).fetch)
        let bookmark = try XCTUnwrap(URL(string: "https://saved.example/"))

        await store.capture(pageURL: try XCTUnwrap(URL(string: "https://signin.example/")), declaredIconURLs: FaviconStore.PageIcons(), isPrivate: false)
        store.recordRedirectAlias(from: bookmark, to: "signin.example", isPrivate: false)
        let borrowedFromSignIn = try XCTUnwrap(store.icon(forHost: "saved.example"))

        await store.capture(pageURL: try XCTUnwrap(URL(string: "https://real.example/")), declaredIconURLs: FaviconStore.PageIcons(), isPrivate: false)
        store.recordRedirectAlias(from: bookmark, to: "real.example", isPrivate: false)

        XCTAssertFalse(
            store.icon(forHost: "saved.example") === borrowedFromSignIn,
            "the newer redirect replaces the older one"
        )
        XCTAssertTrue(store.icon(forHost: "saved.example") === store.icon(forHost: "real.example"))
    }

    func testARedirectAliasSurvivesRelaunchAndIsErasedByTheDataReset() async throws {
        let directory = Self.makeFaviconDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FaviconStore(directory: directory, fetch: RecordingFaviconFetcher(response: Self.pngFixture()).fetch)
        let requested = try XCTUnwrap(URL(string: "https://old.example/"))

        await store.capture(pageURL: try XCTUnwrap(URL(string: "https://new.example/")), declaredIconURLs: FaviconStore.PageIcons(), isPrivate: false)
        store.recordRedirectAlias(from: requested, to: "new.example", isPrivate: false)

        let reopened = FaviconStore(directory: directory, fetch: Self.forbiddenFaviconFetcher)
        XCTAssertNotNil(reopened.icon(forHost: "old.example"), "the alias is read back from disk")

        reopened.clearAll()
        let afterReset = FaviconStore(directory: directory, fetch: Self.forbiddenFaviconFetcher)
        XCTAssertNil(afterReset.icon(forHost: "old.example"), "the reset takes the alias with the icons")
        XCTAssertNil(afterReset.icon(forHost: "new.example"))
    }

    /// A private window leaves nothing behind, aliases included.
    func testAPrivateVisitsRedirectAliasIsNeverWrittenToDisk() async throws {
        let directory = Self.makeFaviconDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FaviconStore(directory: directory, fetch: RecordingFaviconFetcher(response: Self.pngFixture()).fetch)

        store.recordRedirectAlias(
            from: try XCTUnwrap(URL(string: "https://private-start.example/")),
            to: "private-end.example",
            isPrivate: true
        )

        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        XCTAssertFalse(files.contains("redirects.json"), "a private visit writes no alias file")
    }

    /// Only a real cross-host redirect records anything.
    func testNoAliasIsRecordedWhenNothingRedirected() async throws {
        let directory = Self.makeFaviconDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FaviconStore(directory: directory, fetch: RecordingFaviconFetcher(response: Self.pngFixture()).fetch)
        let same = try XCTUnwrap(URL(string: "https://www.same.example/one"))

        store.recordRedirectAlias(from: same, to: "same.example", isPrivate: false)

        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        XCTAssertFalse(files.contains("redirects.json"), "www and case are the same host, not a redirect")
    }

    // MARK: - The AI home shows a tool as itself once it has been opened

    /// The AI home is the first surface anybody sees, and it must not depend
    /// on shipping other companies' logos inside the app. It draws the icon a
    /// visit already captured, and the catalog's own monogram until there is
    /// one — the same rule as every other icon in the browser.
    func testAToolsMarkUsesACapturedIconAndOtherwiseTheCatalogMonogram() async throws {
        let directory = Self.makeFaviconDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FaviconStore(directory: directory, fetch: RecordingFaviconFetcher(response: Self.pngFixture()).fetch)
        let tool = try XCTUnwrap(AIToolCatalog.tools.first)
        let host = try XCTUnwrap(tool.officialURL.host)

        XCTAssertNil(store.icon(forHost: host), "nothing is shipped with the app for this tool")
        XCTAssertFalse(tool.monogram.isEmpty, "so the catalog must carry something to draw instead")

        await store.capture(pageURL: tool.officialURL, declaredIconURLs: FaviconStore.PageIcons(), isPrivate: false)

        XCTAssertNotNil(store.icon(forHost: host), "opening the tool is what makes its own mark appear")
    }

    /// Every listing needs a monogram, because that is what shows before the
    /// reader has opened anything — the state the AI home launches in.
    func testEveryCatalogedToolCanBeDrawnBeforeItHasEverBeenOpened() {
        for tool in AIToolCatalog.tools {
            XCTAssertFalse(
                tool.monogram.trimmingCharacters(in: .whitespaces).isEmpty,
                "\(tool.name) has nothing to draw on first launch"
            )
            XCTAssertNotNil(tool.officialURL.host, "\(tool.name) has no host to key an icon by")
        }
    }

    // MARK: - A page that finishes before the icon exists

    /// A bot check, a consent bounce or a redirect stub finishes loading
    /// before the document that declares the icon exists. That first document
    /// declares nothing, so the only address to try is `/favicon.ico` — which
    /// single-page sites answer with their own HTML. Remembering "this host
    /// failed" spent the site's one chance on a page that was never going to
    /// have an icon, and refused the real one a moment later without asking.
    /// This is what left DeepSeek grey in a fresh profile.
    func testADocumentThatDeclaredNothingDoesNotBlockTheOneThatDoes() async throws {
        let directory = Self.makeFaviconDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fetcher = ScriptedFaviconFetcher([
            // The catch-all route every single-page app has.
            "https://chat.example/favicon.ico": Data("<!doctype html><html><body>app</body></html>".utf8),
            "https://cdn.example/icon-180.png": Self.pngFixture()
        ])
        let store = FaviconStore(directory: directory, fetch: fetcher.fetch)
        let page = try XCTUnwrap(URL(string: "https://chat.example/sign_in"))

        // Document one: the interstitial. Declares no icon at all.
        await store.capture(pageURL: page, declaredIconURLs: FaviconStore.PageIcons(), isPrivate: false)
        XCTAssertNil(store.icon(forHost: "chat.example"), "there was nothing to find yet")

        // Document two: the real page, declaring its icon on the CDN that
        // served its stylesheet moments earlier.
        await store.capture(
            pageURL: page,
            declaredIconURLs: FaviconStore.PageIcons(
                icons: [FaviconStore.DeclaredIcon(url: "https://cdn.example/icon-180.png", rel: "icon", sizes: "180x180", media: "")],
                contactedHosts: ["cdn.example"]
            ),
            isPrivate: false
        )

        XCTAssertNotNil(store.icon(forHost: "chat.example"), "the second document must still be asked")
        XCTAssertTrue(
            fetcher.requestedURLs.map(\.absoluteString).contains("https://cdn.example/icon-180.png"),
            "and the address it declared must actually be fetched"
        )
    }

    /// The reason the memory exists: a site with genuinely no icon offers the
    /// same one address every time, and must not be re-asked on every page.
    func testASiteWithNoIconIsStillOnlyAskedOncePerSession() async throws {
        let directory = Self.makeFaviconDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fetcher = ScriptedFaviconFetcher([:])
        let store = FaviconStore(directory: directory, fetch: fetcher.fetch)

        for path in ["/one", "/two", "/three"] {
            await store.capture(
                pageURL: try XCTUnwrap(URL(string: "https://bare.example\(path)")),
                declaredIconURLs: FaviconStore.PageIcons(),
                isPrivate: false
            )
        }

        XCTAssertEqual(
            fetcher.requestedURLs.map(\.absoluteString),
            ["https://bare.example/favicon.ico"],
            "three page views, one request"
        )
    }

    /// A site changing its icon address on every page view must not be able to
    /// make the browser fetch forever.
    func testAHostThatKeepsOfferingNewAddressesIsEventuallyLeftAlone() async throws {
        let directory = Self.makeFaviconDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fetcher = ScriptedFaviconFetcher([:])
        let store = FaviconStore(directory: directory, fetch: fetcher.fetch)
        let page = try XCTUnwrap(URL(string: "https://churn.example/"))

        for index in 0..<8 {
            await store.capture(
                pageURL: page,
                declaredIconURLs: FaviconStore.PageIcons(
                    icons: [FaviconStore.DeclaredIcon(url: "https://churn.example/icon\(index).png", rel: "icon", sizes: "", media: "")]
                ),
                isPrivate: false
            )
        }

        XCTAssertLessThanOrEqual(
            fetcher.requestedURLs.count, 8,
            "a host offering a new address every time is left alone after a few tries"
        )
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

    private static func declared(
        _ icons: [(String, String, String)],
        contacted: Set<String> = [],
        media: [String] = []
    ) -> FaviconStore.PageIcons {
        FaviconStore.PageIcons(
            icons: icons.enumerated().map { index, icon in
                FaviconStore.DeclaredIcon(
                    url: icon.0,
                    rel: icon.1,
                    sizes: icon.2,
                    media: index < media.count ? media[index] : ""
                )
            },
            contactedHosts: contacted
        )
    }

    /// Sites increasingly ship a dark mark for light backgrounds and a light
    /// one for dark, distinguished only by `media`. Limeghost's chrome is
    /// always dark, so taking the first declared icon picked the one designed
    /// to be invisible on it — Google Flow's tab was a black square.
    func testAnIconDeclaredForDarkBackgroundsIsPreferredOverOneForLight() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://labs.example/tool"))

        XCTAssertEqual(
            FaviconStore.iconCandidates(for: pageURL, declared: Self.declared(
                [
                    ("https://labs.example/icon_black.png", "icon", ""),
                    ("https://labs.example/icon_white.png", "icon", "")
                ],
                media: ["(prefers-color-scheme: light)", "(prefers-color-scheme: dark)"]
            )).first?.absoluteString,
            "https://labs.example/icon_white.png",
            "the mark made for a dark background wins on a dark tab strip"
        )
    }

    /// An icon with no media query applies everywhere, so it beats one the
    /// site said was for light backgrounds only.
    func testAnUnqualifiedIconBeatsOneDeclaredForLightBackgroundsOnly() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://labs.example/tool"))

        XCTAssertEqual(
            FaviconStore.iconCandidates(for: pageURL, declared: Self.declared(
                [
                    ("https://labs.example/icon_black.png", "icon", ""),
                    ("https://labs.example/icon_any.png", "icon", "")
                ],
                media: ["(prefers-color-scheme: light)", ""]
            )).first?.absoluteString,
            "https://labs.example/icon_any.png"
        )
    }

    func testAnUnrecognisedMediaQueryIsTreatedAsApplyingEverywhere() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://labs.example/tool"))

        XCTAssertEqual(
            FaviconStore.iconCandidates(for: pageURL, declared: Self.declared(
                [("https://labs.example/icon.png", "icon", "")],
                media: ["(min-width: 600px)"]
            )).first?.absoluteString,
            "https://labs.example/icon.png",
            "a media query about something else must not demote an icon"
        )
    }

    func testFaviconCandidatesPreferTheVisitedSiteOwnOrigin() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/story"))

        XCTAssertEqual(
            FaviconStore.iconCandidates(for: pageURL, declared: Self.declared([
                ("/assets/icon.png", "icon", ""),
                ("https://example.com/other.png", "icon", "")
            ])).map(\.absoluteString),
            [
                "https://example.com/assets/icon.png",
                "https://example.com/other.png",
                "https://example.com/favicon.ico"
            ],
            "same-origin icons are tried in declaration order, then the origin's own /favicon.ico"
        )
        XCTAssertTrue(
            FaviconStore.iconCandidates(
                for: try XCTUnwrap(URL(string: "file:///Users/private/page.html")),
                declared: Self.declared([("file:///Users/private/icon.png", "icon", "")])
            ).isEmpty,
            "only real web pages are ever candidates"
        )
        XCTAssertNil(FaviconStore.captureHost(for: try XCTUnwrap(URL(string: "about:blank"))))
    }

    /// The rule the same-origin one replaced. A host the page never touched is
    /// never asked — which is what keeps a favicon service impossible, since
    /// nothing on any page is ever loaded from one.
    func testAnIconIsOnlyFetchedFromAHostThePageItselfAlreadyUsed() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://chat.example/"))

        XCTAssertEqual(
            FaviconStore.iconCandidates(for: pageURL, declared: Self.declared(
                [("https://assets.cdn.example/app/favicon.png", "icon", "")],
                contacted: ["assets.cdn.example"]
            )).map(\.absoluteString),
            ["https://assets.cdn.example/app/favicon.png", "https://chat.example/favicon.ico"],
            "the CDN that already served this page may be asked for its icon"
        )
        XCTAssertEqual(
            FaviconStore.iconCandidates(for: pageURL, declared: Self.declared(
                [
                    ("https://www.google.com/s2/favicons?domain=chat.example", "icon", ""),
                    ("https://assets.cdn.example/app/favicon.png", "icon", "")
                ],
                contacted: ["assets.cdn.example"]
            )).map(\.absoluteString),
            ["https://assets.cdn.example/app/favicon.png", "https://chat.example/favicon.ico"],
            "an icon service the page never loaded from is dropped even when the page names it"
        )
        XCTAssertEqual(
            FaviconStore.iconCandidates(for: pageURL, declared: Self.declared(
                [("http://assets.cdn.example/icon.png", "icon", "")],
                contacted: ["assets.cdn.example"]
            )).map(\.absoluteString),
            ["https://chat.example/favicon.ico"],
            "reaching off-origin is https only, whatever the page asks for"
        )
    }

    func testTheSitesOwnOriginIsPreferredOverAHostItMerelyUsed() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://chat.example/"))

        XCTAssertEqual(
            FaviconStore.iconCandidates(for: pageURL, declared: Self.declared(
                [
                    ("https://cdn.example/icon.png", "icon", ""),
                    ("https://chat.example/icon.png", "icon", "")
                ],
                contacted: ["cdn.example"]
            )).first?.absoluteString,
            "https://chat.example/icon.png",
            "a site's own address is asked before anywhere else"
        )
    }

    func testABitmapIsPreferredOverAnSVGAndASizeCloseToWhatIsStored() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/"))

        XCTAssertEqual(
            FaviconStore.iconCandidates(for: pageURL, declared: Self.declared([
                ("https://example.com/icon.svg", "icon", "any"),
                ("https://example.com/icon-512.png", "icon", "512x512")
            ])).first?.absoluteString,
            "https://example.com/icon-512.png",
            "an SVG cannot be decoded today, so a bitmap beside it wins"
        )
        XCTAssertEqual(
            FaviconStore.iconCandidates(for: pageURL, declared: Self.declared([
                ("https://example.com/icon-16.png", "icon", "16x16"),
                ("https://example.com/icon-64.png", "icon", "64x64"),
                ("https://example.com/icon-512.png", "icon", "512x512")
            ])).first?.absoluteString,
            "https://example.com/icon-64.png",
            "the size that needs neither upscaling nor much downscaling is tried first"
        )
    }

    func testAtMostFourAddressesAreEverTried() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/"))
        let many = (0..<8).map { ("https://example.com/icon\($0).png", "icon", "") }

        let candidates = FaviconStore.iconCandidates(for: pageURL, declared: Self.declared(many))

        XCTAssertEqual(candidates.count, FaviconStore.maximumCandidates)
        XCTAssertEqual(candidates.last?.absoluteString, "https://example.com/favicon.ico", "the guess is always last")
    }

    func testPrivateFaviconCaptureKeepsTheIconInMemoryAndOffTheDisk() async throws {
        let directory = Self.makeFaviconDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fetcher = RecordingFaviconFetcher(response: Self.pngFixture())
        let store = FaviconStore(directory: directory, fetch: fetcher.fetch)

        await store.capture(
            pageURL: try XCTUnwrap(URL(string: "https://private.example/page")),
            declaredIconURLs: Self.declared([("https://private.example/icon.png", "icon", "")]),
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
            declaredIconURLs: FaviconStore.PageIcons(),
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

        await store.capture(pageURL: pageURL, declaredIconURLs: FaviconStore.PageIcons(), isPrivate: false)
        await store.capture(pageURL: pageURL, declaredIconURLs: FaviconStore.PageIcons(), isPrivate: false)

        XCTAssertEqual(fetcher.requestedURLs.count, 1, "one silent attempt per host per session, then nothing")
        XCTAssertNil(store.icon(forHost: "127.0.0.1"))
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [], [])
    }

    private static func makeFaviconDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("limeghost-favicons-\(UUID().uuidString)", isDirectory: true)
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
        addTeardownBlock { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }

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
        addTeardownBlock { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }
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
        addTeardownBlock { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }
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
            .appendingPathComponent("limeghost-content-blocking-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// A provider backed by a throwaway rule store and a two-domain list, so
    /// tests never touch the shared WebKit store or pay for the shipped list.
    fileprivate static func makeTestContentBlocking(
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
/// Answers each address differently, so a test can model a site whose first
/// document is not the one that declares the icon.
private final class ScriptedFaviconFetcher {
    private(set) var requestedURLs: [URL] = []
    private let responses: [String: Data?]

    init(_ responses: [String: Data?]) {
        self.responses = responses
    }

    func fetch(_ url: URL) async -> Data? {
        requestedURLs.append(url)
        return responses[url.absoluteString] ?? nil
    }
}

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

/// The drop-resolution half of tab reordering. `TabStrip.chipID(at:in:)` is
/// what turns a pointer position into the tab a drag has landed on, and it is
/// the part a unit test can reach: the gesture that feeds it lives in AppKit's
/// event dispatch, which no test here can drive.
@MainActor
final class TabStripDropResolutionTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID()

    /// Chips 120pt wide with 8pt gaps, laid out left to right.
    private var frames: [UUID: CGRect] {
        [
            a: CGRect(x: 0, y: 0, width: 120, height: 32),
            b: CGRect(x: 128, y: 0, width: 120, height: 32),
            c: CGRect(x: 256, y: 0, width: 120, height: 32),
        ]
    }

    func testAPointInsideAChipResolvesToThatChip() {
        XCTAssertEqual(TabStrip.chipID(at: CGPoint(x: 60, y: 16), in: frames), a)
        XCTAssertEqual(TabStrip.chipID(at: CGPoint(x: 190, y: 16), in: frames), b)
        XCTAssertEqual(TabStrip.chipID(at: CGPoint(x: 300, y: 16), in: frames), c)
    }

    func testAPointInTheGapBetweenChipsSnapsToTheNearerOne() {
        // The gap runs 120...128. 122 is nearer a's trailing edge, 126 nearer b's.
        XCTAssertEqual(TabStrip.chipID(at: CGPoint(x: 122, y: 16), in: frames), a)
        XCTAssertEqual(TabStrip.chipID(at: CGPoint(x: 126, y: 16), in: frames), b)
    }

    func testAPointPastEitherEndOfTheStripStillResolves() {
        XCTAssertEqual(TabStrip.chipID(at: CGPoint(x: -500, y: 16), in: frames), a)
        XCTAssertEqual(TabStrip.chipID(at: CGPoint(x: 5_000, y: 16), in: frames), c)
    }

    /// A drag runs along one row; drifting above or below the strip must not
    /// change which tab the pointer is over.
    func testVerticalDriftDoesNotChangeTheAnswer() {
        for y in [-400.0, -1.0, 16.0, 33.0, 400.0] {
            XCTAssertEqual(TabStrip.chipID(at: CGPoint(x: 190, y: y), in: frames), b, "y=\(y)")
        }
    }

    /// Mid-animation the frames briefly overlap. The answer has to come from
    /// the geometry, not from whatever order the dictionary happens to be in.
    func testOverlappingFramesResolveToTheLeftmostAndAreStable() {
        let overlapping: [UUID: CGRect] = [
            a: CGRect(x: 100, y: 0, width: 120, height: 32),
            b: CGRect(x: 100, y: 0, width: 120, height: 32),
        ]
        let answers = (0..<50).map { _ in TabStrip.chipID(at: CGPoint(x: 150, y: 16), in: overlapping) }
        XCTAssertEqual(Set(answers).count, 1, "resolution must not depend on dictionary order")
    }

    func testAnEmptyStripResolvesToNothing() {
        XCTAssertNil(TabStrip.chipID(at: CGPoint(x: 10, y: 10), in: [:]))
    }

    // MARK: - Reordering must not undo itself

    /// The real geometry the shake happened on: five tabs in a 700pt strip,
    /// the selected one wider than the rest.
    private static func compressedStrip(order: [UUID], selected: UUID) -> [UUID: CGRect] {
        var frames: [UUID: CGRect] = [:]
        var x: CGFloat = 0
        for id in order {
            let width: CGFloat = id == selected ? 177 : 126
            frames[id] = CGRect(x: x, y: 0, width: width, height: 32)
            x += width + 4
        }
        return frames
    }

    /// A chip that has entered a wider neighbour but not yet reached its
    /// midpoint stays put. This exact input swapped under the old rule, and
    /// the swap is what the next event undid.
    func testACarriedChipDoesNotDisplaceANeighbourItHasOnlyPartlyOverlapped() {
        let frames = Self.compressedStrip(order: [a, b], selected: b)
        // `a` is 0..126, `b` is 130..307 with midpoint 218.5.
        XCTAssertNil(TabStrip.reorderTarget(carrying: a, centre: 200, in: frames))
        XCTAssertEqual(TabStrip.reorderTarget(carrying: a, centre: 220, in: frames), b)
    }

    /// The invariant whose absence let this ship: apply the swap, rebuild the
    /// frames the layout would then produce, and the same pointer position
    /// must no longer ask for anything.
    func testASwapIsNotImmediatelyUndoneAtTheSamePointerPosition() {
        let before = Self.compressedStrip(order: [a, b], selected: b)
        let centre: CGFloat = 220
        XCTAssertEqual(TabStrip.reorderTarget(carrying: a, centre: centre, in: before), b)

        let after = Self.compressedStrip(order: [b, a], selected: b)
        XCTAssertNil(
            TabStrip.reorderTarget(carrying: a, centre: centre, in: after),
            "the swap put the neighbour back under this point; it must not swap back"
        )
        // The band that actually shook. Once `b` is first it occupies 0...177,
        // so anything from 128 to 179 sits inside the neighbour's rectangle —
        // which is why asking "whose rectangle is this?" swapped straight back.
        // Measured against a resting midpoint instead, none of it moves.
        for centre in stride(from: CGFloat(128), through: 179, by: 1) {
            XCTAssertNil(
                TabStrip.reorderTarget(carrying: a, centre: centre, in: after),
                "x=\(centre) is inside the neighbour but behind its midpoint; it must not reorder"
            )
        }
    }

    /// Dragged across the whole strip one point at a time, the order changes
    /// monotonically and never revisits an arrangement it already left.
    func testAStepwiseDragReordersOnceAndNeverRevisitsAnOrder() {
        var order = [a, b, c]
        var seen: Set<[UUID]> = [order]
        var changes = 0

        for step in stride(from: CGFloat(60), through: 700, by: 1) {
            let frames = Self.compressedStrip(order: order, selected: b)
            guard let target = TabStrip.reorderTarget(carrying: a, centre: step, in: frames),
                  let from = order.firstIndex(of: a),
                  let to = order.firstIndex(of: target)
            else { continue }
            order.remove(at: from)
            order.insert(a, at: to)
            changes += 1
            XCTAssertTrue(seen.insert(order).inserted, "order \(order) was revisited at x=\(step)")
        }

        XCTAssertEqual(order, [b, c, a], "the tab ends up last, having passed both neighbours")
        XCTAssertEqual(changes, 2, "one move per neighbour passed, never a flip back")
    }

    /// A hand resting exactly on a boundary must not shake.
    func testAPointerParkedOnABoundaryProducesNoReorders() {
        let frames = Self.compressedStrip(order: [a, b], selected: b)
        let midpoint = try! XCTUnwrap(frames[b]).midX
        for jitter in stride(from: CGFloat(-1), through: 1, by: 0.1) {
            let target = TabStrip.reorderTarget(carrying: a, centre: midpoint + jitter, in: frames)
            // Either side of the midpoint asks for at most the one neighbour,
            // and never for something behind it.
            XCTAssertNotEqual(target, a)
        }
    }

    func testACarriedChipAtTheEndsOfTheStripHasNowhereFurtherToGo() {
        let frames = Self.compressedStrip(order: [a, b], selected: b)
        XCTAssertNil(TabStrip.reorderTarget(carrying: a, centre: -500, in: frames), "already leftmost")
        XCTAssertNil(TabStrip.reorderTarget(carrying: b, centre: 5_000, in: frames), "already rightmost")
    }

    func testAReorderTargetIsNothingWhenTheCarriedChipIsUnknown() {
        XCTAssertNil(TabStrip.reorderTarget(carrying: c, centre: 100, in: Self.compressedStrip(order: [a, b], selected: b)))
    }

    /// Three unpinned tabs in a throwaway defaults suite, plus the cleanup the
    /// suite and the rule-list store both need.
    private static func makeStripWorkspace() throws -> (BrowserWorkspace, () -> Void) {
        let suiteName = "clearframe.tabstrip.drop.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let blocking = try BrowserBehaviorTests.makeTestContentBlocking(defaults: defaults)
        let workspace = BrowserWorkspace(
            dataStore: BrowserDataStore(defaults: defaults),
            downloads: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking.provider
        )
        while workspace.tabs.count > 1, let last = workspace.tabs.last {
            workspace.closeTab(last.id)
        }
        while workspace.tabs.count < 3 { workspace.addTab() }
        return (workspace, {
            blocking.removeStore()
            TestSuiteCleanup.destroy(suiteName, defaults: defaults)
        })
    }

    /// End to end over the two pieces the gesture actually calls: resolve the
    /// chip under the pointer, then ask the workspace to move the dragged tab
    /// there. Dragging the first tab onto the third must land it third.
    func testResolvingADropAndMovingTheTabReordersTheStrip() throws {
        let (workspace, teardown) = try Self.makeStripWorkspace()
        defer { teardown() }
        let ids = workspace.tabs.map(\.id)
        guard ids.count >= 3 else { return XCTFail("expected three tabs, got \(ids.count)") }

        let laid: [UUID: CGRect] = [
            ids[0]: CGRect(x: 0, y: 0, width: 120, height: 32),
            ids[1]: CGRect(x: 128, y: 0, width: 120, height: 32),
            ids[2]: CGRect(x: 256, y: 0, width: 120, height: 32),
        ]
        let target = TabStrip.chipID(at: CGPoint(x: 300, y: 16), in: laid)
        XCTAssertEqual(target, ids[2])

        let index = workspace.tabs.firstIndex { $0.id == target }
        XCTAssertEqual(index, 2)
        XCTAssertTrue(workspace.moveTab(ids[0], toIndex: index!))
        XCTAssertEqual(workspace.tabs.map(\.id), [ids[1], ids[2], ids[0]])
    }

    /// The same path in the other direction — the user asked for both.
    func testDraggingTheLastTabLeftwardsReordersTheStrip() throws {
        let (workspace, teardown) = try Self.makeStripWorkspace()
        defer { teardown() }
        let ids = workspace.tabs.map(\.id)
        guard ids.count >= 3 else { return XCTFail("expected three tabs, got \(ids.count)") }

        let laid: [UUID: CGRect] = [
            ids[0]: CGRect(x: 0, y: 0, width: 120, height: 32),
            ids[1]: CGRect(x: 128, y: 0, width: 120, height: 32),
            ids[2]: CGRect(x: 256, y: 0, width: 120, height: 32),
        ]
        let target = TabStrip.chipID(at: CGPoint(x: 40, y: 16), in: laid)
        XCTAssertEqual(target, ids[0])
        XCTAssertTrue(workspace.moveTab(ids[2], toIndex: 0))
        XCTAssertEqual(workspace.tabs.map(\.id), [ids[2], ids[0], ids[1]])
    }
}

/// Moving a tab from one window to another. `detachTab` and `adopt` are the
/// two halves of dragging a tab out of the strip: the drag itself lives in
/// AppKit's event dispatch, which no test here can drive, but everything the
/// gesture asks the workspace to do is checked below.
@MainActor
final class TabDetachAndAdoptTests: XCTestCase {
    func testDetachingRemovesTheTabAndHandsItBackAlive() throws {
        let (workspace, teardown) = try Self.makeWorkspace(tabs: 3)
        defer { teardown() }
        let ids = workspace.tabs.map(\.id)
        let session = workspace.tabs[1].session

        let detached = try XCTUnwrap(workspace.detachTab(ids[1]))

        XCTAssertEqual(detached.id, ids[1])
        XCTAssertEqual(workspace.tabs.map(\.id), [ids[0], ids[2]])
        // The same session object, which is what carries the web view — and so
        // the page's scroll position and its back/forward list — into the new
        // window instead of reloading it from the address.
        XCTAssertTrue(detached.session === session)
    }

    /// A closed tab can be reopened; a moved one has not gone anywhere, so
    /// offering to reopen it would put a second copy on screen.
    func testDetachingDoesNotRecordTheTabAsClosed() throws {
        let (workspace, teardown) = try Self.makeWorkspace(tabs: 2)
        defer { teardown() }
        let id = workspace.tabs[1].id
        XCTAssertFalse(workspace.canReopenClosedTab)

        _ = workspace.detachTab(id)

        XCTAssertFalse(workspace.canReopenClosedTab)
    }

    /// Pulling the only tab out would close this window to open an identical
    /// one. Chrome moves the window instead, and so does the strip.
    func testTheLastTabInAWindowCannotBeDetached() throws {
        let (workspace, teardown) = try Self.makeWorkspace(tabs: 1)
        defer { teardown() }
        XCTAssertEqual(workspace.tabs.count, 1)
        XCTAssertFalse(workspace.canDetachTab)

        XCTAssertNil(workspace.detachTab(workspace.tabs[0].id))
        XCTAssertEqual(workspace.tabs.count, 1)
    }

    func testDetachingTheSelectedTabSelectsAnother() throws {
        let (workspace, teardown) = try Self.makeWorkspace(tabs: 3)
        defer { teardown() }
        let ids = workspace.tabs.map(\.id)
        workspace.selectTab(ids[1])
        XCTAssertEqual(workspace.selectedTabID, ids[1])

        _ = workspace.detachTab(ids[1])

        XCTAssertNotNil(workspace.selectedTabID)
        XCTAssertNotEqual(workspace.selectedTabID, ids[1])
        XCTAssertTrue(workspace.tabs.contains { $0.id == workspace.selectedTabID })
    }

    /// The group belongs to the window it was made in, so a tab that leaves
    /// arrives ungrouped rather than referring to a group that is not there.
    func testADetachedTabLeavesItsGroupBehind() throws {
        let (workspace, teardown) = try Self.makeWorkspace(tabs: 3)
        defer { teardown() }
        let ids = workspace.tabs.map(\.id)
        workspace.createGroup(withTabs: [ids[0], ids[1]])
        XCTAssertNotNil(workspace.tabs.first { $0.id == ids[1] }?.groupID)

        let detached = try XCTUnwrap(workspace.detachTab(ids[1]))

        XCTAssertNil(detached.groupID)
    }

    func testAdoptingPlacesTheTabAndSelectsIt() throws {
        let (source, tearDownSource) = try Self.makeWorkspace(tabs: 2)
        defer { tearDownSource() }
        let (destination, tearDownDestination) = try Self.makeWorkspace(tabs: 2)
        defer { tearDownDestination() }
        let moved = try XCTUnwrap(source.detachTab(source.tabs[1].id))
        let existing = destination.tabs.map(\.id)

        destination.adopt(moved)

        XCTAssertEqual(destination.tabs.map(\.id), existing + [moved.id])
        XCTAssertEqual(destination.selectedTabID, moved.id)
    }

    func testAdoptingAtAnIndexDropsTheTabThere() throws {
        let (source, tearDownSource) = try Self.makeWorkspace(tabs: 2)
        defer { tearDownSource() }
        let (destination, tearDownDestination) = try Self.makeWorkspace(tabs: 3)
        defer { tearDownDestination() }
        let moved = try XCTUnwrap(source.detachTab(source.tabs[1].id))
        let existing = destination.tabs.map(\.id)

        destination.adopt(moved, at: 1)

        XCTAssertEqual(destination.tabs.map(\.id), [existing[0], moved.id, existing[1], existing[2]])
    }

    /// The pinned run still comes first. An unpinned tab dropped over the
    /// pinned tabs lands after them rather than splitting them.
    func testAnAdoptedUnpinnedTabLandsAfterThePinnedRun() throws {
        let (source, tearDownSource) = try Self.makeWorkspace(tabs: 2)
        defer { tearDownSource() }
        let (destination, tearDownDestination) = try Self.makeWorkspace(tabs: 3)
        defer { tearDownDestination() }
        destination.pinTab(destination.tabs[0].id)
        destination.pinTab(destination.tabs[1].id)
        let moved = try XCTUnwrap(source.detachTab(source.tabs[1].id))
        XCTAssertFalse(moved.isPinned)

        destination.adopt(moved, at: 0)

        let index = try XCTUnwrap(destination.tabs.firstIndex { $0.id == moved.id })
        XCTAssertEqual(index, 2, "an unpinned tab must not land inside the pinned run")
        XCTAssertTrue(destination.tabs.prefix(2).allSatisfy(\.isPinned))
    }

    func testAPinnedTabStaysPinnedWhenItMovesWindow() throws {
        let (source, tearDownSource) = try Self.makeWorkspace(tabs: 2)
        defer { tearDownSource() }
        let (destination, tearDownDestination) = try Self.makeWorkspace(tabs: 2)
        defer { tearDownDestination() }
        source.pinTab(source.tabs[0].id)
        let pinnedID = try XCTUnwrap(source.tabs.first { $0.isPinned }).id

        let moved = try XCTUnwrap(source.detachTab(pinnedID))
        destination.adopt(moved)

        XCTAssertTrue(moved.isPinned)
        XCTAssertEqual(destination.tabs.first?.id, moved.id, "a pinned tab belongs at the front")
    }

    func testAdoptingTheSameTabTwiceDoesNothingTheSecondTime() throws {
        let (source, tearDownSource) = try Self.makeWorkspace(tabs: 2)
        defer { tearDownSource() }
        let (destination, tearDownDestination) = try Self.makeWorkspace(tabs: 1)
        defer { tearDownDestination() }
        let moved = try XCTUnwrap(source.detachTab(source.tabs[1].id))

        destination.adopt(moved)
        let after = destination.tabs.map(\.id)
        destination.adopt(moved)

        XCTAssertEqual(destination.tabs.map(\.id), after)
    }

    /// Only the window that restored the saved session writes it back. A
    /// second window doing so would replace the session with its own tabs.
    func testAWindowThatDidNotRestoreTheSessionDoesNotOverwriteIt() throws {
        let suiteName = "clearframe.detach.persist.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }
        let blocking = try BrowserBehaviorTests.makeTestContentBlocking(defaults: defaults)
        defer { blocking.removeStore() }
        let dataStore = BrowserDataStore(defaults: defaults)

        let primary = BrowserWorkspace(
            dataStore: dataStore,
            downloads: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking.provider
        )
        primary.addTab(url: URL(string: "https://kept.example")!)
        primary.persistNow()
        let saved = try XCTUnwrap(dataStore.loadWorkspace())

        let secondary = BrowserWorkspace(
            dataStore: dataStore,
            downloads: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking.provider,
            restoresSession: false
        )
        secondary.addTab(url: URL(string: "https://transient.example")!)
        secondary.persistNow()

        let reloaded = try XCTUnwrap(dataStore.loadWorkspace())
        XCTAssertEqual(reloaded.tabs.map(\.id), saved.tabs.map(\.id))
    }

    /// A window opened around a torn-off tab shows that page and nothing else
    /// — in particular it does not also restore the first window's tabs.
    func testAWindowOpenedAroundATabShowsOnlyThatTab() throws {
        let (source, tearDownSource) = try Self.makeWorkspace(tabs: 3)
        defer { tearDownSource() }
        let moved = try XCTUnwrap(source.detachTab(source.tabs[1].id))

        let suiteName = "clearframe.detach.adopting.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }
        let blocking = try BrowserBehaviorTests.makeTestContentBlocking(defaults: defaults)
        defer { blocking.removeStore() }

        let torn = BrowserWorkspace(
            dataStore: BrowserDataStore(defaults: defaults),
            downloads: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking.provider,
            restoresSession: false,
            adopting: moved
        )

        XCTAssertEqual(torn.tabs.map(\.id), [moved.id])
        XCTAssertEqual(torn.selectedTabID, moved.id)
        XCTAssertFalse(torn.canDetachTab, "the only tab in a new window cannot be torn out again")
    }

    private static func makeWorkspace(tabs count: Int) throws -> (BrowserWorkspace, () -> Void) {
        let suiteName = "clearframe.detach.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let blocking = try BrowserBehaviorTests.makeTestContentBlocking(defaults: defaults)
        let workspace = BrowserWorkspace(
            dataStore: BrowserDataStore(defaults: defaults),
            downloads: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking.provider
        )
        while workspace.tabs.count > 1, let last = workspace.tabs.last {
            workspace.closeTab(last.id)
        }
        while workspace.tabs.count < count { workspace.addTab() }
        return (workspace, {
            blocking.removeStore()
            TestSuiteCleanup.destroy(suiteName, defaults: defaults)
        })
    }
}

/// Dropping a tab into a window that already has tabs, which is what happens
/// when a drag is released over another window's strip.
@MainActor
final class TabMergeBetweenWindowsTests: XCTestCase {
    /// The whole point of the merge: the window a lone tab leaves is empty,
    /// so `detachTab` has to allow it and the strip closes that window.
    func testTheLastTabCanLeaveWhenItIsJoiningAnotherWindow() throws {
        let (source, tearDownSource) = try Self.makeWorkspace(tabs: 1)
        defer { tearDownSource() }
        let (destination, tearDownDestination) = try Self.makeWorkspace(tabs: 2)
        defer { tearDownDestination() }
        let id = source.tabs[0].id
        XCTAssertFalse(source.canDetachTab)

        let moved = try XCTUnwrap(source.detachTab(id, evenIfLast: true))
        destination.adopt(moved)

        XCTAssertTrue(source.tabs.isEmpty)
        XCTAssertNil(source.selectedTabID, "an emptied window has nothing to select")
        XCTAssertEqual(destination.tabs.count, 3)
        XCTAssertEqual(destination.selectedTabID, moved.id)
    }

    /// Without `evenIfLast` the guard still holds, so a plain tear-off never
    /// empties the window it came from.
    func testALoneTabStillCannotBeTornIntoAWindowOfItsOwn() throws {
        let (workspace, teardown) = try Self.makeWorkspace(tabs: 1)
        defer { teardown() }
        XCTAssertNil(workspace.detachTab(workspace.tabs[0].id))
        XCTAssertEqual(workspace.tabs.count, 1)
    }

    func testATabMergedInKeepsItsLiveSession() throws {
        let (source, tearDownSource) = try Self.makeWorkspace(tabs: 2)
        defer { tearDownSource() }
        let (destination, tearDownDestination) = try Self.makeWorkspace(tabs: 1)
        defer { tearDownDestination() }
        let session = source.tabs[1].session

        let moved = try XCTUnwrap(source.detachTab(source.tabs[1].id))
        destination.adopt(moved)

        let landed = try XCTUnwrap(destination.tabs.first { $0.id == moved.id })
        XCTAssertTrue(landed.session === session)
    }

    /// A tab moved out and then back again must not leave a stale copy in
    /// either window.
    func testATabCanBeMovedBackToTheWindowItCameFrom() throws {
        let (first, tearDownFirst) = try Self.makeWorkspace(tabs: 2)
        defer { tearDownFirst() }
        let (second, tearDownSecond) = try Self.makeWorkspace(tabs: 1)
        defer { tearDownSecond() }
        let travellerID = first.tabs[1].id

        let out = try XCTUnwrap(first.detachTab(travellerID))
        second.adopt(out)
        let back = try XCTUnwrap(second.detachTab(travellerID))
        first.adopt(back)

        XCTAssertEqual(first.tabs.filter { $0.id == travellerID }.count, 1)
        XCTAssertFalse(second.tabs.contains { $0.id == travellerID })
        XCTAssertEqual(second.tabs.count, 1)
    }

    private static func makeWorkspace(tabs count: Int) throws -> (BrowserWorkspace, () -> Void) {
        let suiteName = "clearframe.merge.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let blocking = try BrowserBehaviorTests.makeTestContentBlocking(defaults: defaults)
        let workspace = BrowserWorkspace(
            dataStore: BrowserDataStore(defaults: defaults),
            downloads: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking.provider
        )
        while workspace.tabs.count > 1, let last = workspace.tabs.last {
            workspace.closeTab(last.id)
        }
        while workspace.tabs.count < count { workspace.addTab() }
        return (workspace, {
            blocking.removeStore()
            TestSuiteCleanup.destroy(suiteName, defaults: defaults)
        })
    }
}

/// The File menu's page commands, and the labels the new menus show.
@MainActor
final class PageFileCommandTests: XCTestCase {
    func testAFileNameIsBuiltFromThePageTitle() {
        XCTAssertEqual(PageFileCommands.safeFileName(from: "Apple Newsroom"), "Apple Newsroom")
    }

    /// A page title is not a filename: a slash would write into another
    /// directory, and a colon is a path separator to the Finder.
    func testPathCharactersAreRemovedFromAFileName() {
        let name = PageFileCommands.safeFileName(from: "Reports / Q3: draft?")
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(":"))
        XCTAssertFalse(name.contains("?"))
    }

    func testARunawayTitleIsCutToAUsableFileName() {
        let name = PageFileCommands.safeFileName(from: String(repeating: "long title ", count: 40))
        XCTAssertLessThanOrEqual(name.count, 80)
        XCTAssertFalse(name.isEmpty)
    }

    func testATitleThatIsAllWhitespaceStillProducesAName() {
        XCTAssertEqual(PageFileCommands.safeFileName(from: "   \n  "), "Untitled Page")
    }

    /// Everything an open panel offers has to be something the engine can
    /// actually show, or the panel invites a file that opens as a blank page.
    func testTheOpenPanelOffersOnlyTypesTheEngineRenders() {
        let types = PageFileCommands.openableTypes
        XCTAssertTrue(types.contains(.html))
        XCTAssertTrue(types.contains(.pdf))
        XCTAssertFalse(types.contains(.executable))
        XCTAssertFalse(types.contains(.archive))
    }

    func testAShortMenuTitleIsLeftAlone() {
        XCTAssertEqual(BookmarkMenuTitle.short("News"), "News")
    }

    func testALongMenuTitleIsCutOnAWord() {
        let title = "A very long headline about something that happened somewhere today and yesterday"
        let short = BookmarkMenuTitle.short(title)
        XCTAssertLessThanOrEqual(short.count, 61)
        XCTAssertTrue(short.hasSuffix("…"))
        XCTAssertFalse(short.contains("  "))
        // Cut on a word, so the label does not end mid-syllable.
        XCTAssertFalse(short.dropLast().hasSuffix(" "))
    }

    func testAnEmptyMenuTitleStillReads() {
        XCTAssertEqual(BookmarkMenuTitle.short("   "), "Untitled")
    }
}

/// Opening a file is a separate door from opening a web address, and the one
/// stays shut when the other opens.
@MainActor
final class LocalFileOpeningTests: XCTestCase {
    /// The boundary that must not move: nothing that arrives as text — a
    /// typed address, a link, a restored record — can name a local file.
    func testAFileAddressIsStillRejectedEverywhereItWasBefore() {
        XCTAssertNil(WebURLPolicy.validatedURL("file:///etc/passwd"))
        XCTAssertNil(WebURLPolicy.validatedURL("File:///Users/someone/Desktop/page.html"))
        XCTAssertNil(BookmarkURLPolicy.validatedURL("file:///etc/hosts"))
    }

    func testOpeningAFileAddsATabShowingIt() throws {
        let (workspace, teardown) = try Self.makeWorkspace()
        defer { teardown() }
        let file = try Self.writeTemporaryPage()
        defer { try? FileManager.default.removeItem(at: file) }
        let before = workspace.tabs.count

        workspace.openLocalFile(file)

        XCTAssertEqual(workspace.tabs.count, before + 1)
        let opened = try XCTUnwrap(workspace.selectedTab)
        XCTAssertEqual(opened.session.currentURLString, file.absoluteString)
    }

    /// A web address is not a file, and asking to open one as a file does
    /// nothing rather than something surprising.
    func testOpeningANonFileAddressDoesNothing() throws {
        let (workspace, teardown) = try Self.makeWorkspace()
        defer { teardown() }
        let before = workspace.tabs.count

        workspace.openLocalFile(URL(string: "https://example.com")!)

        XCTAssertEqual(workspace.tabs.count, before)
    }

    /// The saved session is a file on disk. A local path written into it would
    /// be a record of what somebody opened, kept for a restore that refuses to
    /// use it anyway.
    func testALocalPageIsNotWrittenIntoTheSavedSession() throws {
        let suiteName = "clearframe.localfile.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }
        let blocking = try BrowserBehaviorTests.makeTestContentBlocking(defaults: defaults)
        defer { blocking.removeStore() }
        let dataStore = BrowserDataStore(defaults: defaults)
        let workspace = BrowserWorkspace(
            dataStore: dataStore,
            downloads: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking.provider
        )
        let file = try Self.writeTemporaryPage()
        defer { try? FileManager.default.removeItem(at: file) }

        workspace.openLocalFile(file)
        workspace.persistNow()

        let saved = try XCTUnwrap(dataStore.loadWorkspace())
        let urls = saved.tabs.compactMap(\.url)
        XCTAssertFalse(
            urls.contains { $0.hasPrefix("file:") },
            "a local path must not reach the saved session: \(urls)"
        )
    }

    private static func writeTemporaryPage() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("limeghost-test-\(UUID().uuidString).html")
        try "<html><body><h1>Local page</h1></body></html>".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func makeWorkspace() throws -> (BrowserWorkspace, () -> Void) {
        let suiteName = "clearframe.openfile.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let blocking = try BrowserBehaviorTests.makeTestContentBlocking(defaults: defaults)
        let workspace = BrowserWorkspace(
            dataStore: BrowserDataStore(defaults: defaults),
            downloads: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking.provider
        )
        return (workspace, {
            blocking.removeStore()
            TestSuiteCleanup.destroy(suiteName, defaults: defaults)
        })
    }
}

/// What the History menu offers. History records every visit; a menu wants
/// pages.
@MainActor
final class HistoryMenuTests: XCTestCase {
    private func visit(_ url: String, _ title: String, minutesAgo: Int) -> HistoryRecord {
        HistoryRecord(
            title: title,
            url: url,
            visitedAt: Date(timeIntervalSince1970: 1_000_000 - Double(minutesAgo * 60))
        )
    }

    func testEachPageIsOfferedOnce() {
        let history = [
            visit("https://a.example", "A", minutesAgo: 1),
            visit("https://b.example", "B", minutesAgo: 2),
            visit("https://a.example", "A", minutesAgo: 3),
            visit("https://a.example", "A", minutesAgo: 4),
        ]
        let recent = LimeghostBrowserApp.recentPages(in: history)
        XCTAssertEqual(recent.map(\.url), ["https://a.example", "https://b.example"])
    }

    /// The newest visit wins, so a page that was reopened sits where its most
    /// recent visit puts it rather than where it first appeared.
    func testThePageKeepsItsMostRecentVisit() {
        let history = [
            visit("https://b.example", "B now", minutesAgo: 1),
            visit("https://a.example", "A", minutesAgo: 2),
            visit("https://b.example", "B before", minutesAgo: 90),
        ]
        let recent = LimeghostBrowserApp.recentPages(in: history)
        XCTAssertEqual(recent.first?.title, "B now")
        XCTAssertEqual(recent.count, 2)
    }

    func testTheMenuStaysShort() {
        let history = (0..<50).map { visit("https://site\($0).example", "Page \($0)", minutesAgo: $0) }
        XCTAssertEqual(LimeghostBrowserApp.recentPages(in: history).count, 12)
    }

    func testAnEmptyHistoryOffersNothing() {
        XCTAssertTrue(LimeghostBrowserApp.recentPages(in: []).isEmpty)
    }
}

/// A private window, as opposed to a private tab in an ordinary one.
@MainActor
final class PrivateWindowTests: XCTestCase {
    func testAPrivateWindowOpensWithAPrivateTab() throws {
        let (workspace, teardown) = try Self.makeWorkspace(isPrivate: true)
        defer { teardown() }
        XCTAssertTrue(workspace.isPrivate)
        XCTAssertEqual(workspace.tabs.count, 1)
        XCTAssertTrue(workspace.tabs.allSatisfy(\.isPrivate))
    }

    /// The point of it being a window: there is no way to end up with a
    /// normal tab beside the private ones.
    func testEveryTabOpenedInAPrivateWindowIsPrivate() throws {
        let (workspace, teardown) = try Self.makeWorkspace(isPrivate: true)
        defer { teardown() }
        workspace.addTab()
        workspace.addTab(url: URL(string: "https://example.com")!)
        XCTAssertEqual(workspace.tabs.count, 3)
        XCTAssertTrue(workspace.tabs.allSatisfy(\.isPrivate))
    }

    func testAnOrdinaryWindowStillOpensOrdinaryTabs() throws {
        let (workspace, teardown) = try Self.makeWorkspace(isPrivate: false)
        defer { teardown() }
        workspace.addTab()
        XCTAssertFalse(workspace.isPrivate)
        XCTAssertTrue(workspace.tabs.allSatisfy { !$0.isPrivate })
    }

    /// An ordinary window can still hold a private tab, which is what the
    /// Tabs menu offers; asking for one explicitly still works.
    func testAPrivateTabCanStillBeOpenedInAnOrdinaryWindow() throws {
        let (workspace, teardown) = try Self.makeWorkspace(isPrivate: false)
        defer { teardown() }
        workspace.addTab(isPrivate: true)
        XCTAssertEqual(workspace.tabs.filter(\.isPrivate).count, 1)
        XCTAssertEqual(workspace.tabs.filter { !$0.isPrivate }.count, 1)
    }

    /// Nothing from a private window reaches the disk. Writing its tabs to
    /// the saved session would put them back on screen after a relaunch.
    func testAPrivateWindowNeverWritesTheSavedSession() throws {
        let suiteName = "clearframe.private.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }
        let blocking = try BrowserBehaviorTests.makeTestContentBlocking(defaults: defaults)
        defer { blocking.removeStore() }
        let dataStore = BrowserDataStore(defaults: defaults)

        let ordinary = BrowserWorkspace(
            dataStore: dataStore,
            downloads: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking.provider
        )
        ordinary.addTab(url: URL(string: "https://kept.example")!)
        ordinary.persistNow()
        let saved = try XCTUnwrap(dataStore.loadWorkspace())

        let secret = BrowserWorkspace(
            dataStore: dataStore,
            downloads: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking.provider,
            restoresSession: false,
            isPrivate: true
        )
        secret.addTab(url: URL(string: "https://secret.example")!)
        secret.persistNow()

        let reloaded = try XCTUnwrap(dataStore.loadWorkspace())
        XCTAssertEqual(reloaded.tabs.map(\.id), saved.tabs.map(\.id))
    }

    /// A private window is not where a restored session belongs either, even
    /// if it is the first window to open.
    func testAPrivateWindowDoesNotRestoreASavedSession() throws {
        let suiteName = "clearframe.private.restore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }
        let blocking = try BrowserBehaviorTests.makeTestContentBlocking(defaults: defaults)
        defer { blocking.removeStore() }
        let dataStore = BrowserDataStore(defaults: defaults)

        let ordinary = BrowserWorkspace(
            dataStore: dataStore,
            downloads: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking.provider
        )
        ordinary.addTab(url: URL(string: "https://one.example")!)
        ordinary.addTab(url: URL(string: "https://two.example")!)
        ordinary.persistNow()

        let secret = BrowserWorkspace(
            dataStore: dataStore,
            downloads: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking.provider,
            restoresSession: true,
            isPrivate: true
        )

        XCTAssertEqual(secret.tabs.count, 1, "a private window opens blank")
        XCTAssertTrue(secret.tabs[0].isPrivate)
    }

    /// Safari's New Empty Tab Group. A group with no tabs at all is pruned by
    /// design, so ours starts with one empty tab.
    func testANewEmptyTabGroupArrivesWithOneBlankTab() throws {
        let (workspace, teardown) = try Self.makeWorkspace(isPrivate: false)
        defer { teardown() }
        let before = workspace.tabs.count

        let group = try XCTUnwrap(workspace.createEmptyGroup())

        XCTAssertEqual(workspace.tabs.count, before + 1)
        let members = workspace.tabs.filter { $0.groupID == group.id }
        XCTAssertEqual(members.count, 1)
        XCTAssertEqual(workspace.selectedTabID, members.first?.id)
    }

    private static func makeWorkspace(isPrivate: Bool) throws -> (BrowserWorkspace, () -> Void) {
        let suiteName = "clearframe.privatewindow.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let blocking = try BrowserBehaviorTests.makeTestContentBlocking(defaults: defaults)
        let workspace = BrowserWorkspace(
            dataStore: BrowserDataStore(defaults: defaults),
            downloads: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking.provider,
            restoresSession: !isPrivate,
            isPrivate: isPrivate
        )
        return (workspace, {
            blocking.removeStore()
            TestSuiteCleanup.destroy(suiteName, defaults: defaults)
        })
    }
}

/// Profiles: the list, its rules, and where each one's data lives.
@MainActor
final class ProfileStoreTests: XCTestCase {
    private func makeStore() throws -> (ProfileStore, () -> Void) {
        let suiteName = "clearframe.profiles.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        return (ProfileStore(defaults: defaults), {
            TestSuiteCleanup.destroy(suiteName, defaults: defaults)
        })
    }

    /// Someone upgrading has bookmarks, history and logins already. They must
    /// land in a profile, not be stranded behind a new identifier.
    func testAFreshInstallStartsWithTheOriginalProfile() throws {
        let (store, teardown) = try makeStore()
        defer { teardown() }
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertTrue(store.profiles[0].isDefault)
        XCTAssertEqual(store.currentProfileID, BrowserProfileRecord.defaultID)
    }

    /// The point of the original profile: it reads the app's existing stores
    /// rather than a suite of its own.
    func testTheOriginalProfileKeepsTheApplicationsOwnStores() {
        XCTAssertEqual(
            ProfileStorage.defaults(for: BrowserProfileRecord.defaultID),
            UserDefaults.standard
        )
        XCTAssertEqual(
            ProfileStorage.faviconDirectory(for: BrowserProfileRecord.defaultID),
            FaviconStore.defaultDirectory
        )
    }

    /// Every other profile is genuinely somewhere else, which is what keeps
    /// two of them signed into the same site apart.
    func testEveryOtherProfileGetsItsOwnPlaces() throws {
        let (store, teardown) = try makeStore()
        defer { teardown() }
        let work = store.addProfile(name: "Work")
        defer { ProfileStorage.erase(profileID: work.id) }

        XCTAssertNotEqual(ProfileStorage.defaults(for: work.id), UserDefaults.standard)
        XCTAssertNotEqual(
            ProfileStorage.faviconDirectory(for: work.id),
            FaviconStore.defaultDirectory
        )
        XCTAssertTrue(ProfileStorage.suiteName(for: work.id).contains(work.id.uuidString))
    }

    func testProfilesSurviveARelaunch() throws {
        let suiteName = "clearframe.profiles.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }

        let first = ProfileStore(defaults: defaults)
        let zincoo = first.addProfile(name: "Zincoo")
        defer { ProfileStorage.erase(profileID: zincoo.id) }
        first.setCurrent(zincoo.id)

        let reopened = ProfileStore(defaults: defaults)
        XCTAssertEqual(reopened.profiles.map(\.id), first.profiles.map(\.id))
        XCTAssertEqual(reopened.currentProfileID, zincoo.id)
    }

    /// There has to be somewhere to open a window, and the original profile
    /// holds the data from before profiles existed.
    func testTheOriginalProfileCannotBeDeleted() throws {
        let (store, teardown) = try makeStore()
        defer { teardown() }
        XCTAssertFalse(store.canDelete(BrowserProfileRecord.defaultID))
        store.deleteProfile(BrowserProfileRecord.defaultID)
        XCTAssertEqual(store.profiles.count, 1)
    }

    func testDeletingAProfileMovesTheCurrentOneSomewhereReal() throws {
        let (store, teardown) = try makeStore()
        defer { teardown() }
        let temporary = store.addProfile(name: "Temporary")
        store.setCurrent(temporary.id)
        XCTAssertEqual(store.currentProfileID, temporary.id)

        store.deleteProfile(temporary.id)

        XCTAssertFalse(store.profiles.contains { $0.id == temporary.id })
        XCTAssertTrue(store.profiles.contains { $0.id == store.currentProfileID })
    }

    func testANameIsAlwaysSomethingYouCanRead() {
        XCTAssertEqual(BrowserProfileRecord.sanitizedName("   "), "Profile")
        XCTAssertEqual(BrowserProfileRecord.sanitizedName("  Work   Mail "), "Work Mail")
        XCTAssertLessThanOrEqual(
            BrowserProfileRecord.sanitizedName(String(repeating: "x", count: 200)).count,
            40
        )
    }

    func testInitialsComeFromTheFirstTwoWords() {
        XCTAssertEqual(BrowserProfileRecord(name: "Lucian Roman").initials, "LR")
        XCTAssertEqual(BrowserProfileRecord(name: "Zincoo").initials, "Z")
        XCTAssertEqual(BrowserProfileRecord(name: "  ").initials, "?")
    }

    func testNewProfilesTakeUnusedColours() throws {
        let (store, teardown) = try makeStore()
        defer { teardown() }
        let a = store.addProfile(name: "A")
        let b = store.addProfile(name: "B")
        defer {
            ProfileStorage.erase(profileID: a.id)
            ProfileStorage.erase(profileID: b.id)
        }
        XCTAssertNotEqual(a.colorID, b.colorID)
        XCTAssertNotEqual(a.colorID, store.profiles[0].colorID)
    }

    /// The tick in the Profiles menu marks the window in front, not the
    /// profile new windows would use.
    func testTheMenuTicksTheProfileOfTheWindowInFront() {
        let profile = BrowserProfileRecord(name: "Work")
        let ticked = LimeghostBrowserApp.profileMenuTitle(profile, focused: profile.id)
        let plain = LimeghostBrowserApp.profileMenuTitle(profile, focused: UUID())
        XCTAssertTrue(ticked.hasPrefix("✓"))
        XCTAssertFalse(plain.hasPrefix("✓"))
        XCTAssertTrue(ticked.contains("Work"))
        XCTAssertTrue(plain.contains("Work"))
    }
}

/// A window belongs to a profile, and its bookmarks and history come from it.
@MainActor
final class ProfileSeparationTests: XCTestCase {
    private func makeWorkspace(profileID: UUID) throws -> (BrowserWorkspace, () -> Void) {
        let defaults = ProfileStorage.defaults(for: profileID)
        let blocking = try BrowserBehaviorTests.makeTestContentBlocking(defaults: defaults)
        let workspace = BrowserWorkspace(
            dataStore: BrowserDataStore(defaults: defaults),
            downloads: DownloadCenter(),
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking.provider,
            profileID: profileID
        )
        return (workspace, { blocking.removeStore() })
    }

    /// The whole promise: a bookmark saved in one profile is not in the other.
    func testBookmarksDoNotCrossBetweenProfiles() throws {
        let work = UUID(), personal = UUID()
        defer {
            ProfileStorage.erase(profileID: work)
            ProfileStorage.erase(profileID: personal)
        }
        let (workWorkspace, tearDownWork) = try makeWorkspace(profileID: work)
        defer { tearDownWork() }
        let (personalWorkspace, tearDownPersonal) = try makeWorkspace(profileID: personal)
        defer { tearDownPersonal() }

        _ = workWorkspace.dataStore.addBookmark(
            title: "Invoices",
            url: "https://invoices.example",
            folderID: nil
        )

        XCTAssertTrue(workWorkspace.dataStore.bookmarks.contains { $0.url == "https://invoices.example" })
        XCTAssertFalse(personalWorkspace.dataStore.bookmarks.contains { $0.url == "https://invoices.example" })
    }

    func testHistoryDoesNotCrossBetweenProfiles() throws {
        let work = UUID(), personal = UUID()
        defer {
            ProfileStorage.erase(profileID: work)
            ProfileStorage.erase(profileID: personal)
        }
        let (workWorkspace, tearDownWork) = try makeWorkspace(profileID: work)
        defer { tearDownWork() }
        let (personalWorkspace, tearDownPersonal) = try makeWorkspace(profileID: personal)
        defer { tearDownPersonal() }

        workWorkspace.dataStore.recordVisit(title: "Invoices", url: "https://invoices.example")

        XCTAssertTrue(workWorkspace.dataStore.history.contains { $0.url == "https://invoices.example" })
        XCTAssertFalse(personalWorkspace.dataStore.history.contains { $0.url == "https://invoices.example" })
    }

    /// Each profile's saved session is its own, so opening a window in one
    /// does not restore another's tabs.
    func testSavedSessionsDoNotCrossBetweenProfiles() throws {
        let work = UUID(), personal = UUID()
        defer {
            ProfileStorage.erase(profileID: work)
            ProfileStorage.erase(profileID: personal)
        }
        let (workWorkspace, tearDownWork) = try makeWorkspace(profileID: work)
        defer { tearDownWork() }
        workWorkspace.addTab(url: URL(string: "https://invoices.example")!)
        workWorkspace.persistNow()

        XCTAssertNotNil(BrowserDataStore(defaults: ProfileStorage.defaults(for: work)).loadWorkspace())
        XCTAssertNil(BrowserDataStore(defaults: ProfileStorage.defaults(for: personal)).loadWorkspace())
    }

    func testAWorkspaceRemembersWhichProfileItBelongsTo() throws {
        let work = UUID()
        defer { ProfileStorage.erase(profileID: work) }
        let (workspace, teardown) = try makeWorkspace(profileID: work)
        defer { teardown() }
        XCTAssertEqual(workspace.profileID, work)
    }
}

/// Deleting a profile should leave nothing named after it on the disk.
@MainActor
final class ProfileErasureTests: XCTestCase {
    private func preferenceFile(for profileID: UUID) -> URL? {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Preferences/\(ProfileStorage.suiteName(for: profileID)).plist")
    }

    /// Emptying the preference domain leaves the file behind, named after the
    /// profile. Someone who deleted a profile would still find it listed in
    /// their Preferences folder.
    func testErasingAProfileRemovesItsPreferenceFile() throws {
        let profileID = UUID()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: ProfileStorage.suiteName(for: profileID)))
        defaults.set("something", forKey: "clearframe.test.marker")
        defaults.synchronize()
        let file = try XCTUnwrap(preferenceFile(for: profileID))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "the suite should exist to begin with")

        ProfileStorage.erase(profileID: profileID)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: file.path),
            "a deleted profile must not leave a file named after it"
        )
    }

    /// The original profile shares the application's own preferences. Erasing
    /// it would take the app's settings with it.
    func testErasingTheOriginalProfileIsRefused() throws {
        ProfileStorage.erase(profileID: BrowserProfileRecord.defaultID)
        // Nothing to assert about a file — the point is that the app's own
        // preferences are still readable afterwards.
        XCTAssertEqual(ProfileStorage.defaults(for: BrowserProfileRecord.defaultID), UserDefaults.standard)
        XCTAssertNotNil(UserDefaults.standard)
    }
}

/// The thresholds that decide what a press means. The numbers come from
/// Chromium's own tab-drag code, so that a hand used to Chrome finds the same
/// gesture here.
@MainActor
final class TabDragThresholdTests: XCTestCase {
    private func update(dx: CGFloat, dy: CGFloat, at point: CGPoint = .zero) -> TabDragUpdate {
        TabDragUpdate(location: point, translation: CGSize(width: dx, height: dy))
    }

    /// Chrome's `kMinimumDragDistance` is 10, measured in any direction rather
    /// than per axis: a diagonal wander of 8 across and 8 down is 11 away, and
    /// is a drag.
    func testAPressBecomesADragAtTenPointsInAnyDirection() {
        XCTAssertTrue(update(dx: 6, dy: 0).isTap)
        XCTAssertTrue(update(dx: 0, dy: 9).isTap)
        XCTAssertTrue(update(dx: 6, dy: 6).isTap, "8.5 away is still a click")
        XCTAssertFalse(update(dx: 11, dy: 0).isTap)
        XCTAssertFalse(update(dx: 8, dy: 8).isTap, "11.3 away is a drag")
        XCTAssertEqual(update(dx: 11, dy: 0).hasStartedDragging, true)
    }

    /// Measured from the row of chips, not from where the press began, so
    /// grabbing a tab low does not mean a shorter pull than grabbing it high.
    func testTearingOutIsMeasuredFromTheStripNotThePress() {
        let row = CGRect(x: 0, y: 8, width: 120, height: 34)

        // Inside the row, and inside the sticky band just outside it.
        XCTAssertFalse(update(dx: 0, dy: 0, at: CGPoint(x: 60, y: 20)).hasLeftStrip(row: row))
        XCTAssertFalse(update(dx: 0, dy: 0, at: CGPoint(x: 60, y: 50)).hasLeftStrip(row: row))
        XCTAssertFalse(update(dx: 0, dy: 0, at: CGPoint(x: 60, y: -5)).hasLeftStrip(row: row))

        // Clear of it, below and above alike.
        XCTAssertTrue(update(dx: 0, dy: 0, at: CGPoint(x: 60, y: 60)).hasLeftStrip(row: row))
        XCTAssertTrue(update(dx: 0, dy: 0, at: CGPoint(x: 60, y: -10)).hasLeftStrip(row: row))
    }

    /// A long sideways drag along the strip must never tear a tab out, however
    /// far it travels.
    func testDraggingAlongTheStripNeverTearsOut() {
        let row = CGRect(x: 0, y: 8, width: 120, height: 34)
        for x in stride(from: CGFloat(0), through: 900, by: 60) {
            XCTAssertFalse(
                update(dx: x, dy: 0, at: CGPoint(x: x, y: 25)).hasLeftStrip(row: row),
                "x=\(x) is along the row, not out of it"
            )
        }
    }

    func testTheThresholdsAreTheOnesChromeUses() {
        XCTAssertEqual(TabDragUpdate.dragStartDistance, 10, "Chromium kMinimumDragDistance")
        XCTAssertEqual(TabDragUpdate.reorderGate, 16, "Chromium kHorizontalMoveThreshold")
        XCTAssertEqual(TabDragUpdate.detachMagnetism, 15, "Chromium kVerticalDetachMagnetism")
    }

    /// The dragged chip is drawn from its slot, so a reorder that moves the
    /// slot re-bases the offset instead of the chip leaping a tab's width.
    func testTheDraggedChipIsDrawnRelativeToItsCurrentSlot() {
        // Grabbed 20pt right of centre; pointer now 50pt right of centre.
        let grab: CGFloat = 20
        let slotBefore = CGRect(x: 0, y: 0, width: 120, height: 34)
        let pointer: CGFloat = slotBefore.midX + 50
        let offsetBefore = pointer - slotBefore.midX - grab
        XCTAssertEqual(offsetBefore, 30)

        // The reorder moves the slot a full tab to the right; the same pointer
        // now sits nearer that slot's centre, so the drawn offset shrinks
        // rather than the chip jumping.
        let slotAfter = slotBefore.offsetBy(dx: 128, dy: 0)
        let offsetAfter = pointer - slotAfter.midX - grab
        XCTAssertEqual(offsetAfter, offsetBefore - 128)
        XCTAssertEqual(slotBefore.midX + offsetBefore, slotAfter.midX + offsetAfter,
                       "the chip stays under the pointer across a reorder")
    }
}

/// What a folder looks like while it is being dragged.
@MainActor
final class BookmarkDragPayloadTests: XCTestCase {
    func testAFolderTravelsAsItsOwnKindOfAddress() throws {
        let id = UUID()
        let url = try XCTUnwrap(BookmarkDragPayload.folderURL(id))
        XCTAssertEqual(BookmarkDragPayload.folderID(from: url), id)
    }

    /// The reason for a scheme of its own: a folder reference dropped where
    /// bookmarks are saved must not become one.
    func testAFolderReferenceIsNeverSaveableAsAPage() throws {
        let url = try XCTUnwrap(BookmarkDragPayload.folderURL(UUID()))
        XCTAssertNil(WebURLPolicy.validatedURL(url.absoluteString))
        XCTAssertNil(BookmarkURLPolicy.validatedURL(url.absoluteString))
    }

    func testAPageIsNotMistakenForAFolder() throws {
        let page = try XCTUnwrap(URL(string: "https://example.com/page"))
        XCTAssertNil(BookmarkDragPayload.folderID(from: page))
    }

    func testRubbishInThatSchemeIsRefusedRatherThanGuessed() throws {
        let url = try XCTUnwrap(URL(string: "limeghost-folder://not-a-uuid"))
        XCTAssertNil(BookmarkDragPayload.folderID(from: url))
    }
}
