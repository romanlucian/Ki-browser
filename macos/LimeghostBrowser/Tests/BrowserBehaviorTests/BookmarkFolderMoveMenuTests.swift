import Foundation
import LimeghostCore
import LimeghostShared
import XCTest
@testable import LimeghostBrowser

/// The Mac's Move to for a folder. The shared layer could re-file a folder
/// from September 29, 2026, and the iPhone offered it the same day; the Mac's
/// folder menus had no way to, so the founder asked for it.
@MainActor
final class BookmarkFolderMoveMenuTests: XCTestCase {
    private func makeStore() throws -> BrowserDataStore {
        let suiteName = "clearframe.macFolderMove.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return BrowserDataStore(defaults: defaults)
    }

    private func folder(_ title: String, in parentID: UUID? = nil, _ store: BrowserDataStore) throws -> BookmarkFolderRecord {
        try XCTUnwrap(store.createBookmarkFolder(title: title, iconID: LimeghostIconCatalog.defaultIconID, parentID: parentID))
    }

    /// A folder's menu offers every place but the folder itself and the
    /// folders inside it, however deep: the top ("Unfiled", as the bookmark
    /// menus call it) and every other branch stay.
    func testAFoldersMoveMenuLeavesOutItsOwnBranch() throws {
        let store = try makeStore()
        let work = try folder("Work", store)
        let projects = try folder("Projects", in: work.id, store)
        _ = try folder("Deep", in: projects.id, store)
        _ = try folder("Travel", store)
        let destinations = BookmarkFolderDestination.tree(in: store)

        XCTAssertEqual(
            BookmarkFolderDestination.places(for: work, among: destinations).map(\.label),
            ["Unfiled", "Travel"]
        )
        XCTAssertEqual(
            BookmarkFolderDestination.places(for: projects, among: destinations).map(\.label),
            ["Unfiled", "Travel", "Work"]
        )
    }

    /// Every place still reads as its path, as the bookmark menus show it.
    func testEveryPlaceStillReadsAsItsPath() throws {
        let store = try makeStore()
        let work = try folder("Work", store)
        let projects = try folder("Projects", in: work.id, store)
        _ = try folder("Deep", in: projects.id, store)

        XCTAssertEqual(
            BookmarkFolderDestination.tree(in: store).map(\.label),
            ["Unfiled", "Work", "Work › Projects", "Work › Projects › Deep"]
        )
    }
}
