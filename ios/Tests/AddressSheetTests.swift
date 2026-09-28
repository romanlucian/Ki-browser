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

    // MARK: - The typing screen's three parts

    /// The best place is drawn large at the top, and is not drawn a second
    /// time in the list beneath it. The search row is its own part, never one
    /// of the places.
    func testTheBestPlaceIsTheTopHitAndIsNotRepeatedBelow() throws {
        let host = try makeHost()
        host.workspace.dataStore.recordVisit(title: "Example Domain", url: "https://example.com/")
        host.workspace.dataStore.recordVisit(title: "Example Org", url: "https://example.org/")
        let model = AddressSheetModel(workspace: host.workspace)

        let results = model.results(for: "exam")

        let top = try XCTUnwrap(results.topHit, "a matching visit produced no top hit")
        XCTAssertNotEqual(top.kind, .search)
        XCTAssertFalse(results.places.contains { $0.url == top.url }, "the top hit was listed twice")
        XCTAssertEqual(results.search?.kind, .search)
        XCTAssertFalse(results.places.contains { $0.kind == .search }, "the search row was filed as a place")
        // No new order: the top hit is simply what completion already put first.
        XCTAssertEqual(top, model.suggestions(for: "exam").first { $0.kind != .search })
    }

    /// A place says when it was last visited, which is what lets it read
    /// "visited 2 weeks ago" rather than being a bare address.
    func testAPlaceKnowsWhenItWasLastVisited() throws {
        let host = try makeHost()
        let when = Date(timeIntervalSinceNow: -14 * 24 * 60 * 60)
        host.workspace.dataStore.recordVisit(title: "Example Domain", url: "https://example.com/", at: when)
        let model = AddressSheetModel(workspace: host.workspace)

        let results = model.results(for: "exam")

        let top = try XCTUnwrap(results.topHit)
        let recorded = try XCTUnwrap(results.lastVisits[top.url], "the visit date was lost on the way")
        XCTAssertEqual(recorded.timeIntervalSince1970, when.timeIntervalSince1970, accuracy: 1)
    }

    /// A bookmark nobody has opened has no visit to report, and must not
    /// borrow a date that means nothing — "visited 56 years ago" for a page
    /// saved yesterday.
    func testANeverOpenedBookmarkClaimsNoVisit() throws {
        let host = try makeHost()
        _ = host.workspace.dataStore.addBookmark(title: "Kestrel", url: "https://kestrel.example/", folderID: nil)
        let model = AddressSheetModel(workspace: host.workspace)

        let results = model.results(for: "kestrel")

        let top = try XCTUnwrap(results.topHit, "the bookmark has to be offered, or the assertion below proves nothing")
        XCTAssertNil(results.lastVisits[top.url], "a bookmark never opened claimed a visit")
    }

    /// A private tab shows none of it — no top hit, no places, and not even the
    /// search row, as the sheet has always behaved there.
    func testAPrivateTabShowsNothingAtAll() throws {
        let host = try makeHost()
        host.workspace.dataStore.recordVisit(title: "Example Domain", url: "https://example.com/")
        let model = AddressSheetModel(workspace: host.workspace)
        XCTAssertNotNil(model.results(for: "exam").topHit, "the visit has to be offered in an ordinary tab first")

        host.workspace.addTab(url: URL(string: "https://example.org/")!, isPrivate: true)

        XCTAssertTrue(model.results(for: "exam").isEmpty)
    }

    /// The line under a place says as much as is true and nothing more: the
    /// host without `www.`, "Bookmark" only for a bookmark, "Visited …" only
    /// when there was a visit.
    func testAPlacesDetailSaysOnlyWhatIsTrue() {
        let now = Date()
        // Scheme-less, because that is the form a real suggestion carries —
        // written with `https://` at first, this test passed against the very
        // bug it exists for.
        let visited = AddressSuggestion(kind: .place(isBookmarked: false), title: "Owl", url: "en.wikipedia.org/wiki/Owl")
        let saved = AddressSuggestion(kind: .place(isBookmarked: true), title: "Kestrel", url: "www.kestrel.example/")

        let twoWeeks = AddressSheet.detail(for: visited, lastVisit: now.addingTimeInterval(-14 * 86_400), now: now)
        XCTAssertTrue(twoWeeks.hasPrefix("en.wikipedia.org \u{00B7} Visited "), "the line shows a path, not a host: \(twoWeeks)")
        XCTAssertTrue(twoWeeks.contains("2 weeks ago"), twoWeeks)
        XCTAssertFalse(twoWeeks.contains("Bookmark"), "a visit that is not a bookmark was called one")

        let neverOpened = AddressSheet.detail(for: saved, lastVisit: nil, now: now)
        XCTAssertEqual(neverOpened, "kestrel.example \u{00B7} Bookmark")
    }
}

