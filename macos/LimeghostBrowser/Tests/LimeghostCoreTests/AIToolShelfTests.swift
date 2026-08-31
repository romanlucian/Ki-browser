import XCTest
@testable import LimeghostCore

final class AIToolShelfTests: XCTestCase {
    func testAToolEarnsAPlaceOnItsFirstOpen() {
        var shelf = AIToolShelf()
        shelf.recordOpen("chatgpt")
        XCTAssertEqual(shelf.toolIDs, ["chatgpt"])
    }

    func testToolsKeepTheSlotTheyWereGiven() {
        var shelf = AIToolShelf()
        for id in ["chatgpt", "midjourney", "gemini"] { shelf.recordOpen(id) }
        // Gemini is now opened far more often than either of the others. The row
        // must not reorder underneath the reader's hand.
        for _ in 0..<20 { shelf.recordOpen("gemini") }
        XCTAssertEqual(shelf.toolIDs, ["chatgpt", "midjourney", "gemini"])
    }

    func testAFullRowIsOnlyTakenFromTheLeastOpenedTool() {
        var shelf = AIToolShelf(capacity: 3)
        shelf.recordOpen("a"); shelf.recordOpen("a"); shelf.recordOpen("a")
        shelf.recordOpen("b"); shelf.recordOpen("b")
        shelf.recordOpen("c")                      // c is the weakest, one open
        shelf.recordOpen("d"); shelf.recordOpen("d")  // two opens beats c's one
        XCTAssertEqual(shelf.toolIDs, ["a", "b", "d"], "the newcomer should take the weakest slot, in place")
    }

    func testAPassingToolDoesNotDisplaceOneStillInUse() {
        var shelf = AIToolShelf(capacity: 2)
        for _ in 0..<5 { shelf.recordOpen("a") }
        for _ in 0..<5 { shelf.recordOpen("b") }
        shelf.recordOpen("c")                      // one open against five
        XCTAssertEqual(shelf.toolIDs, ["a", "b"], "a single visit must not evict a tool in regular use")
    }

    func testAPinnedToolIsNeverDisplaced() {
        var shelf = AIToolShelf(capacity: 2)
        shelf.recordOpen("keep")                   // one open, but pinned
        shelf.pin("keep")
        for _ in 0..<9 { shelf.recordOpen("busy") }
        for _ in 0..<9 { shelf.recordOpen("newcomer") }
        XCTAssertTrue(shelf.toolIDs.contains("keep"), "pinning must outrank the counts")
        XCTAssertTrue(shelf.isPinned("keep"))
    }

    func testPinningAToolNotOnTheRowPutsItThere() {
        var shelf = AIToolShelf(capacity: 2)
        for _ in 0..<3 { shelf.recordOpen("a") }
        for _ in 0..<3 { shelf.recordOpen("b") }
        shelf.pin("wanted")
        XCTAssertTrue(shelf.toolIDs.contains("wanted"))
        XCTAssertEqual(shelf.toolIDs.count, 2)
    }

    func testARemovedToolDoesNotWalkStraightBackOn() {
        var shelf = AIToolShelf()
        for _ in 0..<4 { shelf.recordOpen("unwanted") }
        shelf.remove("unwanted")
        XCTAssertEqual(shelf.toolIDs, [])
        XCTAssertEqual(shelf.openCount(of: "unwanted"), 0, "its history goes with it")
    }

    func testTheRowSurvivesBeingSavedAndRead() throws {
        var shelf = AIToolShelf(capacity: 4)
        shelf.recordOpen("a"); shelf.recordOpen("b")
        shelf.pin("b")
        let restored = try JSONDecoder().decode(
            AIToolShelf.self, from: try JSONEncoder().encode(shelf)
        )
        XCTAssertEqual(restored, shelf)
        XCTAssertEqual(restored.toolIDs, ["a", "b"])
        XCTAssertTrue(restored.isPinned("b"))
    }

    func testAnEmptyIdentifierIsIgnored() {
        var shelf = AIToolShelf()
        shelf.recordOpen("")
        shelf.pin("")
        XCTAssertEqual(shelf.toolIDs, [])
    }
}
