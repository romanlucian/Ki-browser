import SwiftUI
import XCTest
@testable import Limeghost
@testable import LimeghostShared

@MainActor
final class PrivacyCoverTests: XCTestCase {
    private func makeHost() throws -> WorkspaceHost {
        let suiteName = "clearframe.privacyCover.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return WorkspaceHost.forTesting(defaults: defaults)
    }

    /// iOS photographs an app for the app switcher as it leaves and keeps the
    /// picture inside the app's own container, so with a private page in front
    /// that photograph was the private page, on disk — the one thing a private
    /// tab promises never happens.
    func testAPrivatePageIsHiddenAsTheAppLeaves() throws {
        let host = try makeHost()
        host.workspace.addTab(url: URL(string: "https://example.org/")!, isPrivate: true)
        let cover = PrivacyCover(workspace: host.workspace)

        XCTAssertTrue(cover.covers(.background))
        // Inactive as well, not only background: the switcher is already
        // showing the app while it is merely inactive.
        XCTAssertTrue(cover.covers(.inactive), "the app switcher would photograph the private page")
        XCTAssertFalse(cover.covers(.active), "a private page was hidden while somebody was reading it")
    }

    /// Only the tab in front decides. A private tab behind an ordinary page
    /// puts nothing private on the screen, and a cover there would hide an
    /// ordinary page for no reason.
    func testAnOrdinaryPageInFrontIsNotHidden() throws {
        let host = try makeHost()
        host.workspace.addTab(url: URL(string: "https://example.org/")!, isPrivate: true)
        host.workspace.addTab(url: URL(string: "https://example.com/")!, isPrivate: false)
        let cover = PrivacyCover(workspace: host.workspace)

        XCTAssertEqual(host.workspace.selectedTab?.isPrivate, false)
        XCTAssertFalse(cover.covers(.inactive), "an ordinary page was hidden for a private tab behind it")
    }
}
