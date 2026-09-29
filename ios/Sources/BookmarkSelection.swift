import LimeghostCore
import LimeghostShared
import SwiftUI

/// One row a person can tick while selecting: a folder or a bookmark. One
/// type, so a list of both kinds holds one selection.
enum BookmarkItemID: Hashable {
    case folder(UUID)
    case bookmark(UUID)
}

/// Moving and deleting several at once — asked for by the founder after an
/// import left dozens of things inside one folder, when Move to… one at a
/// time was the only way out. Both are the one-at-a-time actions run over a
/// list, inside one batch so the store writes once, and neither can do what
/// the one-at-a-time action would refuse.
extension BookmarksModel {
    /// Files every item at the end of `parentID`, in the order given — the
    /// order they were listed — each folder with what it holds. A folder the
    /// store refuses to move, into itself or one of its own folders, stays
    /// where it is while the rest move. Returns how many moved.
    @discardableResult
    func move(_ items: [BookmarkItemID], to parentID: UUID?) -> Int {
        let store = workspace.dataStore
        var moved = 0
        store.performBatch {
            for item in items {
                switch item {
                case .folder(let id):
                    guard let folder = store.bookmarkFolder(id: id) else { continue }
                    if store.moveBookmarkFolder(folder, to: parentID) { moved += 1 }
                case .bookmark(let id):
                    guard let bookmark = store.bookmarks.first(where: { $0.id == id }), bookmark.folderID != parentID else { continue }
                    store.moveBookmark(bookmark, to: parentID)
                    moved += 1
                }
            }
        }
        return moved
    }

    /// Deletes every ticked bookmark. A ticked folder keeps the rule deleting
    /// one folder has always had: it goes, and what it held moves up a level —
    /// a bookmark inside it is never deleted by deleting its folder. Bookmarks
    /// first, so one ticked inside a ticked folder is deleted rather than
    /// moved up.
    func delete(_ items: [BookmarkItemID]) {
        let store = workspace.dataStore
        store.performBatch {
            for case .bookmark(let id) in items {
                if let bookmark = store.bookmarks.first(where: { $0.id == id }) { store.removeBookmark(bookmark) }
            }
            for case .folder(let id) in items {
                if let folder = store.bookmarkFolder(id: id) { store.deleteBookmarkFolderPreservingContents(folder) }
            }
        }
    }
}

extension BookmarkDestinations {
    /// Every place several ticked items can go: all but the ticked folders
    /// and the folders inside them.
    static func rows(folders: [BookmarkFolderRecord], excludingAll folderIDs: Set<UUID>) -> [BookmarkDestination] {
        let collection = BookmarkCollection(folders: folders)
        return rows(folders: folders).filter { row in
            !folderIDs.contains { collection.isFolder(row.folderID, insideOrEqualTo: $0) }
        }
    }
}

/// Selecting's words. The delete question names what goes and says plainly
/// that a folder's bookmarks do not.
enum BookmarkSelectionWording {
    static func selectedCount(_ count: Int) -> String {
        count == 0 ? "Select Items" : "\(count) Selected"
    }

    static func deleteTitle(folders: Int, bookmarks: Int) -> String {
        switch (folders, bookmarks) {
        case (0, _): return "Delete \(counted(bookmarks, "bookmark"))?"
        case (_, 0): return "Delete \(counted(folders, "folder"))?"
        default: return "Delete \(folders + bookmarks) items?"
        }
    }

    static func deleteMessage(folders: Int, bookmarks: Int) -> String {
        var sentences: [String] = []
        if bookmarks == 1 {
            sentences.append("The bookmark is deleted.")
        } else if bookmarks > 1 {
            sentences.append("The \(bookmarks) bookmarks are deleted.")
        }
        if folders == 1 {
            sentences.append("The folder is removed, and what it holds moves up a level — no bookmark inside it is deleted.")
        } else if folders > 1 {
            sentences.append("The \(folders) folders are removed, and what they hold moves up a level — no bookmark inside them is deleted.")
        }
        sentences.append("This cannot be undone.")
        return sentences.joined(separator: " ")
    }

    private static func counted(_ count: Int, _ singular: String) -> String {
        "\(count) \(count == 1 ? singular : singular + "s")"
    }
}
