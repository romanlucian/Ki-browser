import Foundation
import XCTest
@testable import LimeghostCore

/// The order somebody arranged their bookmarks in survives the ordinary
/// operations that are not about order at all: renaming one, and deleting the
/// folder around some of them.
final class BookmarkOrderIntegrityTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func bookmark(_ title: String, in folderID: UUID? = nil, secondsLater: TimeInterval) -> BookmarkRecord {
        BookmarkRecord(
            title: title,
            url: "https://\(title.lowercased()).example/",
            createdAt: start.addingTimeInterval(secondsLater),
            folderID: folderID
        )
    }

    /// `updateBookmark` promises "same position in the list". It rebuilt the
    /// record without its position, so the edited bookmark sorted after every
    /// sibling that still had one: rename the first bookmark on a bar and it
    /// jumped to the end.
    func testRenamingABookmarkKeepsItsPlace() throws {
        var collection = BookmarkCollection()
        let folder = try XCTUnwrap(
            collection.createFolder(title: "Trip", iconID: LimeghostIconCatalog.defaultIconID, parentID: nil)
        )
        let first = bookmark("One", in: folder.id, secondsLater: 0)
        collection.addBookmark(first)
        collection.addBookmark(bookmark("Two", in: folder.id, secondsLater: 1))
        collection.addBookmark(bookmark("Three", in: folder.id, secondsLater: 2))
        XCTAssertEqual(collection.bookmarks(in: folder.id).map(\.title), ["One", "Two", "Three"])

        XCTAssertTrue(collection.updateBookmark(id: first.id, title: "One, renamed", url: first.url))

        XCTAssertEqual(collection.bookmarks(in: folder.id).map(\.title), ["One, renamed", "Two", "Three"])
    }

    /// Changing only the address is the same promise.
    func testChangingABookmarksAddressKeepsItsPlace() throws {
        var collection = BookmarkCollection()
        let first = bookmark("One", secondsLater: 0)
        collection.addBookmark(first)
        collection.addBookmark(bookmark("Two", secondsLater: 1))

        XCTAssertTrue(collection.updateBookmark(id: first.id, title: "One", url: "https://moved.example/"))

        XCTAssertEqual(collection.bookmarks(in: nil).map(\.title), ["One", "Two"])
    }

    /// Deleting a folder moves what it held up a level. Those records kept the
    /// positions they had *inside* the deleted folder, so they collided with
    /// the parent's own numbering and interleaved with it — X, Y and the
    /// deleted folder's A, B came back as A, X, B, Y.
    func testDeletingAFolderPutsWhatItHeldAfterItsParentsOwnBookmarks() throws {
        var collection = BookmarkCollection()
        let sub = try XCTUnwrap(
            collection.createFolder(title: "Sub", iconID: LimeghostIconCatalog.defaultIconID, parentID: nil)
        )
        collection.addBookmark(bookmark("X", secondsLater: 0))
        collection.addBookmark(bookmark("Y", secondsLater: 1))
        collection.addBookmark(bookmark("A", in: sub.id, secondsLater: 2))
        collection.addBookmark(bookmark("B", in: sub.id, secondsLater: 3))

        collection.deleteFolderPreservingContents(id: sub.id)

        XCTAssertEqual(collection.bookmarks(in: nil).map(\.title), ["X", "Y", "A", "B"])
    }

    /// The same for subfolders. Names are chosen so the title tie-break would
    /// put the moved folder first if positions collided.
    func testDeletingAFolderPutsItsSubfoldersAfterItsParentsOwnFolders() throws {
        var collection = BookmarkCollection()
        let icon = LimeghostIconCatalog.defaultIconID
        _ = try XCTUnwrap(collection.createFolder(title: "Zeta", iconID: icon, parentID: nil))
        let doomed = try XCTUnwrap(collection.createFolder(title: "Doomed", iconID: icon, parentID: nil))
        _ = try XCTUnwrap(collection.createFolder(title: "Alpha", iconID: icon, parentID: doomed.id))

        collection.deleteFolderPreservingContents(id: doomed.id)

        XCTAssertEqual(collection.folders(in: nil).map(\.title), ["Zeta", "Alpha"])
    }
}
