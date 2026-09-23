import LimeghostCore
import XCTest
@testable import LimeghostBrowser

/// Which folder the Bookmark Manager shows once the folder it was showing is
/// gone. Deleting the open folder from its own row, when it held anything,
/// left the page on a folder that no longer existed: the header fell back to
/// "Bookmarks" while the lists filtered by the missing folder and showed
/// nothing — every bookmark one click away, and the page reading as though
/// all of them had been deleted.
final class BookmarksHomeNavigationTests: XCTestCase {
    private let travel = BookmarkFolderRecord(title: "Travel")

    func testDeletingTheFolderOnScreenShowsItsParent() {
        let trip = BookmarkFolderRecord(title: "Trip", parentID: travel.id)

        XCTAssertEqual(BookmarksHomeNavigation.folderToShow(current: trip.id, afterDeleting: trip), travel.id)
    }

    func testDeletingATopLevelFolderOnScreenShowsAllBookmarks() {
        XCTAssertNil(BookmarksHomeNavigation.folderToShow(current: travel.id, afterDeleting: travel))
    }

    func testDeletingAnotherFolderLeavesTheOneOnScreen() {
        let other = BookmarkFolderRecord(title: "Recipes")

        XCTAssertEqual(BookmarksHomeNavigation.folderToShow(current: travel.id, afterDeleting: other), travel.id)
    }

    /// Deleted somewhere else — the bar's menu, another window — the page can
    /// no longer know the parent, and shows everything rather than nothing.
    func testAFolderThatNoLongerExistsFallsBackToAllBookmarks() {
        XCTAssertNil(BookmarksHomeNavigation.folderToShow(current: UUID(), existing: [travel]))
        XCTAssertEqual(BookmarksHomeNavigation.folderToShow(current: travel.id, existing: [travel]), travel.id)
        XCTAssertNil(BookmarksHomeNavigation.folderToShow(current: nil, existing: [travel]))
    }
}
