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

    /// The dated container's real title is built in the browser target from
    /// the source name and today's date; the planner only ever passes it
    /// through, so the tests use a fixed stand-in.
    private static let importFolderTitle = "Imported"

    private func plan(
        _ imported: BookmarkImport,
        into existing: BookmarkCollection = BookmarkCollection(),
        placement: BookmarkImportPlacement = .singleFolder
    ) -> BookmarkImportPlan {
        BookmarkImportMergePlanner.plan(
            imported,
            into: existing,
            placement: placement,
            importFolderTitle: Self.importFolderTitle
        )
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

        let plan = plan(imported, into: existing)

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

        let plan = plan(imported)

        XCTAssertEqual(
            plan.folders.map(\.title), ["Imported", "Work", "Reading"],
            "the source's own \"Bookmarks bar\" level is collapsed away — it is a container the exporting browser wrote, not a folder anybody made"
        )
        XCTAssertEqual(plan.importFolderIndex, 0)
        XCTAssertNil(plan.folders[0].parentIndex, "the dated container itself sits at the top level")
        XCTAssertEqual(plan.folders[1].parentIndex, 0, "\"Work\" nests inside the dated container")
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

        let plan = plan(imported, into: existing)

        XCTAssertEqual(plan.folders.map(\.title), ["Imported", "Survives"])
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

        let plan = plan(imported, into: existing)

        XCTAssertEqual(
            plan.folders.map(\.title), ["Imported"],
            "\"Other bookmarks\" held only a skipped address, so one root survives and collapses"
        )
        XCTAssertEqual(plan.bookmarks.map(\.parentIndex), [0], "its one bookmark lands in the dated container")
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

        let plan = plan(imported)

        XCTAssertEqual(plan.addedCount, 1)
        XCTAssertEqual(plan.duplicateWithinImportCount, 1)
        XCTAssertEqual(plan.bookmarks.map(\.title), ["First copy"], "the first occurrence in file order is kept")
        XCTAssertEqual(plan.folders.map(\.title), ["Imported"], "\"Sub\" held only the duplicate and is pruned")
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

        let plan = plan(imported, into: existing)

        XCTAssertTrue(plan.isEmpty)
        XCTAssertTrue(plan.folders.isEmpty, "no folder — not even an empty dated container — should be planned")
        XCTAssertNil(plan.importFolderIndex)
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

        let plan = plan(imported, into: existing)

        XCTAssertEqual(plan.sourceBookmarkCount, 2)
        XCTAssertEqual(plan.sourceFolderCount, 1, "\"Sub\" only; the root is not counted, matching BookmarkImport.folderCount")
    }

    // MARK: - Bar placement

    private func chromeShapedImport() -> BookmarkImport {
        BookmarkImport(roots: [
            ImportedFolder(title: "Bookmarks bar", children: [
                folder("Projects", [bookmark("P", "https://p.example/")]),
                folder("AI", [bookmark("A", "https://a.example/")]),
                bookmark("Loose", "https://loose.example/")
            ], role: .bookmarksBar),
            ImportedFolder(title: "Other bookmarks", children: [
                bookmark("O", "https://o.example/")
            ]),
            ImportedFolder(title: "Mobile bookmarks", children: [
                bookmark("M", "https://m.example/")
            ])
        ])
    }

    /// The founder's actual complaint, stated as a test: in Chrome his bar
    /// *is* his folders, one click each, and an import that buries them is
    /// not the shape he asked for.
    func testBarPlacementPutsTheSourcesBarFoldersOnTheBar() {
        let plan = plan(chromeShapedImport(), placement: .bookmarksBar)

        XCTAssertEqual(plan.folders[0].title, "Projects")
        XCTAssertNil(plan.folders[0].parentIndex, "one click from the bar, not three")
        XCTAssertEqual(plan.folders[1].title, "AI")
        XCTAssertNil(plan.folders[1].parentIndex)
        XCTAssertFalse(
            plan.folders.contains { $0.title == "Bookmarks bar" },
            "the source's own bar container is never recreated as a folder"
        )
        XCTAssertEqual(
            plan.bookmarks.first { $0.url == "https://loose.example/" }?.parentIndex, nil,
            "a bookmark loose on the source's bar stays loose on ours"
        )
    }

    /// Everything the source kept somewhere other than its bar goes into one
    /// dated chip, appended last so it never pushes the bar folders along.
    func testBarPlacementCollectsNonBarRootsIntoOneDatedFolder() {
        let plan = plan(chromeShapedImport(), placement: .bookmarksBar)

        let container = try? XCTUnwrap(plan.importFolderIndex)
        XCTAssertEqual(plan.folders[container ?? -1].title, Self.importFolderTitle)
        XCTAssertNil(plan.folders[container ?? -1].parentIndex, "the dated folder is itself a chip on the bar")
        XCTAssertEqual(
            container, plan.folders.count - 3,
            "it is appended after the bar folders, and holds the two leftover roots"
        )

        let leftovers = plan.folders.filter { $0.parentIndex == container }
        XCTAssertEqual(leftovers.map(\.title), ["Other bookmarks", "Mobile bookmarks"], "in source order, names kept")
    }

    /// A desktop-only person has no mobile bookmarks, and should not get an
    /// empty chip advertising that.
    func testBarPlacementDropsARootThatPrunedToNothing() {
        var existing = BookmarkCollection()
        existing.addBookmark(BookmarkRecord(title: "M", url: "https://m.example/", folderID: nil))

        let plan = plan(chromeShapedImport(), into: existing, placement: .bookmarksBar)

        XCTAssertFalse(plan.folders.contains { $0.title == "Mobile bookmarks" })
        XCTAssertEqual(plan.skippedExistingCount, 1)
    }

    /// With nothing left over, there is no dated chip at all — the import is
    /// simply the person's bar.
    func testBarPlacementWithEverythingOnTheSourcesBarCreatesNoDatedFolder() {
        let imported = BookmarkImport(roots: [
            ImportedFolder(title: "Bookmarks bar", children: [
                folder("Projects", [bookmark("P", "https://p.example/")])
            ], role: .bookmarksBar)
        ])

        let plan = plan(imported, placement: .bookmarksBar)

        XCTAssertNil(plan.importFolderIndex)
        XCTAssertEqual(plan.folders.map(\.title), ["Projects"])
    }

    /// An older export names no bar. One surviving root is unambiguously
    /// the one place that person kept bookmarks, so it goes on the bar.
    func testBarPlacementWithNoDeclaredBarAndOneRootUnwrapsThatRoot() {
        let imported = BookmarkImport(roots: [
            ImportedFolder(title: "Bookmarks", children: [
                folder("Work", [bookmark("W", "https://w.example/")])
            ])
        ])

        let plan = plan(imported, placement: .bookmarksBar)

        XCTAssertEqual(plan.folders.map(\.title), ["Work"])
        XCTAssertNil(plan.importFolderIndex)
    }

    /// Several roots and no marker: Clearframe does not pick one by reading
    /// its title. Everything goes into the dated folder instead.
    func testBarPlacementWithNoDeclaredBarAndSeveralRootsNeverGuesses() {
        let imported = BookmarkImport(roots: [
            ImportedFolder(title: "Bookmarks bar", children: [bookmark("A", "https://a.example/")]),
            ImportedFolder(title: "Other bookmarks", children: [bookmark("B", "https://b.example/")])
        ])

        let plan = plan(imported, placement: .bookmarksBar)

        XCTAssertEqual(plan.importFolderIndex, 0)
        XCTAssertEqual(
            plan.folders.map(\.title), [Self.importFolderTitle, "Bookmarks bar", "Other bookmarks"],
            "a folder merely named like a bar is not treated as one"
        )
    }

    /// The declared bar pruning away must not let the single-root rule
    /// promote some unrelated root in its place.
    func testBarPlacementWhoseDeclaredBarPrunedAwayUnwrapsNothing() {
        var existing = BookmarkCollection()
        existing.addBookmark(BookmarkRecord(title: "P", url: "https://p.example/", folderID: nil))

        let imported = BookmarkImport(roots: [
            ImportedFolder(title: "Bookmarks bar", children: [
                bookmark("P", "https://p.example/")
            ], role: .bookmarksBar),
            ImportedFolder(title: "Other bookmarks", children: [
                bookmark("O", "https://o.example/")
            ])
        ])

        let plan = plan(imported, into: existing, placement: .bookmarksBar)

        XCTAssertEqual(plan.importFolderIndex, 0)
        XCTAssertEqual(plan.folders.map(\.title), [Self.importFolderTitle, "Other bookmarks"])
    }

    // MARK: - Placement does not change what is skipped

    /// Skipping is keyed on the address; where a new bookmark lands has
    /// nothing to do with it. If these two ever diverge, one placement is
    /// quietly clobbering something the other does not.
    func testSkippingAndCountsAreIdenticalInBothPlacements() {
        var existing = BookmarkCollection()
        existing.addBookmark(BookmarkRecord(title: "Mine", url: "https://p.example/", folderID: nil))

        let bar = plan(chromeShapedImport(), into: existing, placement: .bookmarksBar)
        let single = plan(chromeShapedImport(), into: existing, placement: .singleFolder)

        XCTAssertEqual(bar.addedCount, single.addedCount)
        XCTAssertEqual(bar.skippedExistingCount, single.skippedExistingCount)
        XCTAssertEqual(bar.duplicateWithinImportCount, single.duplicateWithinImportCount)
        XCTAssertEqual(bar.sourceBookmarkCount, single.sourceBookmarkCount)
        XCTAssertEqual(bar.sourceFolderCount, single.sourceFolderCount)
        XCTAssertEqual(
            Set(bar.bookmarks.map(\.url)), Set(single.bookmarks.map(\.url)),
            "the same addresses are added either way — only their placement differs"
        )
    }

    // MARK: - Name collisions

    func testBarTitleCollisionsAreReportedCaseInsensitivelyAndDeduplicated() {
        var existing = BookmarkCollection()
        _ = existing.createFolder(title: "ai", iconID: "folder", parentID: nil)
        _ = existing.createFolder(title: "Unrelated", iconID: "folder", parentID: nil)

        let plan = plan(chromeShapedImport(), into: existing, placement: .bookmarksBar)

        XCTAssertEqual(plan.barTitleCollisions, ["AI"], "reported with the imported spelling, matched case-insensitively")
    }

    func testACollisionIsReportedButNeverMergedOrRenamed() {
        var existing = BookmarkCollection()
        _ = existing.createFolder(title: "AI", iconID: "folder", parentID: nil)

        let plan = plan(chromeShapedImport(), into: existing, placement: .bookmarksBar)

        XCTAssertEqual(plan.barTitleCollisions, ["AI"])
        XCTAssertEqual(
            plan.folders.filter { $0.parentIndex == nil }.map(\.title).filter { $0 == "AI" }, ["AI"],
            "the imported folder keeps its own name — never \"AI (2)\", which would misname somebody's folder"
        )
    }

    func testNoCollisionsWhenNothingIsOnTheBar() {
        XCTAssertTrue(plan(chromeShapedImport(), placement: .bookmarksBar).barTitleCollisions.isEmpty)
    }

    // MARK: - Which placement is offered first

    func testRecommendedPlacementIsTheBarOnlyWhenNothingIsOnItYet() {
        XCTAssertEqual(BookmarkImportMergePlanner.recommendedPlacement(for: BookmarkCollection()), .bookmarksBar)

        var withFolder = BookmarkCollection()
        _ = withFolder.createFolder(title: "Mine", iconID: "folder", parentID: nil)
        XCTAssertEqual(BookmarkImportMergePlanner.recommendedPlacement(for: withFolder), .singleFolder)

        var withLooseBookmark = BookmarkCollection()
        withLooseBookmark.addBookmark(BookmarkRecord(title: "Mine", url: "https://mine.example/", folderID: nil))
        XCTAssertEqual(
            BookmarkImportMergePlanner.recommendedPlacement(for: withLooseBookmark), .singleFolder,
            "a bar holding loose bookmarks but no folders is still not empty"
        )
    }

    // MARK: - Purity

    func testPlanningDoesNotMutateTheCollectionItPlansAgainst() {
        var existing = BookmarkCollection()
        _ = existing.createFolder(title: "Mine", iconID: "folder", parentID: nil)
        existing.addBookmark(BookmarkRecord(title: "Mine", url: "https://mine.example/", folderID: nil))
        let before = existing

        _ = plan(chromeShapedImport(), into: existing, placement: .bookmarksBar)
        _ = plan(chromeShapedImport(), into: existing, placement: .singleFolder)

        XCTAssertEqual(existing.folders, before.folders)
        XCTAssertEqual(existing.bookmarks, before.bookmarks)
    }
}
