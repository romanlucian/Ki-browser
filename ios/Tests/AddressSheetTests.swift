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

    /// Go with nothing typed does nothing, and the guide is still there.
    ///
    /// The sheet's field is always empty when it opens, so this is one stray
    /// tap away at any moment. Without the guard the empty string reaches
    /// `BrowserSession.navigate`, which resolves it to no URL and sets
    /// `.failed` — and `showsGuide` wants `.startPage`, while nothing on the
    /// phone ever resets `startSurface`, so that tab could never show the AI
    /// home again. The first assertion is the load-bearing precondition: the
    /// guide has to be on screen before the submit, or the ones after it would
    /// pass against a tab that was never showing it.
    ///
    /// Whitespace is submitted too, because the guard trims before it decides
    /// and a space is exactly as much of a request as nothing is.
    func testSubmittingAnEmptyFieldLeavesTheGuideAlone() throws {
        let host = try makeHost()
        let tab = try XCTUnwrap(host.workspace.selectedTab)
        let model = AddressSheetModel(workspace: host.workspace)

        XCTAssertTrue(
            TabSurface(tab: tab, workspace: host.workspace).showsTheGuide,
            "the guide has to start on screen, or nothing below proves anything"
        )

        model.submit("")
        XCTAssertTrue(TabSurface(tab: tab, workspace: host.workspace).showsTheGuide)

        model.submit("   ")
        XCTAssertTrue(TabSurface(tab: tab, workspace: host.workspace).showsTheGuide)
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

    /// A private tab is completed from nothing at all.
    ///
    /// Nothing is written in a private tab either way — private visits never
    /// reach history — but reading a saved history back onto the screen would
    /// work against what a private tab is for. The Mac has refused this from
    /// the start (`BrowserView.addressSuggestions`) and
    /// `docs/privacy-and-safety.md` states it as a promise; the phone did not,
    /// from the moment the tab switcher could open a private tab until this
    /// test.
    ///
    /// The prefix is the load-bearing part. It matches a visit this profile
    /// really holds, and the first assertion proves it does, so the empty
    /// result below is the guard refusing rather than a profile with nothing
    /// to offer. Asserting emptiness against a prefix that matches nothing
    /// anyway would pass with the guard deleted.
    func testAPrivateTabIsNeverCompletedFromOrdinaryHistory() throws {
        let host = try makeHost()
        host.workspace.dataStore.recordVisit(title: "Example Domain", url: "https://example.com/")
        let model = AddressSheetModel(workspace: host.workspace)

        let inTheOrdinaryTab = model.suggestions(for: "exam")
        XCTAssertTrue(
            inTheOrdinaryTab.contains { $0.kind != .search },
            "the seeded visit has to be completable here, or the private assertion proves nothing: \(inTheOrdinaryTab)"
        )

        host.workspace.addTab(url: URL(string: "https://example.org/")!, isPrivate: true)
        XCTAssertEqual(host.workspace.selectedTab?.session.isPrivate, true)

        XCTAssertTrue(model.suggestions(for: "exam").isEmpty)
    }
}
