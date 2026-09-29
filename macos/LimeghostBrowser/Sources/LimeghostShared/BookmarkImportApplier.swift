import Foundation
import LimeghostCore

// Moved here from the Mac's `BookmarkImportViews.swift` on September 29,
// 2026, when the iPhone gained Import Bookmarks: applying and undoing an
// import is logic, not a screen, and two copies of it would be two answers to
// "what did this import add". Unchanged apart from being public.

/// What actually happened when a `BookmarkImportPlan` was applied to the
/// store: the real folder and bookmark ids it created, in the order it
/// created them. Carrying the ids (not just counts) is what makes `undo`
/// possible, and is why undo works the same whether the import landed in
/// one folder or across the bar — there is no wrapper it depends on.
public struct BookmarkImportApplyResult: Equatable {
    public let placement: BookmarkImportPlacement
    /// The dated container's id and title, when the import created one.
    /// Both `nil` together: under bar placement with nothing left over
    /// there is no such folder, and no screen should name one that does not
    /// exist.
    public let importFolderID: UUID?
    public let importFolderTitle: String?
    /// Parent-before-child: the same order `BookmarkImportPlan.folders`
    /// listed them in, which is the order they were created in.
    ///
    /// `nil` at a slot means that folder could not be created and its
    /// children were filed one level up. Deliberately not "the parent's id
    /// instead" — that would make undo delete a folder this import did not
    /// create, which under bar placement would be one of the person's own.
    public let createdFolderIDs: [UUID?]
    public let createdBookmarkIDs: [UUID]
    public let skippedExistingCount: Int
    public let duplicateWithinImportCount: Int

    public var addedCount: Int { createdBookmarkIDs.count }
    /// How many of the source's *own* bar folders now sit on the bar.
    /// Excludes the dated container, which is also a top-level folder but is
    /// Limeghost's own doing rather than something the person recognizes
    /// from the browser they came from — counting it would make the result
    /// screen name it twice.
    public var createdBarFolderCount: Int = 0
}

/// Applies a `BookmarkImportPlan` to a `BrowserDataStore`, and can undo
/// exactly what it applied. Both directions are built entirely from the
/// store's own existing, already-tested primitives — creating a folder,
/// adding a bookmark, removing a bookmark, and deleting an (by then empty)
/// folder without disturbing its parent — so undoing an import needs no
/// separate "delete with contents" capability that the rest of the app does
/// not also have.
@MainActor
public enum BookmarkImportApplier {
    /// Only `createBookmarkFolder` and `addBookmark` are used here, and both
    /// only ever append to a sibling row without renumbering it. Never reach
    /// for `moveBookmarkFolder(_:toIndex:)` or `moveBookmark(_:toIndex:)` in
    /// this file: they renumber an entire row of siblings, and under bar
    /// placement that row is the person's own bookmarks bar.
    ///
    /// A plan may only be applied to the collection it was planned against.
    /// It was built knowing which addresses that collection already held.
    public static func apply(_ plan: BookmarkImportPlan, into store: BrowserDataStore) -> BookmarkImportApplyResult {
        // The single most important rule this whole feature exists to
        // protect: an address already saved is skipped, never re-added, so
        // `BookmarkCollection.addBookmark`'s replace-on-matching-URL
        // behavior never has a chance to move or rename an existing
        // bookmark. `plan` already excludes every such address — this
        // function only ever creates brand-new records. That reasoning is
        // unchanged by placement: the skip is keyed on the address, and
        // where a new bookmark lands has nothing to do with it.
        guard !plan.isEmpty else { return emptyResult(for: plan) }

        var createdFolderIDs: [UUID?] = []
        var createdBookmarkIDs: [UUID] = []
        var createdBarFolderCount = 0

        // One write for the whole import instead of one per record. Every
        // call below still updates the store's published records
        // immediately; only the encoding and the disk write wait for the
        // end.
        store.performBatch {
        for (index, planned) in plan.folders.enumerated() {
            // `flatMap`, not `map`: a parent that could not be created
            // leaves its children filed one level up rather than trapping.
            let parentID = planned.parentIndex.flatMap { createdFolderIDs[$0] }
            let created = store.createBookmarkFolder(
                title: planned.title,
                iconID: LimeghostIconCatalog.defaultIconID,
                colorID: nil,
                parentID: parentID
            )
            createdFolderIDs.append(created?.id)
            if created != nil, planned.parentIndex == nil, index != plan.importFolderIndex {
                createdBarFolderCount += 1
            }
        }

        for planned in plan.bookmarks {
            let parentID = planned.parentIndex.flatMap { createdFolderIDs[$0] }
            if let created = store.addBookmark(title: planned.title, url: planned.url, folderID: parentID) {
                createdBookmarkIDs.append(created.id)
            }
        }
        }

        let importFolderID = plan.importFolderIndex.flatMap { createdFolderIDs[$0] }
        return BookmarkImportApplyResult(
            placement: plan.placement,
            importFolderID: importFolderID,
            importFolderTitle: importFolderID == nil ? nil : plan.importFolderIndex.map { plan.folders[$0].title },
            createdFolderIDs: createdFolderIDs,
            createdBookmarkIDs: createdBookmarkIDs,
            skippedExistingCount: plan.skippedExistingCount,
            duplicateWithinImportCount: plan.duplicateWithinImportCount,
            createdBarFolderCount: createdBarFolderCount
        )
    }

    private static func emptyResult(for plan: BookmarkImportPlan) -> BookmarkImportApplyResult {
        BookmarkImportApplyResult(
            placement: plan.placement,
            importFolderID: nil,
            importFolderTitle: nil,
            createdFolderIDs: [],
            createdBookmarkIDs: [],
            skippedExistingCount: plan.skippedExistingCount,
            duplicateWithinImportCount: plan.duplicateWithinImportCount,
            createdBarFolderCount: 0
        )
    }

    /// Removes every bookmark this import created, then deletes every folder
    /// it created, deepest first. By the time any one folder's turn comes,
    /// its own bookmarks are already gone and every subfolder has already
    /// been removed, so it is genuinely empty — the existing
    /// preserve-contents delete has nothing left to preserve and simply
    /// removes it, the same way it already does for any other empty folder.
    ///
    /// Nothing this import did not create is ever touched, and because both
    /// creation primitives only appended, every record the person already
    /// had comes back to its exact previous position rather than merely its
    /// previous folder.
    ///
    /// The one thing this cannot promise: a bookmark the person moved into
    /// an imported folder *after* importing is kept, but ends up one level
    /// up, because deleting its folder preserves its contents by reparenting
    /// them. The result screen says so rather than promising nothing moves.
    public static func undo(_ result: BookmarkImportApplyResult, in store: BrowserDataStore) {
        store.performBatch {
        for bookmarkID in result.createdBookmarkIDs {
            guard let bookmark = store.bookmarks.first(where: { $0.id == bookmarkID }) else { continue }
            store.removeBookmark(bookmark)
        }
        for folderID in result.createdFolderIDs.reversed() {
            guard let folderID, let folder = store.bookmarkFolder(id: folderID) else { continue }
            store.deleteBookmarkFolderPreservingContents(folder)
        }
        }
    }
}
