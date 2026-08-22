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
/// Where an import lands. A plan is built for exactly one of these, and the
/// two produce genuinely different trees — so a plan may only ever be
/// applied as the placement it was built for.
public enum BookmarkImportPlacement: String, Equatable, Sendable, CaseIterable {
    /// The source's own bar becomes Clearframe's bar. Nothing wraps the
    /// bookmarks that were on it: they land at the top level, which *is*
    /// the bar — `BookmarkBarViews` shows exactly `folders(in: nil)` and
    /// `bookmarks(in: nil)`. Anything the source kept somewhere other than
    /// its bar goes into a single dated folder, which is itself one more
    /// chip on the bar.
    ///
    /// This is the shape somebody switching browsers is asking for: in
    /// Chrome their bar *is* their folders, one click each, and an import
    /// that buries them two levels down has taken that away.
    case bookmarksBar
    /// One dated folder holds the whole import, the source's structure
    /// preserved beneath it. Safer for somebody who already has a bar they
    /// arranged, because everything the import added can be removed by
    /// deleting one folder.
    case singleFolder
}

public struct BookmarkImportPlan: Equatable, Sendable {
    /// One folder the import will create, addressed by its position in
    /// `folders` rather than a real id — nothing exists yet when a plan is
    /// built. `parentIndex` is `nil` for a folder that sits at the top
    /// level, which is the bookmarks bar; otherwise it is the index,
    /// earlier in this same array, of the folder it nests inside.
    ///
    /// The dated "Imported from …" container, when there is one, is an
    /// ordinary entry in this array like any other — see
    /// `importFolderIndex`. Nothing is created outside this plan, so what a
    /// preview counts here is exactly what will appear.
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

    /// Which shape this plan was built for.
    public let placement: BookmarkImportPlacement

    /// New folders to create, parent before child, so applying them in order
    /// never references a folder that has not been created yet. Never
    /// includes a folder whose entire subtree ended up empty — Clearframe
    /// does not create empty folders, on import or anywhere else.
    public let folders: [PlannedFolder]
    /// New bookmarks to add, each already resolved to a place among
    /// `folders`, or onto the bar itself when `parentIndex` is `nil`.
    public let bookmarks: [PlannedBookmark]

    /// An address already present anywhere in the existing collection. The
    /// existing record is not part of this plan at all — it is left exactly
    /// as it was found: same id, same folder, same title.
    public let skippedExistingCount: Int
    /// The same address appearing more than once inside the import itself.
    /// Only the first occurrence is planned; the rest are counted here
    /// instead of silently vanishing from the numbers a preview shows.
    public let duplicateWithinImportCount: Int

    /// Where the dated "Imported from …" folder sits in `folders`, when the
    /// plan creates one at all.
    ///
    /// `nil` only under `.bookmarksBar` placement when the source kept
    /// everything on its bar — then there is nothing left over to hold, and
    /// creating an empty dated folder would put a chip on the bar that
    /// contains nothing.
    public let importFolderIndex: Int?

    /// Titles this plan will put on the bar that a folder already on the bar
    /// also uses, compared case-insensitively, de-duplicated, in plan order.
    ///
    /// Never a blocker, and never renamed to "AI (2)": the source's own name
    /// is kept, and Clearframe never merges an import into a folder somebody
    /// made — that is what keeps undo exact and what stops an import
    /// silently interleaving itself with a person's own bookmarks. But two
    /// identically named chips appearing on the bar is a surprise unless it
    /// is said first, so a preview must show this.
    public let barTitleCollisions: [String]

    public var addedCount: Int { bookmarks.count }
    /// True when nothing survived skipping and de-duplication — every
    /// address the source held was already saved. Nothing should be created
    /// for a plan like this, not even the destination folder itself.
    public var isEmpty: Bool { bookmarks.isEmpty }

    public init(
        placement: BookmarkImportPlacement,
        sourceBookmarkCount: Int,
        sourceFolderCount: Int,
        folders: [PlannedFolder],
        bookmarks: [PlannedBookmark],
        importFolderIndex: Int?,
        barTitleCollisions: [String],
        skippedExistingCount: Int,
        duplicateWithinImportCount: Int
    ) {
        self.placement = placement
        self.sourceBookmarkCount = sourceBookmarkCount
        self.sourceFolderCount = sourceFolderCount
        self.folders = folders
        self.bookmarks = bookmarks
        self.importFolderIndex = importFolderIndex
        self.barTitleCollisions = barTitleCollisions
        self.skippedExistingCount = skippedExistingCount
        self.duplicateWithinImportCount = duplicateWithinImportCount
    }
}

/// Builds a `BookmarkImportPlan` from a parsed import and the collection it
/// would land in. Pure and side-effect free — the only place this looks at
/// existing data is to decide what to skip, and what would collide by name.
public enum BookmarkImportMergePlanner {
    /// What to offer first, decided by what is already on the bar.
    ///
    /// An empty bar means there is nothing to disturb and nothing to lose,
    /// so the import may as well land where the person will actually use
    /// it. A bar somebody has already arranged is theirs, so the safe,
    /// removable-in-one-gesture shape is offered instead. Either way the
    /// preview shows the choice and either can be picked.
    ///
    /// Uses the same emptiness test the bar itself uses, so the two cannot
    /// drift: a bar holding loose bookmarks but no folders is still not
    /// empty.
    public static func recommendedPlacement(for existing: BookmarkCollection) -> BookmarkImportPlacement {
        let barIsEmpty = existing.folders(in: nil).isEmpty && existing.bookmarks(in: nil).isEmpty
        return barIsEmpty ? .bookmarksBar : .singleFolder
    }

    /// `importFolderTitle` names the dated container. It is passed in rather
    /// than built here so the plan describes every folder it will create,
    /// including that one — a preview that counts `folders` is then counting
    /// exactly what will appear, with nothing conjured later by the applier.
    public static func plan(
        _ imported: BookmarkImport,
        into existing: BookmarkCollection,
        placement: BookmarkImportPlacement,
        importFolderTitle: String
    ) -> BookmarkImportPlan {
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
                    // `role` must survive the rebuild. Drop it here and bar
                    // placement quietly degrades into "the source named no
                    // bar" — which looks exactly like the designed fallback
                    // rather than like a bug.
                    kept.append(.folder(ImportedFolder(title: folder.title, children: prunedChildren, role: folder.role)))
                }
            }
            return kept
        }

        let survivingRoots: [ImportedFolder] = imported.roots.compactMap { root in
            let children = prune(root.children)
            return children.isEmpty ? nil : ImportedFolder(title: root.title, children: children, role: root.role)
        }

        // Second pass: flatten the surviving tree into flat, index-addressed
        // arrays a caller can create top-down without ever creating a folder
        // out of order relative to its own parent. `parentIndex == nil` is
        // the top level — the bar — in both placements; the dated container
        // is an ordinary member of `folders`, not something separate.
        var folders: [BookmarkImportPlan.PlannedFolder] = []
        var bookmarks: [BookmarkImportPlan.PlannedBookmark] = []
        var importFolderIndex: Int?

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

        /// Appends the dated container at the top level and returns its
        /// index. Only ever called when something is going into it.
        func openImportFolder() -> Int {
            let index = folders.count
            folders.append(BookmarkImportPlan.PlannedFolder(title: importFolderTitle, parentIndex: nil))
            importFolderIndex = index
            return index
        }

        if !survivingRoots.isEmpty {
            switch placement {
            case .singleFolder:
                let container = openImportFolder()
                if survivingRoots.count == 1 {
                    // Collapse the source's own root level. A single
                    // surviving root is a container the exporting browser
                    // wrote on its way out, not a folder anybody made, and
                    // keeping it produces the nesting this whole feature
                    // exists to remove: "Imported from Chrome" ▸ "Bookmarks
                    // bar" ▸ "Projects", where "Projects" was one click away
                    // before. Stated on *surviving* roots, so a root that
                    // pruned to nothing cannot block the collapse.
                    flatten(survivingRoots[0].children, parentIndex: container)
                } else {
                    // Two or more roots are genuinely distinct places in the
                    // source. Flattening them together would silently merge
                    // "Other bookmarks" into the bar's own level.
                    flatten(survivingRoots.map(ImportedNode.folder), parentIndex: container)
                }

            case .bookmarksBar:
                let barIndex = barRootIndex(in: survivingRoots, declaredBySource: imported.declaresBookmarksBar)
                if let barIndex {
                    // The bar's contents become the bar's contents. This is
                    // the whole point of the placement.
                    flatten(survivingRoots[barIndex].children, parentIndex: nil)
                }
                // Everything the source kept somewhere other than its bar
                // goes into one dated chip, appended after the bar folders
                // so it never pushes them along. Chrome does the same thing
                // when it merges directly onto an empty bar.
                let leftovers = survivingRoots.enumerated()
                    .filter { $0.offset != barIndex }
                    .map { ImportedNode.folder($0.element) }
                if !leftovers.isEmpty {
                    flatten(leftovers, parentIndex: openImportFolder())
                }
            }
        }

        let existingBarTitles = Set(existing.folders(in: nil).map { $0.title.lowercased() })
        var seenCollisions: Set<String> = []
        let barTitleCollisions = folders
            .filter { $0.parentIndex == nil && existingBarTitles.contains($0.title.lowercased()) }
            .map(\.title)
            .filter { seenCollisions.insert($0.lowercased()).inserted }

        return BookmarkImportPlan(
            placement: placement,
            sourceBookmarkCount: imported.bookmarkCount,
            sourceFolderCount: imported.folderCount,
            folders: folders,
            bookmarks: bookmarks,
            importFolderIndex: importFolderIndex,
            barTitleCollisions: barTitleCollisions,
            skippedExistingCount: skippedExisting,
            duplicateWithinImportCount: duplicates
        )
    }

    /// Which surviving root, if any, should have its contents emptied onto
    /// the bar. Never guesses from a title: "Bookmarks bar", "Bookmarks
    /// Toolbar", "Favorites", "toolbar" and every localized spelling are all
    /// the same folder, and a folder somebody named "Bookmarks bar"
    /// themselves is not.
    private static func barRootIndex(in roots: [ImportedFolder], declaredBySource: Bool) -> Int? {
        // Asked of the *original* import, not of what survived, so a bar
        // that pruned away cannot let the single-root rule below unwrap some
        // unrelated root in its place.
        if declaredBySource {
            return roots.firstIndex { $0.role == .bookmarksBar }
        }
        // A source that named no bar — an older export, or a format with no
        // such concept — but held exactly one place for bookmarks. That one
        // place is what the person had, so it is what goes on the bar.
        return roots.count == 1 ? 0 : nil
    }
}
