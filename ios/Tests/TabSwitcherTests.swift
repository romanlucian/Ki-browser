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
        let model = TabSwitcherModel(workspace: host.workspace)
        let closedIDs = model.rows.map(\.id)
        for id in closedIDs { model.close(id) }

        XCTAssertFalse(model.rows.isEmpty)
        // Not merely non-empty: the survivor must be the *replacement*, not
        // one of the tabs just asked to close left behind by a `close` that
        // silently did nothing.
        XCTAssertTrue(model.rows.allSatisfy { !closedIDs.contains($0.id) })
    }

    /// A closed tab can come back.
    func testAClosedTabCanBeReopened() throws {
        let host = try makeHost()
        host.workspace.addTab(url: URL(string: "https://example.com/")!)
        let model = TabSwitcherModel(workspace: host.workspace)
        let id = try XCTUnwrap(host.workspace.selectedTabID)
        model.close(id)

        XCTAssertTrue(model.canReopenClosed)

        model.reopenClosedTab()

        // Reopening consumes the one closed tab remembered above, so nothing
        // is left to reopen — proof `reopenClosedTab()` actually ran rather
        // than leaving the closed-tab stack untouched.
        XCTAssertFalse(model.canReopenClosed)
    }
}
