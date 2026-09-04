import XCTest
import LimeghostCore
@testable import Limeghost
@testable import LimeghostShared

@MainActor
final class AddressSheetTests: XCTestCase {
    private func makeHost() throws -> WorkspaceHost {
        let suiteName = "clearframe.iosAddress.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return WorkspaceHost.forTesting(defaults: defaults)
    }

    /// A bare host navigates. `workspace.open` would refuse this — it requires
    /// a scheme — which is why typing goes through `navigate`.
    func testABareHostNavigates() throws {
        let host = try makeHost()
        let model = AddressSheetModel(workspace: host.workspace)

        model.submit("example.com")

        let url = try XCTUnwrap(host.workspace.selectedTab?.session.currentURLString)
        XCTAssertTrue(url.contains("example.com"), url)
    }

    /// Completion offers a search row for anything typed, and nothing else when
    /// this profile has never visited or saved a match. It contacts no
    /// suggestion service and makes no request while typing.
    func testAnUnknownPrefixOffersOnlyTheSearchRow() throws {
        let host = try makeHost()
        let model = AddressSheetModel(workspace: host.workspace)

        let rows = model.suggestions(for: "zzzzznotahost")

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.kind, .search)
    }
}
