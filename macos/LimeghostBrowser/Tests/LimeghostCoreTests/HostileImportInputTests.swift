import Foundation
import XCTest
@testable import LimeghostCore

/// A bookmarks file is input from outside: a person can pick any file, and a
/// file can say anything. A value the importer cannot represent must cost the
/// one field it sits in, never the process.
final class HostileImportInputTests: XCTestCase {
    private func chromiumFile(dateAdded: String) -> Data {
        Data("""
        {"roots":{"bookmark_bar":{"name":"Bookmarks bar","type":"folder","children":[
          {"type":"url","name":"Kept","url":"https://example.com/kept","date_added":\(dateAdded)}
        ]}}}
        """.utf8)
    }

    private func onlyBookmark(in parsed: BookmarkImport) throws -> ImportedBookmark {
        let bar = try XCTUnwrap(parsed.roots.first)
        guard case .bookmark(let bookmark)? = bar.children.first else {
            throw NSError(
                domain: "HostileImportInputTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "the bookmark did not survive the import"]
            )
        }
        return bookmark
    }

    /// Chrome's epoch is 1601, so the importer subtracts 11,644,473,600
    /// seconds' worth of microseconds from every timestamp. With `Int64`
    /// arithmetic, a value near `Int64.min` underflowed that subtraction, which
    /// Swift traps on: importing this file ended the app.
    func testATimestampBelowTheRangeOfDatesDoesNotCrashTheImport() throws {
        let parsed = try ChromiumBookmarkImporter.parse(chromiumFile(dateAdded: "\"-9223372036854775808\""))

        let bookmark = try onlyBookmark(in: parsed)
        XCTAssertEqual(bookmark.url, "https://example.com/kept")
        XCTAssertNil(bookmark.addedAt, "a date that cannot be represented is dropped, not invented")
    }

    /// The same value written as a JSON number rather than a string, which
    /// reaches the subtraction through `NSNumber.int64Value`.
    func testATimestampNumberBelowTheRangeOfDatesDoesNotCrashTheImport() throws {
        let parsed = try ChromiumBookmarkImporter.parse(chromiumFile(dateAdded: "-9.3e18"))

        let bookmark = try onlyBookmark(in: parsed)
        XCTAssertEqual(bookmark.url, "https://example.com/kept")
        XCTAssertNil(bookmark.addedAt)
    }

    /// An ordinary Chrome timestamp still converts: 13,300,000,000,000,000
    /// microseconds after 1601 is 1,655,526,400 seconds after 1970.
    func testAnOrdinaryTimestampStillConverts() throws {
        let parsed = try ChromiumBookmarkImporter.parse(chromiumFile(dateAdded: "\"13300000000000000\""))

        let bookmark = try onlyBookmark(in: parsed)
        XCTAssertEqual(bookmark.addedAt?.timeIntervalSince1970, 1_655_526_400)
    }

    /// A file is somebody else's text. An icon the catalogue does not hold,
    /// or a colour Limeghost does not have, is dropped, and the folder is
    /// made plain rather than drawn with nothing.
    func testAnUnknownIconOrColourInAFileIsDropped() throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <DL><p>
            <DT><H3 LIMEGHOST_ICON="javascript:alert(1)" LIMEGHOST_COLOR="hotpink">Odd</H3>
            <DL><p>
                <DT><A HREF="https://example.com/">Example</A>
            </DL><p>
        </DL><p>
        """
        let imported = try NetscapeBookmarkImporter.parse(html)

        let odd = try XCTUnwrap(imported.roots.first { $0.title == "Odd" })
        XCTAssertNil(odd.iconID)
        XCTAssertNil(odd.colorID)
    }
}
