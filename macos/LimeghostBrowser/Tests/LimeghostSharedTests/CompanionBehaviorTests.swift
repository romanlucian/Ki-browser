import LimeghostCore
@testable import LimeghostShared
import Foundation
import WebKit
import XCTest

/// Removing a test's preference suite as thoroughly as a test process can.
///
/// Moved here with the tests that use it, from `BrowserBehaviorTests.swift`.
/// The original stays in that file too -- roughly fifty *other* tests still
/// there call it, so deleting it out from under them was never on the table;
/// only the tests this file names actually moved.
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

/// `BrowserDataStore` recovery, `BrowserSession` construction and popup
/// wiring, and the assistant's layout doors -- moved here from
/// `BrowserBehaviorTests` because every subject under test now lives in
/// `LimeghostShared`. Uses the `NoDownloads`/`NoPageSharing`/`NoClipboard`
/// stubs from `WorkspaceDoorTests.swift` and the `RecordingPlatform` from
/// `BrowserSessionPlatformTests.swift` -- same target, so no need to define
/// them again -- in place of the real macOS collaborators
/// (`DownloadCenter`/`PageFileCommands`/`MacClipboard`/`MacSessionPlatform`)
/// the original tests used.
///
/// Two tests that share a name pattern with these did **not** move, on
/// purpose:
///
/// - `testASessionAnswersWebKitsOpenPanelRequest` asserts a selector that is
///   answered by `extension BrowserSession` in the app target
///   (`MacSessionPlatform.swift`), not by anything in `LimeghostShared`. This
///   target never imports `LimeghostBrowser`, so the assertion would test
///   nothing if it moved. It stays a Mac test because what it tests is
///   Mac-only.
/// - `testBrowserSessionRegistersItsWebViewWithTheContentBlockerUntilTeardown`
///   belongs to the content-blocking cluster further down
///   `BrowserBehaviorTests.swift`; Task 9 did not touch content blocking.
@MainActor
final class CompanionBehaviorTests: XCTestCase {
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
            platform: RecordingPlatform(),
            downloadCenter: NoDownloads(),
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
            platform: RecordingPlatform(),
            downloadCenter: NoDownloads(),
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
            platform: RecordingPlatform(),
            downloadCenter: NoDownloads(),
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
            downloads: NoDownloads(),
            pageSharing: NoPageSharing.self,
            clipboard: NoClipboard(),
            makeSessionPlatform: { RecordingPlatform() },
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
            downloads: NoDownloads(),
            pageSharing: NoPageSharing.self,
            clipboard: NoClipboard(),
            makeSessionPlatform: { RecordingPlatform() },
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking.provider
        )
        let opener = try XCTUnwrap(workspace.selectedTab)

        opener.session.onRequestNewTab?(nil)

        XCTAssertEqual(workspace.tabs.count, 2)
        XCTAssertEqual(workspace.selectedTab?.session.loadState, .startPage)
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

    private func makeSurfaceTestWorkspace() throws -> BrowserWorkspace {
        let suiteName = "clearframe.companionSurface.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }
        let blocking = try Self.makeTestContentBlocking(defaults: defaults)
        addTeardownBlock { blocking.removeStore() }
        return BrowserWorkspace(
            dataStore: BrowserDataStore(defaults: defaults),
            downloads: NoDownloads(),
            pageSharing: NoPageSharing.self,
            clipboard: NoClipboard(),
            makeSessionPlatform: { RecordingPlatform() },
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking.provider
        )
    }

    /// A provider backed by a throwaway rule store and a two-domain list, so
    /// these tests never touch the shared WebKit store or pay for the shipped
    /// list. Mirrors `BrowserBehaviorTests.makeTestContentBlocking` and
    /// `WorkspaceDoorTests.makeTestContentBlocking`.
    private static func makeTestContentBlocking(
        defaults: UserDefaults,
        domains: [String] = ["metrics.example", "tracker.example"]
    ) throws -> TestCompanionContentBlocking {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("limeghost-companion-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store: WKContentRuleListStore? = WKContentRuleListStore(url: directory)
        let ruleStore = try XCTUnwrap(store, "WebKit could not open a rule store in \(directory.path)")
        let provider = ContentRuleListProvider(
            settings: ContentBlockingSettingsStore(defaults: defaults),
            blockList: TrackerBlockList(release: TrackerBlockerCatalog.release, domains: domains),
            ruleStore: ruleStore
        )
        return TestCompanionContentBlocking(provider: provider, directory: directory)
    }
}

@MainActor
private struct TestCompanionContentBlocking {
    let provider: ContentRuleListProvider
    let directory: URL

    func removeStore() {
        try? FileManager.default.removeItem(at: directory)
    }
}
