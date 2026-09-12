import XCTest
@testable import Limeghost
@testable import LimeghostShared

/// What the find bar says, and when its arrows work. WebKit reports whether a
/// match was found and nothing else, so the bar has exactly three things to
/// say, and two of them are nothing.
@MainActor
final class FindBarTests: XCTestCase {
    func testNothingFoundSaysNoResults() {
        XCTAssertEqual(FindBar.outcomeText(.noResults), "No results")
    }

    /// On a match, the page's own highlight is the answer. The bar says
    /// nothing, and above all never a position or a count.
    func testAMatchSaysNothing() {
        XCTAssertNil(FindBar.outcomeText(.matched))
    }

    func testBeforeAnySearchItSaysNothing() {
        XCTAssertNil(FindBar.outcomeText(.idle))
    }

    /// The arrows step between matches, so they wait for one.
    func testTheArrowsWaitForAMatch() {
        XCTAssertTrue(FindBar.canStep(.matched))
        XCTAssertFalse(FindBar.canStep(.noResults))
        XCTAssertFalse(FindBar.canStep(.idle))
    }
}
