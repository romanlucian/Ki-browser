import XCTest
import LimeghostCore
@testable import Limeghost
@testable import LimeghostShared

@MainActor
final class BookmarksSheetTests: XCTestCase {
    /// A suite of its own, emptied afterwards, for the reason
    /// `StartSurfaceTests.makeHost()` gives: these tests run inside the app.
    private func makeHost() throws -> WorkspaceHost {
        let suiteName = "clearframe.iosBookmarks.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return WorkspaceHost.forTesting(defaults: defaults)
    }

    // MARK: - What it lists

    /// The top level is "Bookmarks"; a folder's screen carries its own name.
    func testScreensAreTitledByTheirFolder() throws {
        let host = try makeHost()
        let recipes = try host.workspace.dataStore.folder(named: "Recipes")
        let model = BookmarksModel(workspace: host.workspace)

        XCTAssertEqual(model.title(of: nil), "Bookmarks")
        XCTAssertEqual(model.title(of: recipes.id), "Recipes")
    }

    /// A folder lists what the store holds in it, in the store's order. The
    /// pages are rearranged before reading, so the order is provably the
    /// store's and not simply the order they were made in.
    func testAFolderListsWhatTheStoreHoldsInTheStoresOrder() throws {
        let host = try makeHost()
        let store = host.workspace.dataStore
        let recipes = try store.folder(named: "Recipes")
        let soups = try store.folder(named: "Soups", in: recipes.id)
        let bread = try store.page("Bread", at: "https://example.com/bread", in: recipes.id)
        let cake = try store.page("Cake", at: "https://example.com/cake", in: recipes.id)
        store.moveBookmark(cake.id, toIndex: 0)
        let model = BookmarksModel(workspace: host.workspace)

        XCTAssertEqual(model.folders(in: recipes.id).map(\.id), [soups.id])
        XCTAssertEqual(model.bookmarks(in: recipes.id).map(\.id), [cake.id, bread.id])
        XCTAssertEqual(model.folders(in: nil).map(\.id), [recipes.id], "a subfolder is not listed at the top")
    }

    /// Search looks through every folder, not only the one on screen: a page
    /// filed two folders down is found from the top, by its address.
    func testSearchFindsABookmarkFiledTwoFoldersDown() throws {
        let host = try makeHost()
        let store = host.workspace.dataStore
        let recipes = try store.folder(named: "Recipes")
        let soups = try store.folder(named: "Soups", in: recipes.id)
        _ = try store.page("Leek and potato", at: "https://soups.example/leek", in: soups.id)
        let model = BookmarksModel(workspace: host.workspace)

        XCTAssertEqual(model.bookmarks(matching: "SOUPS.EXAMPLE").map(\.title), ["Leek and potato"])
        XCTAssertEqual(model.folders(matching: "soup").map(\.title), ["Soups"])
    }

    // MARK: - What a tap does

    /// A bookmark opens in the tab in front. On the guide, that uncovers the
    /// page: no tab is added, and the guide steps aside for what was asked for.
    func testOpeningABookmarkLoadsItInTheTabInFront() throws {
        let host = try makeHost()
        let bookmark = try host.workspace.dataStore.page("Example", at: "https://example.com/saved")
        let tab = try XCTUnwrap(host.workspace.selectedTab)
        let tabsBefore = host.workspace.visibleTabs.count

        BookmarksModel(workspace: host.workspace).open(bookmark)

        XCTAssertEqual(host.workspace.visibleTabs.count, tabsBefore)
        XCTAssertEqual(host.workspace.selectedTab?.id, tab.id)
        XCTAssertEqual(tab.session.currentURLString, "https://example.com/saved")
        XCTAssertFalse(TabSurface(tab: tab, workspace: host.workspace).showsTheGuide)
    }

    /// Open in New Tab puts a new tab in front, holding the bookmark.
    func testOpenInNewTabPutsANewTabInFront() throws {
        let host = try makeHost()
        let bookmark = try host.workspace.dataStore.page("Example", at: "https://example.com/saved")
        let firstTab = try XCTUnwrap(host.workspace.selectedTab)
        let tabsBefore = host.workspace.visibleTabs.count

        BookmarksModel(workspace: host.workspace).open(bookmark, inNewTab: true)

        XCTAssertEqual(host.workspace.visibleTabs.count, tabsBefore + 1)
        XCTAssertNotEqual(host.workspace.selectedTab?.id, firstTab.id)
        XCTAssertEqual(host.workspace.selectedTab?.session.currentURLString, "https://example.com/saved")
    }

    // MARK: - Filing

    func testDeletingABookmarkRemovesIt() throws {
        let host = try makeHost()
        let store = host.workspace.dataStore
        let bookmark = try store.page("Example", at: "https://example.com/saved")

        BookmarksModel(workspace: host.workspace).delete(bookmark)

        XCTAssertFalse(store.isBookmarked("https://example.com/saved"))
    }

    /// An empty folder has nothing to lose, so it goes without asking. A
    /// folder holding a page asks first, and deleting it still loses nothing:
    /// the page moves up to where the folder was.
    func testAFolderAsksBeforeDeletingOnlyWhenItHoldsSomething() throws {
        let host = try makeHost()
        let store = host.workspace.dataStore
        let empty = try store.folder(named: "Empty")
        let recipes = try store.folder(named: "Recipes")
        let bread = try store.page("Bread", at: "https://example.com/bread", in: recipes.id)
        let model = BookmarksModel(workspace: host.workspace)

        XCTAssertFalse(model.deletingAsksFirst(empty))
        XCTAssertTrue(model.deletingAsksFirst(recipes))

        model.delete(recipes)

        XCTAssertNil(store.bookmarkFolder(id: recipes.id))
        XCTAssertEqual(
            store.bookmarks(in: nil).map(\.id), [bread.id],
            "the page moved up a level rather than going with its folder"
        )
    }

    /// Rename changes the name only: the address and the folder stay.
    func testRenamingABookmarkKeepsItsAddressAndFolder() throws {
        let host = try makeHost()
        let store = host.workspace.dataStore
        let recipes = try store.folder(named: "Recipes")
        let bread = try store.page("Bread", at: "https://example.com/bread", in: recipes.id)

        BookmarksModel(workspace: host.workspace).rename(bread, to: "Sourdough")

        let renamed = try XCTUnwrap(store.bookmark(for: "https://example.com/bread"))
        XCTAssertEqual(renamed.title, "Sourdough")
        XCTAssertEqual(renamed.id, bread.id)
        XCTAssertEqual(renamed.folderID, recipes.id)
    }

    /// The store's folder update takes an icon and a tint as well as a name.
    /// A rename hands it the folder's own, so both survive.
    func testRenamingAFolderKeepsItsIconAndTint() throws {
        let host = try makeHost()
        let store = host.workspace.dataStore
        let travel = try XCTUnwrap(store.createBookmarkFolder(title: "Travel", iconID: "palette", colorID: "amber", parentID: nil))

        BookmarksModel(workspace: host.workspace).rename(travel, to: "Holidays")

        let renamed = try XCTUnwrap(store.bookmarkFolder(id: travel.id))
        XCTAssertEqual(renamed.title, "Holidays")
        XCTAssertEqual(renamed.iconID, "palette")
        XCTAssertEqual(renamed.colorID, "amber")
    }

    /// Move to… files a bookmark in a folder, and back at the top level.
    func testMoveToFilesABookmarkAndBringsItBack() throws {
        let host = try makeHost()
        let store = host.workspace.dataStore
        let recipes = try store.folder(named: "Recipes")
        let bread = try store.page("Bread", at: "https://example.com/bread")
        let model = BookmarksModel(workspace: host.workspace)

        model.move(bread, to: recipes.id)
        XCTAssertEqual(store.bookmarks(in: recipes.id).map(\.id), [bread.id])

        model.move(try XCTUnwrap(store.bookmark(for: bread.url)), to: nil)
        XCTAssertEqual(store.bookmarks(in: nil).map(\.id), [bread.id])
        XCTAssertTrue(store.bookmarks(in: recipes.id).isEmpty)
    }

    /// New Folder makes a folder inside the one on screen, drawn with the
    /// plain folder. Left unnamed, it is called "New Folder".
    func testNewFolderLandsInsideTheFolderOnScreen() throws {
        let host = try makeHost()
        let recipes = try host.workspace.dataStore.folder(named: "Recipes")
        let model = BookmarksModel(workspace: host.workspace)

        let soups = try XCTUnwrap(model.createFolder(named: "  Soups ", in: recipes.id))
        let unnamed = try XCTUnwrap(model.createFolder(named: "   ", in: nil))

        XCTAssertEqual(soups.title, "Soups")
        XCTAssertEqual(soups.parentID, recipes.id)
        XCTAssertEqual(soups.iconID, LimeghostIconCatalog.defaultIconID)
        XCTAssertNil(soups.colorID)
        XCTAssertEqual(unnamed.title, "New Folder")
        XCTAssertNil(unnamed.parentID)
    }

    // MARK: - The name alert

    /// Each case says what it is for, starts from the right text, and its
    /// button does its own job.
    func testTheNameAlertSaysWhatItIsForAndDoesIt() throws {
        let host = try makeHost()
        let store = host.workspace.dataStore
        let recipes = try store.folder(named: "Recipes")
        let bread = try store.page("Bread", at: "https://example.com/bread")
        let model = BookmarksModel(workspace: host.workspace)

        let newFolder = BookmarkNameEdit.newFolder(parentID: recipes.id)
        XCTAssertEqual(newFolder.title, "New Folder")
        XCTAssertEqual(newFolder.confirmLabel, "Create")
        XCTAssertEqual(newFolder.startingName, "")
        newFolder.commit("Soups", with: model)
        XCTAssertEqual(store.bookmarkFolders(in: recipes.id).map(\.title), ["Soups"])

        let renameFolder = BookmarkNameEdit.renameFolder(recipes)
        XCTAssertEqual(renameFolder.title, "Rename Folder")
        XCTAssertEqual(renameFolder.confirmLabel, "Save")
        XCTAssertEqual(renameFolder.startingName, "Recipes")
        renameFolder.commit("Cooking", with: model)
        XCTAssertEqual(store.bookmarkFolder(id: recipes.id)?.title, "Cooking")

        let renameBookmark = BookmarkNameEdit.renameBookmark(bread)
        XCTAssertEqual(renameBookmark.title, "Rename Bookmark")
        XCTAssertEqual(renameBookmark.confirmLabel, "Save")
        XCTAssertEqual(renameBookmark.startingName, "Bread")
        renameBookmark.commit("Sourdough", with: model)
        XCTAssertEqual(store.bookmark(for: bread.url)?.title, "Sourdough")
    }
}

/// Folders and pages made the way the app makes them, through the store's
/// own calls.
private extension BrowserDataStore {
    func folder(named title: String, in parentID: UUID? = nil) throws -> BookmarkFolderRecord {
        try XCTUnwrap(createBookmarkFolder(title: title, iconID: LimeghostIconCatalog.defaultIconID, parentID: parentID))
    }

    func page(_ title: String, at address: String, in folderID: UUID? = nil) throws -> BookmarkRecord {
        try XCTUnwrap(addBookmark(title: title, url: address, folderID: folderID))
    }
}
