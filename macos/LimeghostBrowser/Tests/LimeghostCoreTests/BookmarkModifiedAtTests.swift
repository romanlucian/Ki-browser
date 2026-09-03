import XCTest
@testable import LimeghostCore

final class BookmarkModifiedAtTests: XCTestCase {
    /// Exactly the JSON the app was writing before `modifiedAt` existed. A
    /// record saved yesterday must still decode today, or somebody opens the
    /// browser to an empty bookmarks bar. This is the profile-face precedent:
    /// new fields are optional, and a test decodes the real old bytes.
    func testARecordWrittenBeforeThisFieldExistedStillDecodes() throws {
        let json = """
        {"id":"3F2504E0-4F89-41D3-9A0C-0305E82C3301",
         "title":"Limeghost",
         "url":"https://example.com/",
         "createdAt":768000000,
         "position":0}
        """.data(using: .utf8)!

        let record = try JSONDecoder().decode(BookmarkRecord.self, from: json)

        XCTAssertEqual(record.title, "Limeghost")
        XCTAssertNil(record.modifiedAt, "an absent timestamp must decode as absent, not as now")
    }

    /// The same for folders, which carry the icon and colour a person chose.
    func testAFolderWrittenBeforeThisFieldExistedStillDecodes() throws {
        let json = """
        {"id":"3F2504E0-4F89-41D3-9A0C-0305E82C3302",
         "title":"Reading",
         "emoji":"📁",
         "createdAt":768000000}
        """.data(using: .utf8)!

        let folder = try JSONDecoder().decode(BookmarkFolderRecord.self, from: json)

        XCTAssertEqual(folder.title, "Reading")
        XCTAssertNil(folder.modifiedAt)
    }

    /// And it survives a round trip once set, because sync compares it.
    func testTheTimestampSurvivesARoundTrip() throws {
        let when = Date(timeIntervalSince1970: 800_000_000)
        let record = BookmarkRecord(
            id: UUID(),
            title: "Limeghost",
            url: "https://example.com/",
            createdAt: Date(timeIntervalSince1970: 768_000_000),
            folderID: nil,
            position: 0,
            modifiedAt: when
        )

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(BookmarkRecord.self, from: data)

        XCTAssertEqual(decoded.modifiedAt, when)
    }

    /// Resaving a folder with the exact title, icon and colour it already has
    /// is not an edit. The folder editor's Save button is gated only on a
    /// non-empty title, never on whether anything actually changed, so this
    /// is reached in ordinary use, not just in theory. `BrowserDataStore`
    /// decides whether to write to disk and republish by comparing the whole
    /// folder, so stamping `modifiedAt` on a no-op Save would turn a person
    /// opening an editor and changing nothing into an always-on disk write.
    func testResavingAFolderWithNoActualChangeLeavesItUntouched() throws {
        var collection = BookmarkCollection()
        let created = collection.createFolder(title: "Reading", iconID: "book", colorID: "mint", parentID: nil)
        let folder = try XCTUnwrap(created)

        collection.updateFolder(id: folder.id, title: folder.title, iconID: folder.iconID ?? "", colorID: folder.colorID)

        XCTAssertEqual(collection.folders, [folder], "resaving the same values must not look like an edit")
    }
}
