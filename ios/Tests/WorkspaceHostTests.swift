import XCTest
@testable import Limeghost
@testable import LimeghostShared

@MainActor
final class WorkspaceHostTests: XCTestCase {
    /// A suite of its own, emptied afterwards. The workspace persists tabs and
    /// restores them, so a test on the standard defaults would inherit the
    /// previous run's tabs and leave its own behind — in the simulator the app
    /// itself uses, because these tests run inside the app.
    private func makeHost() throws -> WorkspaceHost {
        let suiteName = "clearframe.iosHost.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return WorkspaceHost.forTesting(defaults: defaults)
    }

    /// The app opens on the AI guide, not a blank page. The first minute is a
    /// product acceptance criterion, not a default.
    func testTheAppOpensOnTheAIGuide() throws {
        let host = try makeHost()
        let tab = try XCTUnwrap(host.workspace.selectedTab)
        XCTAssertEqual(tab.startSurface, .aiHome)
    }

    /// Opening an address goes through the workspace, which is what makes it a
    /// door. If this ever bypasses the workspace, the rule that asking for a
    /// page uncovers the page stops applying to the phone.
    func testOpeningAnAddressAddsATabThroughTheWorkspace() throws {
        let host = try makeHost()
        let before = host.workspace.visibleTabs.count

        host.workspace.addTab(url: URL(string: "https://example.com/")!)

        XCTAssertEqual(host.workspace.visibleTabs.count, before + 1)
        XCTAssertEqual(host.workspace.selectedTab?.session.currentURLString, "https://example.com/")
    }

    // MARK: - A link from another app

    /// A web link another app hands over — which reaches Limeghost only once
    /// it is the default browser — is a door, like every other way of asking
    /// for a page: a new tab in front, holding that page, with the assistant
    /// out of its way.
    func testALinkFromAnotherAppOpensInANewTabInFront() throws {
        let host = try makeHost()
        host.workspace.aiCompanion.toggle()
        XCTAssertTrue(host.workspace.aiCompanion.isVisible, "the assistant has to be covering the page first")
        let before = host.workspace.tabs.count

        let opened = IncomingLink(workspace: host.workspace).open(try XCTUnwrap(URL(string: "https://example.com/recipes")))

        XCTAssertTrue(opened)
        XCTAssertEqual(host.workspace.tabs.count, before + 1)
        XCTAssertEqual(host.workspace.selectedTab?.session.currentURLString, "https://example.com/recipes")
        XCTAssertFalse(host.workspace.aiCompanion.isVisible, "the assistant still covered the page somebody asked for")
    }

    /// Anything that is not a web page opens nothing, and says so, so the
    /// screen leaves its sheets where they were.
    func testALinkThatIsNotAWebPageOpensNothing() throws {
        let host = try makeHost()
        let before = host.workspace.tabs.count

        XCTAssertFalse(IncomingLink(workspace: host.workspace).open(try XCTUnwrap(URL(string: "file:///private/etc/hosts"))))
        XCTAssertEqual(host.workspace.tabs.count, before)
    }
}
