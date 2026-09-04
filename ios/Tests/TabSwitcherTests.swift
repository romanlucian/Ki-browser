import XCTest
@testable import Limeghost
@testable import LimeghostShared

@MainActor
final class TabSwitcherTests: XCTestCase {
    private func makeHost() throws -> WorkspaceHost {
        let suiteName = "clearframe.iosTabs.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return WorkspaceHost.forTesting(defaults: defaults)
    }

    /// Private tabs are their own section. They are ephemeral and excluded from
    /// history; one list would blur a line the product draws on purpose.
    func testPrivateTabsAreTheirOwnSection() throws {
        let host = try makeHost()
        host.workspace.addTab(url: URL(string: "https://example.com/")!, isPrivate: false)
        host.workspace.addTab(url: URL(string: "https://example.org/")!, isPrivate: true)

        let model = TabSwitcherModel(workspace: host.workspace)

        XCTAssertTrue(model.rows.allSatisfy { !$0.isPrivate })
        XCTAssertEqual(model.privateRows.count, 1)
    }

    /// Closing every tab must not leave an empty browser with nothing to tap.
    /// `closeTab` makes a replacement when the last one goes.
    func testClosingEveryTabLeavesOneToLookAt() throws {
        let host = try makeHost()
        for tab in host.workspace.visibleTabs { host.workspace.closeTab(tab.id) }

        XCTAssertFalse(host.workspace.visibleTabs.isEmpty)
    }

    /// A closed tab can come back.
    func testAClosedTabCanBeReopened() throws {
        let host = try makeHost()
        host.workspace.addTab(url: URL(string: "https://example.com/")!)
        let id = try XCTUnwrap(host.workspace.selectedTabID)
        host.workspace.closeTab(id)

        XCTAssertTrue(host.workspace.canReopenClosedTab)
    }
}
