import LimeghostCore
@testable import LimeghostShared
import Foundation
import WebKit
import XCTest

/// A private window makes every tab in it private. That promise is only as
/// good as the least-travelled way of making a tab there: closing the last
/// one, opening a file, a link from another app, a reset.
@MainActor
final class PrivateWindowTabsTests: XCTestCase {
    /// ⌘W on the last tab keeps the window open with a fresh tab. In a private
    /// window that fresh tab was built ordinary — persistent cookies and
    /// history, in a window still showing itself as private.
    func testClosingTheLastTabOfAPrivateWindowLeavesAPrivateTab() throws {
        let workspace = try IsolatedWorkspace.make(for: self, isPrivate: true).workspace
        let only = try XCTUnwrap(workspace.selectedTab)
        XCTAssertTrue(only.isPrivate)

        workspace.closeTab(only.id)

        let replacement = try XCTUnwrap(workspace.selectedTab)
        XCTAssertTrue(replacement.isPrivate, "closing the last tab put an ordinary tab in a private window")
        XCTAssertFalse(
            replacement.session.webView.configuration.websiteDataStore.isPersistent,
            "the replacement tab writes cookies to disk"
        )
    }

    /// The ordinary window's behaviour is unchanged: its replacement is ordinary.
    func testClosingTheLastTabOfAnOrdinaryWindowLeavesAnOrdinaryTab() throws {
        let workspace = try IsolatedWorkspace.make(for: self).workspace
        let only = try XCTUnwrap(workspace.selectedTab)

        workspace.closeTab(only.id)

        XCTAssertFalse(try XCTUnwrap(workspace.selectedTab).isPrivate)
    }

    /// Open File… in a private window opened an ordinary tab beside the
    /// private ones, and every link followed from that page was ordinary too.
    func testAFileOpenedInAPrivateWindowIsPrivate() throws {
        let workspace = try IsolatedWorkspace.make(for: self, isPrivate: true).workspace

        workspace.openLocalFile(
            FileManager.default.temporaryDirectory.appendingPathComponent("limeghost-private-\(UUID().uuidString).html")
        )

        XCTAssertTrue(try XCTUnwrap(workspace.selectedTab).isPrivate)
        XCTAssertTrue(workspace.tabs.allSatisfy(\.isPrivate), "a private window holds an ordinary tab")
    }

    /// A link another app hands over lands in the window in front. If that
    /// window is private, the tab must be too.
    func testAnAddressFromAnotherAppOpensPrivatelyInAPrivateWindow() throws {
        let workspace = try IsolatedWorkspace.make(for: self, isPrivate: true).workspace

        workspace.openExternalURL(URL(string: "https://example.com/from-another-app")!)

        XCTAssertTrue(try XCTUnwrap(workspace.selectedTab).isPrivate)
        XCTAssertTrue(workspace.tabs.allSatisfy(\.isPrivate), "a private window holds an ordinary tab")
    }
}
