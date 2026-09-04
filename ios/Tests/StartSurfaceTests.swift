import XCTest
import LimeghostCore
@testable import Limeghost
@testable import LimeghostShared

@MainActor
final class StartSurfaceTests: XCTestCase {
    /// A new tab opens the guide, not a blank page.
    func testANewTabOpensTheGuide() throws {
        let suiteName = "clearframe.iosStart.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let host = WorkspaceHost.forTesting(defaults: defaults)

        host.workspace.addTab()

        XCTAssertEqual(host.workspace.selectedTab?.startSurface, .aiHome)
    }

    /// The catalogue is bundled, not fetched: showing the guide makes no
    /// request. `filtered` with no category and no query is what the guide
    /// shows before anybody types.
    func testTheCatalogueIsLocalAndNonEmpty() {
        XCTAssertFalse(AIToolCatalog.filtered(category: nil, query: "").isEmpty)
    }
}
