import XCTest
import LimeghostCore
@testable import Limeghost
@testable import LimeghostShared

@MainActor
final class StartSurfaceTests: XCTestCase {
    /// A suite of its own, emptied afterwards — the same reason
    /// `WorkspaceHostTests.makeHost()` uses one: the workspace persists tabs
    /// and would otherwise inherit a previous run's, in the simulator the
    /// app itself uses, since these tests run inside the app.
    private func makeHost() throws -> WorkspaceHost {
        let suiteName = "clearframe.iosStart.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return WorkspaceHost.forTesting(defaults: defaults)
    }

    // MARK: - The gate (`showsGuide`)

    /// The ordinary state of a fresh tab: still on its start page, still the
    /// AI home. This is what `WorkspaceHostTests.testTheAppOpensOnTheAIGuide`
    /// already covers at the model level (`startSurface == .aiHome`); this
    /// asserts the *gate* agrees, which is a different claim once `loadState`
    /// is part of the decision.
    func testTheGateShowsTheGuideOnAFreshStartPage() {
        XCTAssertTrue(showsGuide(loadState: .startPage, startSurface: .aiHome))
    }

    /// The case nothing else guards. `startSurface` is never reset once a
    /// real page loads — iOS has no Home button and no bookmarks or history
    /// home yet to reset it — so a tab can easily be `.content` while
    /// `startSurface` is still `.aiHome`. If the gate read `startSurface`
    /// alone, a tab opened straight to a URL would show the guide instead of
    /// the page just asked for — which is the rule in `CLAUDE.md` that asking
    /// for a page uncovers the page, broken on the surface built to honour it.
    /// Nothing guarded this before.
    func testTheGateHidesTheGuideOnceAPageIsLoaded() {
        XCTAssertFalse(showsGuide(loadState: .content, startSurface: .aiHome))
    }

    // MARK: - The gate, wired to a real tab

    /// The gate is only half the claim; the other half is which object each
    /// side of it is read from. A fresh tab out of the workspace shows the
    /// guide.
    func testAFreshTabsSurfaceShowsTheGuide() throws {
        let host = try makeHost()
        let tab = try XCTUnwrap(host.workspace.selectedTab)

        let surface = TabSurface(tab: tab, workspace: host.workspace)

        XCTAssertTrue(surface.showsTheGuide)
    }

    /// And the same tab, once somebody has asked for a page, does not — with
    /// `startSurface` still `.aiHome` underneath, which is exactly the state
    /// that makes reading it alone wrong. Goes through the real door rather
    /// than setting a load state by hand, so it is the shipped path being
    /// judged.
    func testAskingForAPageUncoversItRatherThanTheGuide() throws {
        let host = try makeHost()
        let tab = try XCTUnwrap(host.workspace.selectedTab)

        host.workspace.open("https://example.com/")

        XCTAssertEqual(tab.startSurface, .aiHome)
        XCTAssertFalse(TabSurface(tab: tab, workspace: host.workspace).showsTheGuide)
    }

    // MARK: - The doors (`StartSurfaceScreen.openTool`/`openSource`)

    /// Opening a tool loads its official URL, synchronously, in the current
    /// tab — the same pattern
    /// `WorkspaceHostTests.testOpeningAnAddressAddsATabThroughTheWorkspace`
    /// already uses to prove a door actually reached the tab rather than
    /// merely returning without effect. The inline closure this replaced was
    /// invisible to any test: emptied out, the suite stayed green.
    func testOpeningAToolLoadsItsURL() throws {
        let host = try makeHost()
        let screen = StartSurfaceScreen(workspace: host.workspace)
        let tool = try XCTUnwrap(AIToolCatalog.tools.first)

        screen.openTool(tool)

        XCTAssertEqual(host.workspace.selectedTab?.session.currentURLString, tool.officialURL.absoluteString)
    }

    /// Opening a tool is also what puts it on the reader's row. Without this
    /// the phone shipped a row that could never change: `AIToolStartPage`'s
    /// `shelfTools` stays empty unless something is recorded, so the guide
    /// reads "GOOD PLACES TO START" forever instead of "YOUR TOOLS", and
    /// pin/remove (`canManage`, gated on that same emptiness) stays dead.
    func testOpeningAToolRecordsItOnTheShelf() throws {
        let host = try makeHost()
        let screen = StartSurfaceScreen(workspace: host.workspace)
        let tool = try XCTUnwrap(AIToolCatalog.tools.first)

        screen.openTool(tool)

        XCTAssertTrue(host.workspace.dataStore.aiToolShelf.toolIDs.contains(tool.id))
    }

    /// A recommendation's official source link loads too, in the current tab.
    func testOpeningASourceLoadsItsURL() throws {
        let host = try makeHost()
        let screen = StartSurfaceScreen(workspace: host.workspace)
        let tool = try XCTUnwrap(AIToolCatalog.tools.first)
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/source"))

        screen.openSource(tool, sourceURL)

        XCTAssertEqual(host.workspace.selectedTab?.session.currentURLString, sourceURL.absoluteString)
    }

    /// Unlike opening the tool itself, opening its source link is not what
    /// the Mac records to the shelf either — a source page is context for a
    /// recommendation, not a tool somebody chose to open. Locks in the
    /// asymmetry `openTool`/`openSource` deliberately keep.
    func testOpeningASourceDoesNotJoinTheShelf() throws {
        let host = try makeHost()
        let screen = StartSurfaceScreen(workspace: host.workspace)
        let tool = try XCTUnwrap(AIToolCatalog.tools.first)
        let sourceURL = try XCTUnwrap(URL(string: "https://example.com/source"))

        screen.openSource(tool, sourceURL)

        XCTAssertFalse(host.workspace.dataStore.aiToolShelf.toolIDs.contains(tool.id))
    }

    // MARK: - The catalogue

    /// The catalogue is bundled, not fetched: showing the guide makes no
    /// request.
    ///
    /// This is deliberately *not* described as what the guide shows before
    /// anybody types, which an earlier version of this comment claimed. It
    /// isn't: `AIToolStartPage.visibleTools` returns `[]` until a category is
    /// picked or something is typed, so the fresh guide shows no cards at all
    /// beyond its own shelf row. The narrower claim is the true one and still
    /// worth holding — every tool `filtered` could ever surface is local.
    func testTheCatalogueIsLocalAndNonEmpty() {
        XCTAssertFalse(AIToolCatalog.filtered(category: nil, query: "").isEmpty)
    }
}
