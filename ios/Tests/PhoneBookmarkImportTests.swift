import XCTest
import LimeghostCore
@testable import Limeghost
@testable import LimeghostShared

/// Import Bookmarks on the phone. The reading, planning, applying and undoing
/// are the Mac's own code in the shared targets and are tested there; these
/// hold the phone's model to using them, and its words to saying what is true
/// on a phone.
@MainActor
final class PhoneBookmarkImportTests: XCTestCase {
    /// A store of its own, emptied afterwards: these tests run inside the app.
    private func makeStore() throws -> BrowserDataStore {
        let suiteName = "clearframe.iosImport.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return BrowserDataStore(defaults: defaults)
    }

    /// A browser's export as it arrives: its bar, holding a folder and a page
    /// already saved here, and one page it kept off the bar.
    private let exportedHTML = """
    <!DOCTYPE NETSCAPE-Bookmark-file-1>
    <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
    <TITLE>Bookmarks</TITLE>
    <H1>Bookmarks</H1>
    <DL><p>
        <DT><H3 PERSONAL_TOOLBAR_FOLDER="true">Bookmarks Bar</H3>
        <DL><p>
            <DT><H3>Work</H3>
            <DL><p>
                <DT><A HREF="https://example.com/work">Work page</A>
            </DL><p>
            <DT><A HREF="https://example.com/saved">Already saved</A>
        </DL><p>
        <DT><A HREF="https://example.com/other">Kept off the bar</A>
    </DL><p>
    """

    /// The export as a file somewhere outside the app, which is how the
    /// Files picker hands one over.
    private func exportedFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("limeghost-import-\(UUID().uuidString).html")
        try Data(exportedHTML.utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private struct DidNotRead: Error {}

    private func preview(
        _ reading: BookmarkImportModel.Reading,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> BookmarkImportPreview {
        switch reading {
        case .preview(let preview):
            return preview
        case .problem(let message):
            XCTFail("the file did not read: \(message)", file: file, line: line)
            throw DidNotRead()
        }
    }

    private func problem(_ reading: BookmarkImportModel.Reading) -> String? {
        if case .problem(let message) = reading { return message }
        return nil
    }

    // MARK: - Reading and planning

    /// A chosen file is planned against what is already saved: an address
    /// already here is counted and left alone, and nothing is written until
    /// Import.
    func testAChosenFileIsPlannedAgainstWhatIsAlreadySaved() throws {
        let store = try makeStore()
        XCTAssertNotNil(store.addBookmark(title: "Mine", url: "https://example.com/saved", folderID: nil))
        let model = BookmarkImportModel(store: store)

        let plan = try preview(model.read(exportedFile())).plan(.singleFolder)

        XCTAssertEqual(plan.sourceBookmarkCount, 3)
        XCTAssertEqual(plan.addedCount, 2)
        XCTAssertEqual(plan.skippedExistingCount, 1)
        XCTAssertEqual(store.bookmarks.map(\.title), ["Mine"], "the store changed before Import")
    }

    /// Somebody arriving with nothing saved wants their old bar at the top;
    /// somebody with bookmarks already arranged wants one folder they can
    /// remove in one go. The Mac's rule, unchanged.
    func testTheSuggestedPlaceFollowsWhatIsAlreadySaved() throws {
        let store = try makeStore()
        let model = BookmarkImportModel(store: store)
        XCTAssertEqual(model.suggestedPlacement(for: try preview(model.read(exportedFile()))), .bookmarksBar)

        XCTAssertNotNil(store.addBookmark(title: "Mine", url: "https://example.com/mine", folderID: nil))
        XCTAssertEqual(model.suggestedPlacement(for: try preview(model.read(exportedFile()))), .singleFolder)
    }

    // MARK: - Importing and undoing

    /// One new folder holds the whole import, dated, with the source's own
    /// shape beneath it — and Undo takes exactly that away, leaving what was
    /// already saved where it was.
    func testOneFolderHoldsTheImportAndUndoTakesItAway() throws {
        let store = try makeStore()
        XCTAssertNotNil(store.addBookmark(title: "Mine", url: "https://example.com/saved", folderID: nil))
        let model = BookmarkImportModel(store: store)
        let plan = try preview(model.read(exportedFile())).plan(.singleFolder)

        let result = model.apply(plan)

        let top = store.bookmarkFolders(in: nil)
        XCTAssertEqual(top.count, 1)
        XCTAssertTrue(top[0].title.hasPrefix("Imported from a file — "), top[0].title)
        XCTAssertEqual(result.addedCount, 2)

        model.undo(result)

        XCTAssertTrue(store.bookmarkFolders.isEmpty, "undo left a folder behind")
        XCTAssertEqual(store.bookmarks.map(\.title), ["Mine"])
    }

    /// At the top of Bookmarks, the old bar's folders become folders at the
    /// top, and what that browser kept off its bar goes into the dated folder
    /// in the file's own shape: the reader files a file's loose top-level
    /// bookmarks in a folder called "Bookmarks", and the import keeps it.
    func testTheTopPlacementPutsTheOldBarsFoldersAtTheTop() throws {
        let store = try makeStore()
        let model = BookmarkImportModel(store: store)

        _ = model.apply(try preview(model.read(exportedFile())).plan(.bookmarksBar))

        let top = store.bookmarkFolders(in: nil).map(\.title)
        XCTAssertTrue(top.contains("Work"), "\(top)")
        XCTAssertFalse(store.bookmarks(in: nil).contains { $0.title == "Kept off the bar" }, "what was off the bar landed at the top")
        let dated = try XCTUnwrap(store.bookmarkFolders(in: nil).first { $0.title.hasPrefix("Imported from a file") })
        let loose = try XCTUnwrap(store.bookmarkFolders(in: dated.id).first { $0.title == "Bookmarks" })
        XCTAssertEqual(store.bookmarks(in: loose.id).map(\.title), ["Kept off the bar"])
    }

    /// A file Limeghost exported brings its folders' own icons and colours.
    /// The founder's first import, from Limeghost on the Mac, arrived with
    /// every folder plain.
    func testALimeghostExportBringsItsFoldersIconsAndColours() throws {
        let mac = try makeStore()
        let sticky = try XCTUnwrap(
            LimeghostIconCategory.allCases.lazy.flatMap { LimeghostIconCatalog.icons(in: $0, style: .stickies) }.first?.id
        )
        let travel = try XCTUnwrap(mac.createBookmarkFolder(title: "Travel", iconID: sticky, parentID: nil))
        let work = try XCTUnwrap(mac.createBookmarkFolder(title: "Work", iconID: "briefcase", colorID: "amber", parentID: nil))
        XCTAssertNotNil(mac.addBookmark(title: "Map", url: "https://map.example/", folderID: travel.id))
        XCTAssertNotNil(mac.addBookmark(title: "Mail", url: "https://mail.example/", folderID: work.id))
        let exported = NetscapeBookmarkExporter.html(folders: mac.bookmarkFolders, bookmarks: mac.bookmarks)

        let phone = try makeStore()
        let model = BookmarkImportModel(store: phone)
        _ = model.apply(try preview(model.read(Data(exported.utf8), fileName: "Bookmarks.html")).plan(.bookmarksBar))

        let top = phone.bookmarkFolders(in: nil)
        XCTAssertEqual(top.first { $0.title == "Travel" }?.iconID, sticky)
        XCTAssertEqual(top.first { $0.title == "Work" }?.iconID, "briefcase")
        XCTAssertEqual(top.first { $0.title == "Work" }?.colorID, "amber")
    }

    // MARK: - Files that are not a bookmarks file

    /// Safari on this iPhone exports a ZIP, bookmarks and passwords together.
    /// Chosen as it is, it is named and explained, and nothing in it is read.
    func testSafarisZipSaysToUnpackItFirst() throws {
        let model = BookmarkImportModel(store: try makeStore())
        var zip = Data([0x50, 0x4B, 0x03, 0x04])
        zip.append(Data(exportedHTML.utf8))

        let message = try XCTUnwrap(problem(model.read(zip, fileName: "Safari Export")))

        XCTAssertTrue(message.contains("ZIP archive"), message)
    }

    /// Anything else says what to look for in the other browser.
    func testAnyOtherFileSaysWhatToLookFor() throws {
        let model = BookmarkImportModel(store: try makeStore())

        let message = try XCTUnwrap(problem(model.read(Data("a shopping list".utf8), fileName: "notes")))

        XCTAssertTrue(message.contains("Export Bookmarks"), message)
    }

    // MARK: - Words

    /// A phone has no bookmarks bar, so the words speak of the top of
    /// Bookmarks, and the guide names the real way out of Safari on an
    /// iPhone and off a computer.
    func testTheWordsSayWhatIsTrueOnAPhone() throws {
        XCTAssertEqual(BookmarkImportWording.placementTitle(.bookmarksBar), "At the top of Bookmarks")
        XCTAssertEqual(BookmarkImportWording.placementTitle(.singleFolder), "In one new folder")

        let model = BookmarkImportModel(store: try makeStore())
        let plan = try preview(model.read(exportedFile())).plan(.bookmarksBar)
        let explanation = BookmarkImportWording.placementExplanation(plan)
        XCTAssertTrue(explanation.contains("top of Bookmarks"), explanation)
        XCTAssertFalse(explanation.contains("your bookmarks bar"), explanation)
        XCTAssertTrue(explanation.contains("Nothing already saved is moved, renamed, or replaced."), explanation)

        XCTAssertTrue(BookmarkImportWording.fromSafari.contains("Apps › Safari"), BookmarkImportWording.fromSafari)
        XCTAssertTrue(BookmarkImportWording.fromSafari.contains("ZIP"), BookmarkImportWording.fromSafari)
        XCTAssertTrue(BookmarkImportWording.fromComputer.contains("AirDrop"), BookmarkImportWording.fromComputer)
    }
}
