import XCTest
import LimeghostCore
@testable import Limeghost
@testable import LimeghostShared

/// Ticking several bookmarks and folders and moving or deleting them in one
/// go. Asked for by the founder after an import left dozens of things inside
/// one folder, and one-at-a-time Move to… was the only way out.
@MainActor
final class BookmarkSelectionTests: XCTestCase {
    /// A suite of its own, emptied afterwards: these tests run inside the app.
    private func makeHost() throws -> WorkspaceHost {
        let suiteName = "clearframe.iosSelection.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return WorkspaceHost.forTesting(defaults: defaults)
    }

    private func folder(_ title: String, in parentID: UUID? = nil, _ store: BrowserDataStore) throws -> BookmarkFolderRecord {
        try XCTUnwrap(store.createBookmarkFolder(title: title, iconID: LimeghostIconCatalog.defaultIconID, parentID: parentID))
    }

    private func page(_ title: String, in folderID: UUID? = nil, _ store: BrowserDataStore) throws -> BookmarkRecord {
        let host = title.lowercased().replacingOccurrences(of: " ", with: "-")
        return try XCTUnwrap(store.addBookmark(title: title, url: "https://\(host).example/", folderID: folderID))
    }

    // MARK: - Moving

    /// Everything ticked goes to the top — each folder with what it holds —
    /// in the order it was listed; what was not ticked stays.
    func testMovingSeveralPutsThemAtTheTopInTheirOrder() throws {
        let host = try makeHost()
        let store = host.workspace.dataStore
        let imported = try folder("Imported", store)
        let sm = try folder("sm", in: imported.id, store)
        let work = try folder("Work", in: imported.id, store)
        let a = try page("A", in: imported.id, store)
        _ = try page("B", in: imported.id, store)
        let c = try page("C", in: imported.id, store)
        _ = try page("Inside", in: sm.id, store)

        let moved = BookmarksModel(workspace: host.workspace)
            .move([.folder(sm.id), .folder(work.id), .bookmark(a.id), .bookmark(c.id)], to: nil)

        XCTAssertEqual(moved, 4)
        XCTAssertEqual(store.bookmarkFolders(in: nil).map(\.title), ["Imported", "sm", "Work"])
        XCTAssertEqual(store.bookmarks(in: nil).map(\.title), ["A", "C"])
        XCTAssertEqual(store.bookmarks(in: imported.id).map(\.title), ["B"])
        XCTAssertEqual(store.bookmarks(in: sm.id).map(\.title), ["Inside"], "a folder's own bookmark stayed behind")
    }

    /// A ticked folder never goes inside itself or one of its own folders,
    /// even beside things that can go there; those still move.
    func testATickedFolderNeverMovesIntoItself() throws {
        let host = try makeHost()
        let store = host.workspace.dataStore
        let work = try folder("Work", store)
        let projects = try folder("Projects", in: work.id, store)
        let loose = try page("Loose", store)

        let moved = BookmarksModel(workspace: host.workspace)
            .move([.folder(work.id), .bookmark(loose.id)], to: projects.id)

        XCTAssertEqual(moved, 1)
        XCTAssertEqual(store.bookmarkFolders(in: nil).map(\.title), ["Work"], "a folder moved inside itself")
        XCTAssertEqual(store.bookmarks(in: projects.id).map(\.title), ["Loose"])
    }

    /// A ticked folder's Move to… leaves out every ticked folder and the
    /// folders inside them.
    func testTheDestinationsLeaveOutEveryTickedFolder() {
        let work = BookmarkFolderRecord(title: "Work")
        let projects = BookmarkFolderRecord(title: "Projects", parentID: work.id)
        let recipes = BookmarkFolderRecord(title: "Recipes")
        let travel = BookmarkFolderRecord(title: "Travel")

        let rows = BookmarkDestinations.rows(folders: [work, projects, recipes, travel], excludingAll: [work.id, recipes.id])

        XCTAssertEqual(rows.map(\.title), ["Bookmarks", "Travel"])
    }

    // MARK: - Deleting

    /// Delete takes the ticked bookmarks, and a ticked folder keeps the
    /// one-at-a-time rule: it goes, and what it held moves up — a bookmark
    /// inside it is never deleted.
    func testDeletingSeveralTakesBookmarksAndEmptiesFolders() throws {
        let host = try makeHost()
        let store = host.workspace.dataStore
        let imported = try folder("Imported", store)
        let old = try folder("Old", in: imported.id, store)
        _ = try page("Kept inside", in: old.id, store)
        let a = try page("A", in: imported.id, store)
        _ = try page("B", in: imported.id, store)

        BookmarksModel(workspace: host.workspace).delete([.folder(old.id), .bookmark(a.id)])

        XCTAssertTrue(store.bookmarkFolders(in: imported.id).isEmpty, "the ticked folder stayed")
        XCTAssertEqual(Set(store.bookmarks(in: imported.id).map(\.title)), ["B", "Kept inside"])
        XCTAssertNil(store.bookmarks.first { $0.title == "A" }, "a ticked bookmark stayed")
    }

    /// The question says what will happen, in numbers, before anything goes.
    func testTheDeleteQuestionSaysWhatHappens() {
        XCTAssertEqual(BookmarkSelectionWording.deleteTitle(folders: 0, bookmarks: 3), "Delete 3 bookmarks?")
        XCTAssertEqual(BookmarkSelectionWording.deleteTitle(folders: 1, bookmarks: 0), "Delete 1 folder?")
        XCTAssertEqual(BookmarkSelectionWording.deleteTitle(folders: 2, bookmarks: 3), "Delete 5 items?")

        let both = BookmarkSelectionWording.deleteMessage(folders: 2, bookmarks: 3)
        XCTAssertTrue(both.contains("3 bookmarks are deleted"), both)
        XCTAssertTrue(both.contains("what they hold moves up a level"), both)
        XCTAssertTrue(both.contains("This cannot be undone."), both)
        XCTAssertEqual(
            BookmarkSelectionWording.deleteMessage(folders: 0, bookmarks: 1),
            "The bookmark is deleted. This cannot be undone."
        )
        XCTAssertFalse(BookmarkSelectionWording.deleteMessage(folders: 1, bookmarks: 0).contains("bookmarks are deleted"))
    }
}
