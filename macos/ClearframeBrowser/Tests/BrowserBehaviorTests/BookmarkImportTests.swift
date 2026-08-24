import ClearframeCore
import Foundation
import XCTest
@testable import ClearframeBrowser

/// The interface half of bookmark import/export: applying a
/// `BookmarkImportPlan` to a real `BrowserDataStore`, undoing it, source
/// discovery, and the destination folder's name. The plan itself — what
/// should be added, skipped, and pruned — is pure logic tested against no
/// store at all, in `ClearframeCoreTests/BookmarkImportMergeTests.swift`.
@MainActor
final class BookmarkImportTests: XCTestCase {
    private func makeStore() throws -> (store: BrowserDataStore, suiteName: String, defaults: UserDefaults) {
        let suiteName = "clearframe.bookmarks.import.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        return (BrowserDataStore(defaults: defaults), suiteName, defaults)
    }

    private static let importFolderTitle = "Imported from Chrome — 21 August 2026"

    private func plan(
        _ imported: BookmarkImport,
        into store: BrowserDataStore,
        placement: BookmarkImportPlacement = .singleFolder
    ) -> BookmarkImportPlan {
        BookmarkImportMergePlanner.plan(
            imported,
            into: BookmarkCollection(folders: store.bookmarkFolders, bookmarks: store.bookmarks),
            placement: placement,
            importFolderTitle: Self.importFolderTitle
        )
    }

    // MARK: - An already-saved address is left untouched

    /// The single most important rule this feature protects, exercised end
    /// to end: `BookmarkCollection.addBookmark` replaces any bookmark
    /// already at the same address, which would otherwise delete this
    /// person's own bookmark and relocate it into the import. After
    /// applying, the existing record must be the exact same record — same
    /// id, same folder, same title — and the import's own copy of that
    /// address must not exist anywhere in the store.
    func testApplyingAnImportLeavesAnAlreadySavedBookmarkCompletelyUntouched() throws {
        let (store, suiteName, defaults) = try makeStore()
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }

        let ownFolder = try XCTUnwrap(store.createBookmarkFolder(title: "My Own Folder", iconID: "folder", parentID: nil))
        let existing = try XCTUnwrap(store.addBookmark(title: "My Notes", url: "https://example.com/notes", folderID: ownFolder.id))

        let imported = BookmarkImport(roots: [
            ImportedFolder(title: "Bookmarks bar", children: [
                .bookmark(ImportedBookmark(title: "Notes (renamed)", url: "https://example.com/notes", addedAt: nil)),
                .bookmark(ImportedBookmark(title: "New Page", url: "https://example.com/new", addedAt: nil))
            ])
        ])
        let mergePlan = plan(imported, into: store)
        let result = BookmarkImportApplier.apply(mergePlan, into: store)

        let stillExisting = try XCTUnwrap(store.bookmarks.first { $0.id == existing.id })
        XCTAssertEqual(stillExisting.id, existing.id)
        XCTAssertEqual(stillExisting.folderID, ownFolder.id)
        XCTAssertEqual(stillExisting.title, "My Notes")
        XCTAssertEqual(stillExisting.createdAt, existing.createdAt)
        XCTAssertEqual(store.bookmarks.filter { $0.url == "https://example.com/notes" }.count, 1, "no second copy anywhere")

        XCTAssertEqual(result.addedCount, 1)
        XCTAssertEqual(result.skippedExistingCount, 1)
        let added = try XCTUnwrap(store.bookmarks.first { $0.url == "https://example.com/new" })
        XCTAssertNotEqual(added.folderID, ownFolder.id, "the import never files into a folder that already existed")
    }

    // MARK: - Folder structure preserved beneath one destination folder

    func testApplyingAnImportPreservesNestedFolderStructureUnderOneDestinationFolder() throws {
        let (store, suiteName, defaults) = try makeStore()
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }

        let imported = BookmarkImport(roots: [
            ImportedFolder(title: "Bookmarks bar", children: [
                .folder(ImportedFolder(title: "Work", children: [
                    .folder(ImportedFolder(title: "Reading", children: [
                        .bookmark(ImportedBookmark(title: "Article", url: "https://example.com/article", addedAt: nil))
                    ]))
                ]))
            ])
        ])
        let mergePlan = plan(imported, into: store)
        let result = BookmarkImportApplier.apply(mergePlan, into: store)

        let destination = try XCTUnwrap(result.importFolderID.flatMap(store.bookmarkFolder(id:)))
        XCTAssertNil(destination.parentID, "the dated container is a new top-level folder")
        XCTAssertEqual(destination.title, "Imported from Chrome — 21 August 2026")
        XCTAssertEqual(
            result.createdFolderIDs.count, 3,
            "the dated container, Work, Reading — the source's own \"Bookmarks bar\" level is collapsed away"
        )

        let work = try XCTUnwrap(result.createdFolderIDs[1].flatMap(store.bookmarkFolder(id:)))
        let reading = try XCTUnwrap(result.createdFolderIDs[2].flatMap(store.bookmarkFolder(id:)))
        XCTAssertEqual(result.createdFolderIDs[0], destination.id)
        XCTAssertEqual(work.title, "Work")
        XCTAssertEqual(work.parentID, destination.id, "\"Work\" is one click inside, not two")
        XCTAssertEqual(reading.title, "Reading")
        XCTAssertEqual(reading.parentID, work.id)
        XCTAssertFalse(
            store.bookmarkFolders.contains { $0.title == "Bookmarks bar" },
            "no folder is created for the container the exporting browser wrote"
        )

        let article = try XCTUnwrap(store.bookmarks.first { $0.url == "https://example.com/article" })
        XCTAssertEqual(article.folderID, reading.id, "filed exactly where the source had it, not flattened")
    }

    // MARK: - Nothing already saved is ever merged into

    func testApplyingNeverAddsAnythingIntoAFolderThatAlreadyExisted() throws {
        let (store, suiteName, defaults) = try makeStore()
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }
        let handMade = try XCTUnwrap(store.createBookmarkFolder(title: "Work", iconID: "folder", parentID: nil))

        let imported = BookmarkImport(roots: [
            ImportedFolder(title: "Bookmarks bar", children: [
                .folder(ImportedFolder(title: "Work", children: [
                    .bookmark(ImportedBookmark(title: "New", url: "https://example.com/new", addedAt: nil))
                ]))
            ])
        ])
        let mergePlan = plan(imported, into: store)
        _ = BookmarkImportApplier.apply(mergePlan, into: store)

        XCTAssertFalse(store.bookmarkFolderContainsItems(handMade), "a same-named existing folder is never reused")
        XCTAssertEqual(store.bookmarkFolders.filter { $0.title == "Work" }.count, 2, "a new folder is created instead")
    }

    // MARK: - Empty import creates no folder

    func testApplyingAnEmptyPlanCreatesNoFolder() throws {
        let (store, suiteName, defaults) = try makeStore()
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }
        _ = store.addBookmark(title: "A", url: "https://a.example/", folderID: nil)

        let imported = BookmarkImport(roots: [
            ImportedFolder(title: "Bookmarks bar", children: [.bookmark(ImportedBookmark(title: "A", url: "https://a.example/", addedAt: nil))])
        ])
        let mergePlan = plan(imported, into: store)
        XCTAssertTrue(mergePlan.isEmpty)

        let folderCountBefore = store.bookmarkFolders.count
        let result = BookmarkImportApplier.apply(mergePlan, into: store)

        XCTAssertNil(result.importFolderID)
        XCTAssertEqual(result.addedCount, 0)
        XCTAssertEqual(store.bookmarkFolders.count, folderCountBefore, "not even an empty destination folder is created")
    }

    // MARK: - Undo restores the original tree exactly

    /// The undo story the preview and result screens both promise: removing
    /// the destination folder undoes the whole import. This asserts it is
    /// literally true — full array equality, order included — not merely
    /// that no bookmark or folder from the import survives.
    func testUndoingAnImportRestoresTheOriginalTreeExactly() throws {
        let (store, suiteName, defaults) = try makeStore()
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }

        let personal = try XCTUnwrap(store.createBookmarkFolder(title: "Personal", iconID: "folder", parentID: nil))
        _ = store.addBookmark(title: "Existing", url: "https://existing.example/", folderID: personal.id)
        _ = store.addBookmark(title: "Loose", url: "https://loose.example/", folderID: nil)

        let beforeBookmarks = store.bookmarks
        let beforeFolders = store.bookmarkFolders

        let imported = BookmarkImport(roots: [
            ImportedFolder(title: "Bookmarks bar", children: [
                .folder(ImportedFolder(title: "Work", children: [
                    .bookmark(ImportedBookmark(title: "Docs", url: "https://docs.example/", addedAt: nil))
                ])),
                .bookmark(ImportedBookmark(title: "Top", url: "https://top.example/", addedAt: nil))
            ])
        ])
        let mergePlan = plan(imported, into: store)
        let result = BookmarkImportApplier.apply(mergePlan, into: store)

        XCTAssertGreaterThan(store.bookmarks.count, beforeBookmarks.count)
        XCTAssertGreaterThan(store.bookmarkFolders.count, beforeFolders.count)

        BookmarkImportApplier.undo(result, in: store)

        XCTAssertEqual(store.bookmarks, beforeBookmarks, "every pre-existing bookmark, unchanged, nothing left behind")
        XCTAssertEqual(store.bookmarkFolders, beforeFolders, "every pre-existing folder, unchanged, nothing left behind")
    }

    // MARK: - Bar placement, against a real store

    private func chromeShapedImport() -> BookmarkImport {
        BookmarkImport(roots: [
            ImportedFolder(title: "Bookmarks bar", children: [
                .folder(ImportedFolder(title: "Projects", children: [
                    .bookmark(ImportedBookmark(title: "P", url: "https://p.example/", addedAt: nil))
                ])),
                .folder(ImportedFolder(title: "AI", children: [
                    .bookmark(ImportedBookmark(title: "A", url: "https://a.example/", addedAt: nil))
                ]))
            ], role: .bookmarksBar),
            ImportedFolder(title: "Other bookmarks", children: [
                .bookmark(ImportedBookmark(title: "O", url: "https://o.example/", addedAt: nil))
            ])
        ])
    }

    /// The ordering guarantee that matters most: an import appends to the
    /// bar and never renumbers what is already on it. Both creation
    /// primitives only ever append, and the applier must never reach for the
    /// move-to-index calls that renumber a whole sibling row.
    func testBarPlacementAppendsAfterTheUsersOwnFoldersWithoutRenumberingThem() throws {
        let (store, suiteName, defaults) = try makeStore()
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }

        let a = try XCTUnwrap(store.createBookmarkFolder(title: "Mine A", iconID: "folder", parentID: nil))
        let b = try XCTUnwrap(store.createBookmarkFolder(title: "Mine B", iconID: "folder", parentID: nil))
        let positionsBefore = store.bookmarkFolders.filter { $0.parentID == nil }.map(\.position)

        let mergePlan = plan(chromeShapedImport(), into: store, placement: .bookmarksBar)
        _ = BookmarkImportApplier.apply(mergePlan, into: store)

        XCTAssertEqual(
            store.bookmarkFolders(in: nil).map(\.title),
            ["Mine A", "Mine B", "Projects", "AI", Self.importFolderTitle],
            "the person's own folders keep their order, and the import lands after them"
        )
        let stillA = try XCTUnwrap(store.bookmarkFolder(id: a.id))
        let stillB = try XCTUnwrap(store.bookmarkFolder(id: b.id))
        XCTAssertEqual([stillA.position, stillB.position], positionsBefore, "no existing position is rewritten")
    }

    /// Bar placement makes the import a sibling of the person's own
    /// bookmarks for the first time. The skip rule must still hold, and it
    /// must hold for a bookmark loose on the bar, not only one in a folder.
    func testBarPlacementLeavesAnAlreadySavedLooseBarBookmarkUntouched() throws {
        let (store, suiteName, defaults) = try makeStore()
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }

        let mine = try XCTUnwrap(store.addBookmark(title: "My Name For It", url: "https://p.example/", folderID: nil))

        let mergePlan = plan(chromeShapedImport(), into: store, placement: .bookmarksBar)
        _ = BookmarkImportApplier.apply(mergePlan, into: store)

        let still = try XCTUnwrap(store.bookmarks.first { $0.id == mine.id })
        XCTAssertEqual(still.title, "My Name For It", "not renamed to the import's title")
        XCTAssertNil(still.folderID, "not relocated into an imported folder")
        XCTAssertEqual(store.bookmarks.filter { $0.url == "https://p.example/" }.count, 1)
    }

    /// The most important new test: bar placement spreads the import across
    /// the bar rather than into one deletable folder, so undo has to put
    /// every one of the person's own records back exactly — same order,
    /// same positions, same ids.
    func testUndoingABarPlacementImportRestoresTheOriginalTreeExactly() throws {
        let (store, suiteName, defaults) = try makeStore()
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }

        let personal = try XCTUnwrap(store.createBookmarkFolder(title: "Personal", iconID: "folder", parentID: nil))
        _ = store.addBookmark(title: "Existing", url: "https://existing.example/", folderID: personal.id)
        _ = store.addBookmark(title: "Loose", url: "https://loose.example/", folderID: nil)

        let beforeBookmarks = store.bookmarks
        let beforeFolders = store.bookmarkFolders

        let mergePlan = plan(chromeShapedImport(), into: store, placement: .bookmarksBar)
        let result = BookmarkImportApplier.apply(mergePlan, into: store)

        XCTAssertGreaterThan(store.bookmarkFolders(in: nil).count, beforeFolders.filter { $0.parentID == nil }.count)

        BookmarkImportApplier.undo(result, in: store)

        XCTAssertEqual(store.bookmarks, beforeBookmarks, "every pre-existing bookmark, unchanged, nothing left behind")
        XCTAssertEqual(store.bookmarkFolders, beforeFolders, "every pre-existing folder, unchanged, nothing left behind")
    }

    /// Re-importing the same profile is the founder's likely next action
    /// after trying this once. It must add nothing at all — no duplicate
    /// chips, no second dated folder.
    func testReimportingTheSameSourceAddsNothing() throws {
        let (store, suiteName, defaults) = try makeStore()
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }

        _ = BookmarkImportApplier.apply(plan(chromeShapedImport(), into: store, placement: .bookmarksBar), into: store)
        let foldersAfterFirst = store.bookmarkFolders
        let bookmarksAfterFirst = store.bookmarks

        let second = plan(chromeShapedImport(), into: store, placement: .bookmarksBar)
        XCTAssertTrue(second.isEmpty, "every address is already saved")
        let result = BookmarkImportApplier.apply(second, into: store)

        XCTAssertEqual(result.addedCount, 0)
        XCTAssertNil(result.importFolderID)
        XCTAssertEqual(store.bookmarkFolders, foldersAfterFirst, "no second dated folder, no duplicate chips")
        XCTAssertEqual(store.bookmarks, bookmarksAfterFirst)
    }

    /// A collision produces two chips, both intact — never a merge, never a
    /// rename of somebody's own folder.
    func testBarPlacementNeverMergesIntoAnExistingSameNamedBarFolder() throws {
        let (store, suiteName, defaults) = try makeStore()
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }

        let mine = try XCTUnwrap(store.createBookmarkFolder(title: "AI", iconID: "folder", parentID: nil))
        _ = store.addBookmark(title: "My AI Link", url: "https://mine.example/", folderID: mine.id)

        let mergePlan = plan(chromeShapedImport(), into: store, placement: .bookmarksBar)
        XCTAssertEqual(mergePlan.barTitleCollisions, ["AI"], "the preview is told before anything is written")
        _ = BookmarkImportApplier.apply(mergePlan, into: store)

        XCTAssertEqual(store.bookmarkFolders(in: nil).filter { $0.title == "AI" }.count, 2)
        let stillMine = try XCTUnwrap(store.bookmarkFolder(id: mine.id))
        XCTAssertEqual(stillMine.title, "AI", "the person's own folder is never renamed to make room")
        XCTAssertEqual(
            store.bookmarks(in: mine.id).map(\.url), ["https://mine.example/"],
            "and nothing imported is filed into it"
        )
    }

    // MARK: - Batched writes

    /// A batch defers writing, never the records themselves: the applier
    /// reads folder ids back out of the store while the batch is still open,
    /// so anything that made those calls return stale data would file every
    /// imported bookmark in the wrong place.
    func testRecordsAreReadableInsideABatchBeforeAnythingIsWritten() throws {
        let (store, suiteName, defaults) = try makeStore()
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }

        var seenInside: BookmarkFolderRecord?
        store.performBatch {
            guard let made = store.createBookmarkFolder(title: "Inside", iconID: "folder", parentID: nil) else { return }
            seenInside = store.bookmarkFolder(id: made.id)
            _ = store.addBookmark(title: "Child", url: "https://inside.example/", folderID: made.id)
            XCTAssertEqual(store.bookmarks(in: made.id).count, 1, "reads inside the batch see the new records")
        }

        XCTAssertEqual(seenInside?.title, "Inside")
        XCTAssertEqual(store.bookmarkFolders(in: nil).map(\.title), ["Inside"])
    }

    /// What the batch exists for: the whole import reaches disk, once.
    func testABatchedImportPersistsEverythingItCreated() throws {
        let (store, suiteName, defaults) = try makeStore()
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }

        let mergePlan = plan(chromeShapedImport(), into: store, placement: .bookmarksBar)
        _ = BookmarkImportApplier.apply(mergePlan, into: store)

        let reopened = BrowserDataStore(defaults: defaults)
        XCTAssertEqual(
            reopened.bookmarks.count, store.bookmarks.count,
            "a batched import is on disk by the time apply returns"
        )
        XCTAssertEqual(reopened.bookmarkFolders.count, store.bookmarkFolders.count)
        XCTAssertEqual(
            Set(reopened.bookmarkFolders(in: nil).map(\.title)),
            Set(store.bookmarkFolders(in: nil).map(\.title))
        )
    }

    func testUndoingABatchedImportPersistsTheRemoval() throws {
        let (store, suiteName, defaults) = try makeStore()
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }

        let result = BookmarkImportApplier.apply(
            plan(chromeShapedImport(), into: store, placement: .bookmarksBar),
            into: store
        )
        BookmarkImportApplier.undo(result, in: store)

        let reopened = BrowserDataStore(defaults: defaults)
        XCTAssertTrue(reopened.bookmarks.isEmpty, "undo reached disk too")
        XCTAssertTrue(reopened.bookmarkFolders.isEmpty)
    }

    /// Renaming a bookmark used to re-encode every folder as well.
    func testABookmarkOnlyChangeDoesNotRewriteTheFolders() throws {
        let (store, suiteName, defaults) = try makeStore()
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }

        _ = store.createBookmarkFolder(title: "Kept", iconID: "folder", parentID: nil)
        let bookmark = try XCTUnwrap(store.addBookmark(title: "Before", url: "https://rename.example/", folderID: nil))
        let foldersOnDisk = try XCTUnwrap(defaults.data(forKey: "clearframe.bookmarkFolders.v2"))

        XCTAssertTrue(store.updateBookmark(id: bookmark.id, title: "After", url: bookmark.url))

        XCTAssertEqual(
            defaults.data(forKey: "clearframe.bookmarkFolders.v2"), foldersOnDisk,
            "the folder blob is untouched when only a bookmark changed"
        )
        let reopened = BrowserDataStore(defaults: defaults)
        XCTAssertEqual(reopened.bookmarks.first?.title, "After", "and the bookmark change still persisted")
        XCTAssertEqual(reopened.bookmarkFolders.map(\.title), ["Kept"])
    }

    // MARK: - Result copy

    func testResultHeadlineNamesBothPlacesUnderBarPlacement() throws {
        let (store, suiteName, defaults) = try makeStore()
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }

        let result = BookmarkImportApplier.apply(
            plan(chromeShapedImport(), into: store, placement: .bookmarksBar),
            into: store
        )

        let headline = BookmarkImportSheet.resultHeadline(result)
        XCTAssertTrue(headline.contains("2 folders on your bookmarks bar"), headline)
        XCTAssertTrue(headline.contains(Self.importFolderTitle), headline)
    }

    /// With nothing left over there is no dated folder, and the copy must
    /// not name one.
    func testResultHeadlineNamesNoFolderWhenTheImportWasEntirelyABar() throws {
        let (store, suiteName, defaults) = try makeStore()
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }

        let imported = BookmarkImport(roots: [
            ImportedFolder(title: "Bookmarks bar", children: [
                .folder(ImportedFolder(title: "Projects", children: [
                    .bookmark(ImportedBookmark(title: "P", url: "https://p.example/", addedAt: nil))
                ]))
            ], role: .bookmarksBar)
        ])
        let result = BookmarkImportApplier.apply(plan(imported, into: store, placement: .bookmarksBar), into: store)

        XCTAssertNil(result.importFolderID)
        let headline = BookmarkImportSheet.resultHeadline(result)
        XCTAssertEqual(headline, "1 bookmark added — 1 folder on your bookmarks bar.")
    }

    /// Undo copy must not promise "nothing else is touched" — a bookmark
    /// moved into an imported folder afterwards is kept, but moves up one
    /// level.
    func testUndoExplanationDoesNotPromiseNothingElseIsTouched() throws {
        let (store, suiteName, defaults) = try makeStore()
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }

        let result = BookmarkImportApplier.apply(
            plan(chromeShapedImport(), into: store, placement: .bookmarksBar),
            into: store
        )

        let copy = BookmarkImportSheet.undoExplanation(result)
        XCTAssertTrue(copy.contains("move up one level"), copy)
        XCTAssertFalse(copy.contains("Nothing else is touched"), copy)
    }

    // MARK: - Destination folder naming

    func testDestinationFolderTitleFormatsSourceAndDateAsSpecified() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 21
        components.hour = 12
        let date = try XCTUnwrap(Calendar.current.date(from: components))

        XCTAssertEqual(
            BookmarkImportFolderNaming.destinationFolderTitle(sourceLabel: "Chrome", date: date),
            "Imported from Chrome — 21 August 2026"
        )
    }

    // MARK: - Chromium profile naming

    func testChromiumProfileNamingReadsDisplayNamesFromASyntheticLocalState() throws {
        let localState = try JSONSerialization.data(withJSONObject: [
            "profile": ["info_cache": [
                "Default": ["name": "Lucian Roman"],
                "Profile 1": ["name": "Work"]
            ]]
        ])
        XCTAssertEqual(ChromiumProfileNaming.displayName(forProfileDirectory: "Default", localState: localState), "Lucian Roman")
        XCTAssertEqual(ChromiumProfileNaming.displayName(forProfileDirectory: "Profile 1", localState: localState), "Work")
    }

    func testChromiumProfileNamingFallsBackToDirectoryNameWhenTheEntryIsMissing() throws {
        let localState = try JSONSerialization.data(withJSONObject: ["profile": ["info_cache": ["Default": ["name": "Lucian Roman"]]]])
        XCTAssertEqual(ChromiumProfileNaming.displayName(forProfileDirectory: "Profile 7", localState: localState), "Profile 7")
    }

    func testChromiumProfileNamingFallsBackToDirectoryNameWhenLocalStateIsMissingOrMalformed() {
        XCTAssertEqual(ChromiumProfileNaming.displayName(forProfileDirectory: "Profile 2", localState: nil), "Profile 2")
        let malformed = Data("not json at all {{{".utf8)
        XCTAssertEqual(ChromiumProfileNaming.displayName(forProfileDirectory: "Profile 2", localState: malformed), "Profile 2")
        XCTAssertTrue(ChromiumProfileNaming.displayNames(fromLocalState: malformed).isEmpty)
    }

    // MARK: - Source discovery

    /// A synthetic profile tree — never the real `~/Library/Application
    /// Support`, which is personal, machine-specific data. Covers what this
    /// Mac's real Chrome install has for real: several numbered profiles
    /// alongside "Default", not just one.
    func testDetectSourcesFindsMultipleChromiumProfilesAndAlwaysOffersSafariAndFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let chrome = root.appendingPathComponent("Google/Chrome")
        try FileManager.default.createDirectory(at: chrome.appendingPathComponent("Default"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: chrome.appendingPathComponent("Profile 1"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: chrome.appendingPathComponent("Profile 2"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: chrome.appendingPathComponent("Default/Bookmarks"))
        try Data("{}".utf8).write(to: chrome.appendingPathComponent("Profile 1/Bookmarks"))
        // "Profile 2" deliberately has no Bookmarks file yet and must not appear.
        let localState = try JSONSerialization.data(withJSONObject: [
            "profile": ["info_cache": [
                "Default": ["name": "Lucian Roman"],
                "Profile 1": ["name": "Work"]
            ]]
        ])
        try localState.write(to: chrome.appendingPathComponent("Local State"))

        let sources = BookmarkImportSourceDiscovery.detectSources(applicationSupportOverride: root)

        let chromeSources = sources.filter { $0.id.hasPrefix("Google/Chrome/") }
        XCTAssertEqual(chromeSources.map(\.title), ["Chrome — Lucian Roman", "Chrome — Work"], "Default before Profile 1, real names from Local State")
        XCTAssertTrue(chromeSources.allSatisfy { $0.folderNamingLabel == "Chrome" })
        XCTAssertTrue(sources.contains { $0.kind == .safari }, "Safari is always offered")
        XCTAssertTrue(sources.contains { $0.kind == .file }, "\"Choose a file…\" is always offered")
    }

    func testDetectSourcesOrdersNumberedProfilesNumericallyNotLexicographically() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let brave = root.appendingPathComponent("BraveSoftware/Brave-Browser")
        for name in ["Profile 10", "Profile 2", "Default"] {
            try FileManager.default.createDirectory(at: brave.appendingPathComponent(name), withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: brave.appendingPathComponent(name).appendingPathComponent("Bookmarks"))
        }

        let sources = BookmarkImportSourceDiscovery.detectSources(applicationSupportOverride: root)
        let braveTitles = sources.filter { $0.id.hasPrefix("BraveSoftware/") }.map(\.title)

        XCTAssertEqual(braveTitles, ["Brave — Default", "Brave — Profile 2", "Brave — Profile 10"])
    }

    // MARK: - Loading a chosen file

    func testBookmarkSourceLoaderParsesChromiumJSONAndCountsUnusableEntries() {
        let json = """
        {"roots":{"bookmark_bar":{"type":"folder","name":"Bookmarks bar","children":[
            {"type":"url","name":"OK","url":"https://example.com/"},
            {"type":"url","name":"Bad","url":"javascript:alert(1)"}
        ]},"other":{"type":"folder","name":"Other bookmarks","children":[]},
           "synced":{"type":"folder","name":"Mobile bookmarks","children":[]}}}
        """
        switch BookmarkSourceLoader.load(Data(json.utf8)) {
        case .success(let loaded):
            XCTAssertEqual(loaded.imported.bookmarkCount, 1)
            XCTAssertEqual(loaded.unusableCount, 1, "the javascript: entry was in the file but could not be kept")
        case .failure(let message):
            XCTFail("expected success, got \(message)")
        }
    }

    func testBookmarkSourceLoaderGivesAPlainLanguageMessageForAnUnrecognizedFile() {
        switch BookmarkSourceLoader.load(Data("not a bookmarks file at all".utf8)) {
        case .success:
            XCTFail("expected failure")
        case .failure(let message):
            XCTAssertFalse(message.isEmpty)
            XCTAssertFalse(message.contains("BookmarkImportError"), "never a raw parser error")
            XCTAssertFalse(message.contains("malformedJSON"), "never a raw parser error")
        }
    }
}
