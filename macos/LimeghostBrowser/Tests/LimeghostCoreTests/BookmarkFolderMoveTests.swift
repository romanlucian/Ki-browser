import Foundation
import XCTest
@testable import LimeghostCore

/// Moving a folder, with everything in it, into another folder or out to the
/// top. There was no way to: folders could be reordered beside each other but
/// never re-filed, so the folders an import brought stayed inside the dated
/// folder it made — the founder imported their bookmarks on September 29,
/// 2026 and asked for exactly this.
final class BookmarkFolderMoveTests: XCTestCase {
    private func folder(_ title: String, in parentID: UUID? = nil, _ collection: inout BookmarkCollection) throws -> BookmarkFolderRecord {
        try XCTUnwrap(collection.createFolder(title: title, iconID: LimeghostIconCatalog.defaultIconID, parentID: parentID))
    }

    /// Out to the top: the folder joins the end of the top level, what it
    /// holds travels with it, and the row it left closes up.
    func testAFolderMovesToTheTopWithEverythingInIt() throws {
        var collection = BookmarkCollection()
        let imported = try folder("Imported", &collection)
        let first = try folder("First", in: imported.id, &collection)
        let travel = try folder("Travel", in: imported.id, &collection)
        let last = try folder("Last", in: imported.id, &collection)
        let inside = try folder("Inside", in: travel.id, &collection)
        collection.addBookmark(BookmarkRecord(title: "Map", url: "https://map.example/", folderID: travel.id))

        XCTAssertTrue(collection.moveFolder(id: travel.id, to: nil))

        XCTAssertEqual(collection.folders(in: nil).map(\.title), ["Imported", "Travel"], "it did not join the end of the top")
        XCTAssertEqual(collection.folders(in: travel.id).map(\.id), [inside.id], "a subfolder stayed behind")
        XCTAssertEqual(collection.bookmarks(in: travel.id).map(\.title), ["Map"], "a bookmark stayed behind")
        XCTAssertEqual(collection.folders(in: imported.id).map(\.id), [first.id, last.id])
        XCTAssertEqual(collection.folders(in: imported.id).map(\.position), [0, 1], "the row it left kept a gap")
    }

    /// Into another folder: it goes to the end there.
    func testAFolderMovesIntoAnotherFolderAtItsEnd() throws {
        var collection = BookmarkCollection()
        let work = try folder("Work", &collection)
        _ = try folder("Projects", in: work.id, &collection)
        let clients = try folder("Clients", &collection)

        XCTAssertTrue(collection.moveFolder(id: clients.id, to: work.id))

        XCTAssertEqual(collection.folders(in: work.id).map(\.title), ["Projects", "Clients"])
        XCTAssertEqual(collection.folders(in: nil).map(\.title), ["Work"])
    }

    /// Never into itself or into one of its own folders: that would cut the
    /// whole branch off from the top. Refused, and nothing changes.
    func testAFolderCannotMoveIntoItselfOrItsOwnFolders() throws {
        var collection = BookmarkCollection()
        let work = try folder("Work", &collection)
        let projects = try folder("Projects", in: work.id, &collection)
        let before = collection

        XCTAssertFalse(collection.moveFolder(id: work.id, to: work.id))
        XCTAssertFalse(collection.moveFolder(id: work.id, to: projects.id))
        XCTAssertEqual(collection, before)
        XCTAssertTrue(collection.isFolder(projects.id, insideOrEqualTo: work.id))
        XCTAssertTrue(collection.isFolder(work.id, insideOrEqualTo: work.id))
        XCTAssertFalse(collection.isFolder(nil, insideOrEqualTo: work.id), "the top is inside nothing")
    }

    /// Moving a folder to where it already is, or to a folder that does not
    /// exist, changes nothing.
    func testAMoveThatGoesNowhereChangesNothing() throws {
        var collection = BookmarkCollection()
        let work = try folder("Work", &collection)
        let before = collection

        XCTAssertFalse(collection.moveFolder(id: work.id, to: nil), "moved to where it already was")
        XCTAssertFalse(collection.moveFolder(id: work.id, to: UUID()), "moved into a folder that does not exist")
        XCTAssertEqual(collection, before)
    }
}
