import Foundation

/// What importing one parsed `BookmarkImport` into Clearframe's own
/// `BookmarkCollection` would actually do — computed once, shown in a
/// preview, and applied unchanged if the person confirms. Building this never
/// writes anything, so a sheet can render it and a person can still cancel.
///
/// The one rule this exists to protect: `BookmarkCollection.addBookmark`
/// replaces any existing bookmark at the same address. Importing naively
/// would therefore delete a person's own bookmark and relocate it into the
/// imported folder, losing its placement and its title. So an address
/// already saved is never planned as an addition — it is counted as skipped,
/// and the existing record is left completely alone.
public struct BookmarkImportPlan: Equatable, Sendable {
    /// One folder the import will create, addressed by its position in
    /// `folders` rather than a real id — nothing exists yet when a plan is
    /// built. `parentIndex` is `nil` for a folder that sits directly under
    /// the single destination folder the caller will create; otherwise it is
    /// the index, earlier in this same array, of the folder it nests inside.
    public struct PlannedFolder: Equatable, Sendable {
        public let title: String
        public let parentIndex: Int?

        public init(title: String, parentIndex: Int?) {
            self.title = title
            self.parentIndex = parentIndex
        }
    }

    /// One bookmark the import will add. `parentIndex` works the same way as
    /// `PlannedFolder.parentIndex`.
    public struct PlannedBookmark: Equatable, Sendable {
        public let title: String
        public let url: String
        public let addedAt: Date?
        public let parentIndex: Int?

        public init(title: String, url: String, addedAt: Date?, parentIndex: Int?) {
            self.title = title
            self.url = url
            self.addedAt = addedAt
            self.parentIndex = parentIndex
        }
    }

    /// Every bookmark and folder the source file or profile actually
    /// contained, however many of them turn out to be skipped below — what a
    /// preview calls "found."
    public let sourceBookmarkCount: Int
    public let sourceFolderCount: Int

    /// New folders to create, parent before child, so applying them in order
    /// never references a folder that has not been created yet. Never
    /// includes a folder whose entire subtree ended up empty — Clearframe
    /// does not create empty folders, on import or anywhere else.
    public let folders: [PlannedFolder]
    /// New bookmarks to add, each already resolved to a place among
    /// `folders`, or directly under the destination folder when
    /// `parentIndex` is `nil`.
    public let bookmarks: [PlannedBookmark]

    /// An address already present anywhere in the existing collection. The
    /// existing record is not part of this plan at all — it is left exactly
    /// as it was found: same id, same folder, same title.
    public let skippedExistingCount: Int
    /// The same address appearing more than once inside the import itself.
    /// Only the first occurrence is planned; the rest are counted here
    /// instead of silently vanishing from the numbers a preview shows.
    public let duplicateWithinImportCount: Int

    public var addedCount: Int { bookmarks.count }
    /// True when nothing survived skipping and de-duplication — every
    /// address the source held was already saved. Nothing should be created
    /// for a plan like this, not even the destination folder itself.
    public var isEmpty: Bool { bookmarks.isEmpty }

    public init(
        sourceBookmarkCount: Int,
        sourceFolderCount: Int,
        folders: [PlannedFolder],
        bookmarks: [PlannedBookmark],
        skippedExistingCount: Int,
        duplicateWithinImportCount: Int
    ) {
        self.sourceBookmarkCount = sourceBookmarkCount
        self.sourceFolderCount = sourceFolderCount
        self.folders = folders
        self.bookmarks = bookmarks
        self.skippedExistingCount = skippedExistingCount
        self.duplicateWithinImportCount = duplicateWithinImportCount
    }
}

/// Builds a `BookmarkImportPlan` from a parsed import and the collection it
/// would land in. Pure and side-effect free — the only place this looks at
/// existing data is to decide what to skip.
public enum BookmarkImportMergePlanner {
    public static func plan(_ imported: BookmarkImport, into existing: BookmarkCollection) -> BookmarkImportPlan {
        let existingURLs = Set(existing.bookmarks.map(\.url))
        var seenInImport: Set<String> = []
        var skippedExisting = 0
        var duplicates = 0

        // First pass: prune the parsed tree down to what will actually be
        // added, keeping a folder only when its subtree still holds at least
        // one surviving bookmark after skip/de-duplication. Recursive on
        // purpose and safe to be: this tree already passed the importer's
        // own depth cap (`BookmarkImportLimits.maxNestingDepth`, 256) before
        // it ever reached this function, so recursion here cannot run any
        // deeper than that.
        func prune(_ nodes: [ImportedNode]) -> [ImportedNode] {
            var kept: [ImportedNode] = []
            for node in nodes {
                switch node {
                case .bookmark(let bookmark):
                    guard seenInImport.insert(bookmark.url).inserted else {
                        duplicates += 1
                        continue
                    }
                    guard !existingURLs.contains(bookmark.url) else {
                        skippedExisting += 1
                        continue
                    }
                    kept.append(node)
                case .folder(let folder):
                    let prunedChildren = prune(folder.children)
                    guard !prunedChildren.isEmpty else { continue }
                    kept.append(.folder(ImportedFolder(title: folder.title, children: prunedChildren)))
                }
            }
            return kept
        }

        let prunedRoots: [ImportedNode] = imported.roots.compactMap { root in
            let children = prune(root.children)
            return children.isEmpty ? nil : .folder(ImportedFolder(title: root.title, children: children))
        }

        // Second pass: flatten the surviving tree into flat, index-addressed
        // arrays a caller can create top-down without ever creating a folder
        // out of order relative to its own parent.
        var folders: [BookmarkImportPlan.PlannedFolder] = []
        var bookmarks: [BookmarkImportPlan.PlannedBookmark] = []

        func flatten(_ nodes: [ImportedNode], parentIndex: Int?) {
            for node in nodes {
                switch node {
                case .bookmark(let bookmark):
                    bookmarks.append(BookmarkImportPlan.PlannedBookmark(
                        title: bookmark.title,
                        url: bookmark.url,
                        addedAt: bookmark.addedAt,
                        parentIndex: parentIndex
                    ))
                case .folder(let folder):
                    let index = folders.count
                    folders.append(BookmarkImportPlan.PlannedFolder(title: folder.title, parentIndex: parentIndex))
                    flatten(folder.children, parentIndex: index)
                }
            }
        }
        flatten(prunedRoots, parentIndex: nil)

        return BookmarkImportPlan(
            sourceBookmarkCount: imported.bookmarkCount,
            sourceFolderCount: imported.folderCount,
            folders: folders,
            bookmarks: bookmarks,
            skippedExistingCount: skippedExisting,
            duplicateWithinImportCount: duplicates
        )
    }
}
