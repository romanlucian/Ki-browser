import Foundation
import XCTest
@testable import ClearframeCore

/// The merge planner: what importing a parsed `BookmarkImport` into an
/// existing `BookmarkCollection` would actually do. Pure logic with no store,
/// no sheet, and no writes behind it — everything here is about the plan a
/// preview would show, not about applying it. The end-to-end behavior these
/// plans exist to protect — an existing bookmark record left completely
/// untouched, and deleting the destination folder afterward restoring the
/// original tree exactly — is exercised against a real `BrowserDataStore` in
/// `BrowserBehaviorTests`, where the store and the applier both live.
final class BookmarkImportMergeTests: XCTestCase {
    private func bookmark(_ title: String, _ url: String) -> ImportedNode {
        .bookmark(ImportedBookmark(title: title, url: url, addedAt: nil))
    }

    private func folder(_ title: String, _ children: [ImportedNode]) -> ImportedNode {
        .folder(ImportedFolder(title: title, children: children))
    }

    // MARK: - Skipping what is already saved

    /// The single most important rule this feature protects:
    /// `BookmarkCollection.addBookmark` replaces any bookmark already at the
    /// same address, which would otherwise delete a person's own bookmark and
    /// relocate it into the import. The planner must never plan that address
    /// as an addition, regardless of what title or folder the import gave it.
    func testAddressAlreadySavedIsSkippedNotPlanned() {
        var existing = BookmarkCollection()
        existing.addBookmark(BookmarkRecord(title: "My Notes", url: "https://example.com/notes", folderID: nil))

        let imported = BookmarkImport(roots: [
            ImportedFolder(title: "Bookmarks bar", children: [
                .bookmark(ImportedBookmark(title: "Notes (renamed)", url: "https://example.com/notes", addedAt: nil)),
                .bookmark(ImportedBookmark(title: "New Page", url: "https://example.com/new", addedAt: nil))
            ])
        ])

        let plan = BookmarkImportMergePlanner.plan(imported, into: existing)

        XCTAssertEqual(plan.skippedExistingCount, 1)
        XCTAssertEqual(plan.addedCount, 1)
        XCTAssertEqual(plan.bookmarks.map(\.url), ["https://example.com/new"])
        XCTAssertFalse(plan.bookmarks.contains { $0.url == "https://example.com/notes" })
    }

    // MARK: - Folder structure

    func testSourceFolderStructureIsPreservedAsAChainOfParentIndices() {
        let imported = BookmarkImport(roots: [
            ImportedFolder(title: "Bookmarks bar", children: [
                folder("Work", [
                    folder("Reading", [
                        bookmark("Article", "https://example.com/article")
                    ])
                ])
            ])
        ])

        let plan = BookmarkImportMergePlanner.plan(imported, into: BookmarkCollection())

        XCTAssertEqual(plan.folders.map(\.title), ["Bookmarks bar", "Work", "Reading"])
        XCTAssertNil(plan.folders[0].parentIndex, "the root folder sits directly under the destination")
        XCTAssertEqual(plan.folders[1].parentIndex, 0, "\"Work\" nests under \"Bookmarks bar\"")
        XCTAssertEqual(plan.folders[2].parentIndex, 1, "\"Reading\" nests under \"Work\"")
        XCTAssertEqual(plan.bookmarks.count, 1)
        XCTAssertEqual(plan.bookmarks[0].parentIndex, 2, "the bookmark resolves to \"Reading\", not one of its ancestors")
    }

    /// A folder whose entire subtree was skipped or duplicated away is not
    /// planned at all — Clearframe does not create empty folders, on import
    /// or anywhere else.
    func testFolderWhoseOnlyContentWasSkippedIsPruned() {
        var existing = BookmarkCollection()
        existing.addBookmark(BookmarkRecord(title: "Already saved", url: "https://example.com/already", folderID: nil))

        let imported = BookmarkImport(roots: [
            ImportedFolder(title: "Bookmarks bar", children: [
                folder("Empty After Merge", [
                    bookmark("Already saved", "https://example.com/already")
                ]),
                folder("Survives", [
                    bookmark("New", "https://example.com/new")
                ])
            ])
        ])

        let plan = BookmarkImportMergePlanner.plan(imported, into: existing)

        XCTAssertEqual(plan.folders.map(\.title), ["Bookmarks bar", "Survives"])
        XCTAssertEqual(plan.bookmarks.map(\.url), ["https://example.com/new"])
    }

    /// A root with nothing left after pruning does not appear at all —
    /// pruning applies to a root exactly the way it applies to any folder
    /// beneath it.
    func testRootThatEndsUpEmptyIsOmittedEntirely() {
        var existing = BookmarkCollection()
        existing.addBookmark(BookmarkRecord(title: "Already saved", url: "https://example.com/already", folderID: nil))

        let imported = BookmarkImport(roots: [
            ImportedFolder(title: "Bookmarks bar", children: [bookmark("New", "https://example.com/new")]),
            ImportedFolder(title: "Other bookmarks", children: [bookmark("Already saved", "https://example.com/already")])
        ])

        let plan = BookmarkImportMergePlanner.plan(imported, into: existing)

        XCTAssertEqual(plan.folders.map(\.title), ["Bookmarks bar"], "\"Other bookmarks\" held only a skipped address")
    }

    // MARK: - Duplicates within the import

    func testDuplicateAddressesWithinTheImportCollapseToOne() {
        let imported = BookmarkImport(roots: [
            ImportedFolder(title: "Bookmarks bar", children: [
                bookmark("First copy", "https://example.com/dupe"),
                folder("Sub", [
                    bookmark("Second copy", "https://example.com/dupe")
                ])
            ])
        ])

        let plan = BookmarkImportMergePlanner.plan(imported, into: BookmarkCollection())

        XCTAssertEqual(plan.addedCount, 1)
        XCTAssertEqual(plan.duplicateWithinImportCount, 1)
        XCTAssertEqual(plan.bookmarks.map(\.title), ["First copy"], "the first occurrence in file order is kept")
        XCTAssertEqual(plan.folders.map(\.title), ["Bookmarks bar"], "\"Sub\" held only the duplicate and is pruned")
    }

    // MARK: - Empty import

    func testImportWhereEveryAddressIsAlreadySavedPlansNothing() {
        var existing = BookmarkCollection()
        existing.addBookmark(BookmarkRecord(title: "A", url: "https://a.example/", folderID: nil))
        existing.addBookmark(BookmarkRecord(title: "B", url: "https://b.example/", folderID: nil))

        let imported = BookmarkImport(roots: [
            ImportedFolder(title: "Bookmarks bar", children: [
                bookmark("A", "https://a.example/"),
                folder("Sub", [bookmark("B", "https://b.example/")])
            ])
        ])

        let plan = BookmarkImportMergePlanner.plan(imported, into: existing)

        XCTAssertTrue(plan.isEmpty)
        XCTAssertTrue(plan.folders.isEmpty, "no folder — not even an empty destination — should be planned")
        XCTAssertTrue(plan.bookmarks.isEmpty)
        XCTAssertEqual(plan.skippedExistingCount, 2)
        XCTAssertEqual(plan.sourceBookmarkCount, 2, "\"found\" still reports what was actually in the file")
    }

    // MARK: - Source counts

    func testSourceCountsReflectTheWholeImportRegardlessOfSkipping() {
        var existing = BookmarkCollection()
        existing.addBookmark(BookmarkRecord(title: "A", url: "https://a.example/", folderID: nil))

        let imported = BookmarkImport(roots: [
            ImportedFolder(title: "Bookmarks bar", children: [
                bookmark("A", "https://a.example/"),
                folder("Sub", [bookmark("B", "https://b.example/")])
            ])
        ])

        let plan = BookmarkImportMergePlanner.plan(imported, into: existing)

        XCTAssertEqual(plan.sourceBookmarkCount, 2)
        XCTAssertEqual(plan.sourceFolderCount, 1, "\"Sub\" only; the root is not counted, matching BookmarkImport.folderCount")
    }
}
