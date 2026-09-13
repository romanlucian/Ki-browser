import LimeghostCore
import LimeghostShared
import SwiftUI

/// What the Bookmarks sheet shows and does, apart from how it draws, so a
/// test can call it: the shape `TabSwitcherModel` has. It holds only the
/// workspace and reads the store fresh on every call, because the sheet
/// observes the store and rebuilds this whenever the store changes.
///
/// Everything here is the store's or the workspace's own: the order, the
/// search filters, the filing calls and the two doors. The phone adds a list,
/// not a second set of rules.
@MainActor
struct BookmarksModel {
    let workspace: BrowserWorkspace

    private var store: BrowserDataStore { workspace.dataStore }

    // MARK: - Listing

    /// "Bookmarks" at the top level, and a folder's own name inside it.
    func title(of folderID: UUID?) -> String {
        guard let folderID, let folder = store.bookmarkFolder(id: folderID) else { return "Bookmarks" }
        return folder.title
    }

    /// A folder's subfolders, in the store's order: the order the Mac shows.
    func folders(in folderID: UUID?) -> [BookmarkFolderRecord] {
        store.bookmarkFolders(in: folderID)
    }

    /// A folder's bookmarks, in the store's order.
    func bookmarks(in folderID: UUID?) -> [BookmarkRecord] {
        store.bookmarks(in: folderID)
    }

    // MARK: - Search

    /// Folders from every level whose names match, through the filter the
    /// Mac's bookmarks home uses.
    func folders(matching query: String) -> [BookmarkFolderRecord] {
        BookmarksHomeSearch.folders(store.bookmarkFolders, matching: query)
    }

    /// Bookmarks from every folder whose names or addresses match.
    func bookmarks(matching query: String) -> [BookmarkRecord] {
        BookmarksHomeSearch.bookmarks(store.bookmarks, matching: query)
    }

    // MARK: - Doors

    /// Through `open(_:inNewTab:)`, the door table's "an address or a
    /// bookmark" and "a bookmark in a new tab". It makes room for the page
    /// before loading it; a session load directly would skip that.
    func open(_ bookmark: BookmarkRecord, inNewTab: Bool = false) {
        workspace.open(bookmark.url, inNewTab: inNewTab)
    }

    // MARK: - Filing

    func delete(_ bookmark: BookmarkRecord) {
        store.removeBookmark(bookmark)
    }

    /// Whether deleting this folder asks first: only when it holds something,
    /// which is the Mac's rule. An empty folder has nothing to lose.
    func deletingAsksFirst(_ folder: BookmarkFolderRecord) -> Bool {
        store.bookmarkFolderContainsItems(folder)
    }

    /// Deletes the folder itself. What it held moves up to its parent, so
    /// deleting a folder never deletes a saved page.
    func delete(_ folder: BookmarkFolderRecord) {
        store.deleteBookmarkFolderPreservingContents(folder)
    }

    /// Changes the name and nothing else: the address and the folder stay.
    /// An empty name becomes the site's host, which is the store's rule.
    func rename(_ bookmark: BookmarkRecord, to name: String) {
        store.updateBookmark(id: bookmark.id, title: name, url: bookmark.url)
    }

    /// Changes the name and nothing else. The store's update takes an icon and
    /// a tint too; handed the folder's own, it leaves both as they are. An
    /// empty icon ID leaves a folder that never chose one still resolving its
    /// old emoji. An empty name keeps the old one, which is the store's rule.
    func rename(_ folder: BookmarkFolderRecord, to name: String) {
        store.updateBookmarkFolder(id: folder.id, title: name, iconID: folder.iconID ?? "", colorID: folder.colorID)
    }

    /// Files a bookmark at the end of another folder, or of the top level.
    func move(_ bookmark: BookmarkRecord, to folderID: UUID?) {
        store.moveBookmark(bookmark, to: folderID)
    }

    /// A new folder at the end of the one on screen, drawn with the plain
    /// folder. The store refuses an empty name, but the person pressed Create
    /// and asked for a folder, so an empty name makes one called "New Folder".
    @discardableResult
    func createFolder(named name: String, in parentID: UUID?) -> BookmarkFolderRecord? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.createBookmarkFolder(
            title: trimmed.isEmpty ? "New Folder" : trimmed,
            iconID: LimeghostIconCatalog.defaultIconID,
            parentID: parentID
        )
    }
}

/// A name being typed into an alert: a new folder, or a new name for a folder
/// or a bookmark. One value, so each screen has one alert and a test can read
/// what each case shows and does.
enum BookmarkNameEdit {
    case newFolder(parentID: UUID?)
    case renameFolder(BookmarkFolderRecord)
    case renameBookmark(BookmarkRecord)

    var title: String {
        switch self {
        case .newFolder: return "New Folder"
        case .renameFolder: return "Rename Folder"
        case .renameBookmark: return "Rename Bookmark"
        }
    }

    var confirmLabel: String {
        switch self {
        case .newFolder: return "Create"
        case .renameFolder, .renameBookmark: return "Save"
        }
    }

    /// What the field holds when the alert opens: nothing for a new folder,
    /// the current name for a rename.
    var startingName: String {
        switch self {
        case .newFolder: return ""
        case .renameFolder(let folder): return folder.title
        case .renameBookmark(let bookmark): return bookmark.title
        }
    }

    @MainActor
    func commit(_ name: String, with model: BookmarksModel) {
        switch self {
        case .newFolder(let parentID): model.createFolder(named: name, in: parentID)
        case .renameFolder(let folder): model.rename(folder, to: name)
        case .renameBookmark(let bookmark): model.rename(bookmark, to: name)
        }
    }
}
