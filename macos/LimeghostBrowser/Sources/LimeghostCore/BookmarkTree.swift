import Foundation

/// One row of the folder tree, already flattened for a list to draw.
///
/// The view gets a flat array and draws it: no recursion in SwiftUI, no
/// `DisclosureGroup` holding its own private state that the page cannot read
/// back. Expansion lives in one `Set` the page owns, which is what lets
/// selecting a deep folder open the path down to it.
public struct BookmarkTreeRow: Identifiable, Equatable, Sendable {
    public let folder: BookmarkFolderRecord
    /// How far to indent. Roots are 0.
    public let depth: Int
    public let hasChildren: Bool
    public let isExpanded: Bool
    /// Saved pages filed directly in this folder — not in its descendants.
    ///
    /// Direct counts, everywhere, on purpose. The bookmarks home used to show
    /// whole-tree counts on its folder cards and direct counts on its rows,
    /// both labelled "LINKS · SUBFOLDERS", so one folder read as "39 links, 17
    /// subfolders" in one place and "0 links, 9 subfolders" in another on the
    /// same screen. In a tree the descendants are one disclosure triangle away,
    /// so the recursive number has nothing left to explain.
    public let directBookmarkCount: Int
    public let directSubfolderCount: Int

    public var id: UUID { folder.id }
}

/// Flattens a folder hierarchy into rows, and answers the two questions a
/// tree needs: what is visible, and how do I get to this folder.
///
/// Pure derivation over records — no store, no view, no web view — so the
/// awkward parts (a collapsed parent hiding an expanded child, a malformed
/// import that says a folder is its own ancestor) are testable directly.
public enum BookmarkTree {
    /// The visible rows, depth-first, titles sorted case-insensitively.
    ///
    /// A folder appears only when every one of its ancestors is expanded.
    /// Being in `expanded` is not enough on its own — a collapsed grandparent
    /// hides the whole branch, which is what makes a tree a tree.
    public static func rows(
        folders: [BookmarkFolderRecord],
        bookmarks: [BookmarkRecord],
        expanded: Set<UUID>
    ) -> [BookmarkTreeRow] {
        var childrenOf: [UUID?: [BookmarkFolderRecord]] = [:]
        for folder in folders {
            childrenOf[folder.parentID, default: []].append(folder)
        }
        for key in childrenOf.keys {
            childrenOf[key]?.sort {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }

        var bookmarkCounts: [UUID: Int] = [:]
        for bookmark in bookmarks {
            guard let folderID = bookmark.folderID else { continue }
            bookmarkCounts[folderID, default: 0] += 1
        }

        var rows: [BookmarkTreeRow] = []
        // Imported data is not trusted to be a tree. A folder whose parent
        // chain loops back on itself would otherwise recurse until the stack
        // gives out, and bookmarks arrive from other browsers' files.
        var visited: Set<UUID> = []

        func walk(parent: UUID?, depth: Int) {
            for folder in childrenOf[parent] ?? [] {
                guard visited.insert(folder.id).inserted else { continue }
                let children = childrenOf[folder.id] ?? []
                let isExpanded = expanded.contains(folder.id)
                rows.append(
                    BookmarkTreeRow(
                        folder: folder,
                        depth: depth,
                        hasChildren: !children.isEmpty,
                        isExpanded: isExpanded,
                        directBookmarkCount: bookmarkCounts[folder.id] ?? 0,
                        directSubfolderCount: children.count
                    )
                )
                if isExpanded { walk(parent: folder.id, depth: depth + 1) }
            }
        }
        walk(parent: nil, depth: 0)
        return rows
    }

    /// Root-first path down to this folder, the folder itself last.
    ///
    /// What a breadcrumb draws, and it replaces a back arrow that could only
    /// say "up one" — at four levels deep that is three presses and no idea
    /// where you are.
    public static func path(
        to folderID: UUID,
        in folders: [BookmarkFolderRecord]
    ) -> [BookmarkFolderRecord] {
        var byID: [UUID: BookmarkFolderRecord] = [:]
        for folder in folders { byID[folder.id] = folder }

        var path: [BookmarkFolderRecord] = []
        var seen: Set<UUID> = []
        var cursor: UUID? = folderID
        while let id = cursor, let folder = byID[id], seen.insert(id).inserted {
            path.append(folder)
            cursor = folder.parentID
        }
        return path.reversed()
    }

    /// Every folder that has to be open for this one to be visible.
    ///
    /// Selecting a folder from search, or restoring a selection, has to open
    /// the branch it lives in or the selection would sit inside a collapsed
    /// parent and appear to do nothing.
    public static func ancestors(
        of folderID: UUID,
        in folders: [BookmarkFolderRecord]
    ) -> Set<UUID> {
        let full = path(to: folderID, in: folders)
        return Set(full.dropLast().map(\.id))
    }
}
