import LimeghostCore
@testable import LimeghostShared
import Combine
import Foundation
import WebKit
import XCTest

/// Nothing to download in a unit test, and downloads are the one collaborator
/// that is still macOS-only. The workspace only needs it to exist.
final class NoDownloads: DownloadTracking {
    func track(_ download: WKDownload, sourceURL: URL?) {}
    let objectWillChange = ObservableObjectPublisher()
    func clearAllRecords() {}
}

/// Nothing to save, export, or share in a door test — none of the thirteen
/// doors touches a page command.
enum NoPageSharing: PageSharing {
    static func savePage(
        named suggestedName: String,
        archivedBy archive: @escaping (@escaping (Result<Data, Error>) -> Void) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {}

    static func exportPDF(
        named suggestedName: String,
        renderedBy render: @escaping (@escaping (Result<Data, Error>) -> Void) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {}

    static func share(_ url: URL) {}
}

/// Nowhere to copy to in a door test.
final class NoClipboard: ClipboardWriting {
    func setString(_ string: String) {}
}

@MainActor
final class WorkspaceDoorTests: XCTestCase {
    /// Every way of asking for a page must uncover the page.
    ///
    /// A table rather than one test each, because the point is coverage: when
    /// somebody adds a fourteenth door and forgets the rule, this is what says
    /// so. Ten of the eleven doors that existed then were broken at once — the
    /// panel stepped aside for ⌘T and for nothing else, so the same request
    /// behaved two ways depending on which button you happened to press.
    ///
    /// The counts in this comment are the mechanism, not decoration: it is the
    /// only place the next author is told to add a row, so a stale number here
    /// quietly stops teaching that. This branch added "a typed address" and
    /// left them saying eleven, and "a local file" had never had a row at all
    /// even though `openLocalFile` has always called `makeRoomForPage()`.
    ///
    /// Moved here from `BrowserBehaviorTests` with `BrowserWorkspace` itself:
    /// the doors are code, not app-target wiring, and the rule they enforce
    /// has to hold on the Simulator too.
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
            ("a typed address", { $0.navigate("example.com") }),
            // The file does not have to exist. `openLocalFile` calls
            // `makeRoomForPage()` before it hands anything to WebKit, and a
            // file load that fails does so asynchronously, long after the
            // assertions below. The path is built from the temporary
            // directory rather than written as a literal so this row means
            // the same thing on the Simulator, where /tmp is not the Mac's.
            ("a local file", {
                $0.openLocalFile(
                    FileManager.default.temporaryDirectory.appendingPathComponent("limeghost-door.html")
                )
            }),
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

    private func makeSurfaceTestWorkspace() throws -> BrowserWorkspace {
        let suiteName = "clearframe.workspaceDoor.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            // Mirrors `BrowserBehaviorTests`' `TestSuiteCleanup`: emptying the
            // domain is what matters for correctness, and removing the file
            // it leaves behind keeps a repeated run from littering
            // ~/Library/Preferences with one plist per test.
            defaults.removePersistentDomain(forName: suiteName)
            if let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
                try? FileManager.default.removeItem(
                    at: library.appendingPathComponent("Preferences/\(suiteName).plist")
                )
            }
        }
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
    /// this test never touches the shared WebKit store or pays for the
    /// shipped list. Mirrors `BrowserBehaviorTests.makeTestContentBlocking`.
    private static func makeTestContentBlocking(
        defaults: UserDefaults,
        domains: [String] = ["metrics.example", "tracker.example"]
    ) throws -> TestDoorContentBlocking {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("limeghost-workspace-door-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store: WKContentRuleListStore? = WKContentRuleListStore(url: directory)
        let ruleStore = try XCTUnwrap(store, "WebKit could not open a rule store in \(directory.path)")
        let provider = ContentRuleListProvider(
            settings: ContentBlockingSettingsStore(defaults: defaults),
            blockList: TrackerBlockList(release: TrackerBlockerCatalog.release, domains: domains),
            ruleStore: ruleStore
        )
        return TestDoorContentBlocking(provider: provider, directory: directory)
    }
}

@MainActor
private struct TestDoorContentBlocking {
    let provider: ContentRuleListProvider
    let directory: URL

    func removeStore() {
        try? FileManager.default.removeItem(at: directory)
    }
}
