import Foundation
import XCTest
@testable import LimeghostCore

/// The search filters both platforms share: the Mac's bookmarks and history
/// homes, and the phone's Bookmarks and History sheets. Moved here from
/// `BrowserBehaviorTests` with the filters themselves on September 13, 2026,
/// so they run on the simulator as well as the Mac.
final class BookmarkAndHistorySearchTests: XCTestCase {
    func testHistoryHomeSearchMatchesTitlesAndAddresses() {
        let visits = [
            HistoryRecord(title: "Garlic Chilli", url: "https://recipes.example/garlic"),
            HistoryRecord(title: "Swift Forums", url: "https://forums.swift.org/thread"),
            HistoryRecord(title: "", url: "https://example.com/untitled")
        ]

        XCTAssertEqual(HistoryHomeSearch.visits(visits, matching: "").count, 3, "an empty query keeps everything")
        XCTAssertEqual(HistoryHomeSearch.visits(visits, matching: "   ").count, 3, "so does whitespace")
        XCTAssertEqual(HistoryHomeSearch.visits(visits, matching: "garlic").map(\.title), ["Garlic Chilli"])
        XCTAssertEqual(
            HistoryHomeSearch.visits(visits, matching: "SWIFT.ORG").map(\.title), ["Swift Forums"],
            "the address matches too, case-insensitively"
        )
        XCTAssertEqual(HistoryHomeSearch.visits(visits, matching: "untitled").count, 1, "a visit with no title is still findable")
        XCTAssertTrue(HistoryHomeSearch.visits(visits, matching: "nothing here").isEmpty)
    }

    func testBookmarksHomeSearchMatchesFolderTitlesAndBookmarkTitlesOrAddresses() {
        let folders = [
            BookmarkFolderRecord(title: "Web Design", emoji: "🎨"),
            BookmarkFolderRecord(title: "Programming", emoji: "💻"),
            BookmarkFolderRecord(title: "Shopping", emoji: "🛍️")
        ]
        let bookmarks = [
            BookmarkRecord(title: "Swift documentation", url: "https://swift.org/documentation/"),
            BookmarkRecord(title: "Colour palettes", url: "https://example.com/palette")
        ]

        XCTAssertEqual(BookmarksHomeSearch.folders(folders, matching: "desi").map(\.title), ["Web Design"])
        XCTAssertEqual(BookmarksHomeSearch.folders(folders, matching: "PROGRAM").map(\.title), ["Programming"])
        XCTAssertTrue(BookmarksHomeSearch.folders(folders, matching: "photography").isEmpty)
        XCTAssertEqual(
            BookmarksHomeSearch.folders(folders, matching: "   ").count,
            folders.count,
            "a blank query filters nothing out"
        )

        XCTAssertEqual(BookmarksHomeSearch.bookmarks(bookmarks, matching: "SWIFT").map(\.title), ["Swift documentation"])
        XCTAssertEqual(
            BookmarksHomeSearch.bookmarks(bookmarks, matching: "example.com").map(\.title),
            ["Colour palettes"],
            "the web address matches as well as the title"
        )
        XCTAssertTrue(BookmarksHomeSearch.bookmarks(bookmarks, matching: "no such page").isEmpty)
        XCTAssertEqual(BookmarksHomeSearch.bookmarks(bookmarks, matching: "").count, bookmarks.count)
    }
}
