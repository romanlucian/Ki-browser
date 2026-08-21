import Foundation
import XCTest
@testable import ClearframeCore

/// The parsing half of bookmark import/export: two readers (Chromium JSON,
/// Netscape HTML) and one writer (Netscape HTML), all pure logic with no
/// file picking or merge behind them. These files were not written by
/// Clearframe, so most of what is tested here is what happens when they are
/// wrong — truncated, garbage, non-web schemes, absent titles — alongside
/// the two timestamp conventions that are the easiest thing to get backwards.
final class BookmarkImportExportTests: XCTestCase {
    private func firstBookmark(_ folder: ImportedFolder) -> ImportedBookmark? {
        guard case .bookmark(let bookmark)? = folder.children.first else { return nil }
        return bookmark
    }

    /// Builds a minimal but complete three-root Chromium `Bookmarks` file
    /// around one bookmark, so timestamp/title/scheme tests only have to
    /// vary the one field they are actually about.
    private func minimalChromiumBookmarksData(
        dateAdded: String,
        url: String = "https://example.com/",
        name: String = "Example"
    ) -> Data {
        let bookmark: [String: Any] = [
            "date_added": dateAdded, "id": "2",
            "guid": "00000000-0000-4000-a000-000000000002",
            "name": name, "type": "url", "url": url
        ]
        let bar: [String: Any] = [
            "date_added": "0", "id": "1", "guid": "00000000-0000-4000-a000-000000000001",
            "name": "Bookmarks bar", "type": "folder", "children": [bookmark]
        ]
        let other: [String: Any] = [
            "date_added": "0", "id": "3", "guid": "00000000-0000-4000-a000-000000000003",
            "name": "Other bookmarks", "type": "folder", "children": []
        ]
        let synced: [String: Any] = [
            "date_added": "0", "id": "4", "guid": "00000000-0000-4000-a000-000000000004",
            "name": "Mobile bookmarks", "type": "folder", "children": []
        ]
        let root: [String: Any] = [
            "checksum": "ignored", "version": 1,
            "roots": ["bookmark_bar": bar, "other": other, "synced": synced]
        ]
        return try! JSONSerialization.data(withJSONObject: root)
    }

    // MARK: - Chromium JSON — standard shape

    /// One file exercising the schema end to end: root names mapped to
    /// Chrome's own display names regardless of what the JSON itself calls
    /// them, a nested folder, an empty title falling back to the host, a
    /// `javascript:` link disappearing rather than failing the import,
    /// fields Clearframe ignores (`id`, `guid`, `meta_info`, `sync_metadata`),
    /// and a checksum that is simply never looked at.
    func testChromiumParsesStandardFileAndMapsRootNames() throws {
        let json = """
        {
          "checksum": "0000000000000000000000000000000",
          "roots": {
            "bookmark_bar": {
              "date_added": "0", "id": "1",
              "guid": "00000000-0000-4000-a000-000000000001",
              "name": "toolbar",
              "type": "folder",
              "children": [
                {
                  "date_added": "11644560000000000", "id": "2",
                  "guid": "00000000-0000-4000-a000-000000000002",
                  "name": "News", "type": "url", "url": "https://news.example.com/"
                },
                {
                  "date_added": "0", "id": "3",
                  "guid": "00000000-0000-4000-a000-000000000003",
                  "meta_info": { "power_bookmark_meta": "ignored" },
                  "name": "Work", "type": "folder",
                  "children": [
                    {
                      "date_added": "0", "id": "4",
                      "guid": "00000000-0000-4000-a000-000000000004",
                      "name": "", "type": "url", "url": "https://plans.example.org/roadmap"
                    },
                    {
                      "date_added": "0", "id": "5",
                      "guid": "00000000-0000-4000-a000-000000000005",
                      "name": "Bad link", "type": "url", "url": "javascript:alert(1)"
                    }
                  ]
                }
              ]
            },
            "other": {
              "date_added": "0", "id": "6",
              "guid": "00000000-0000-4000-a000-000000000006",
              "name": "other_node", "type": "folder", "children": []
            },
            "synced": {
              "date_added": "0", "id": "7",
              "guid": "00000000-0000-4000-a000-000000000007",
              "name": "synced_node", "type": "folder", "children": []
            }
          },
          "sync_metadata": "ZZZZ==",
          "version": 1
        }
        """
        let result = try ChromiumBookmarkImporter.parse(Data(json.utf8))

        XCTAssertEqual(result.roots.map(\.title), ["Bookmarks bar", "Other bookmarks", "Mobile bookmarks"])

        let bar = result.roots[0]
        XCTAssertEqual(bar.children.count, 2, "the javascript: link should be gone, not merely empty")

        guard case .bookmark(let news) = bar.children[0] else { return XCTFail("expected a bookmark") }
        XCTAssertEqual(news, ImportedBookmark(
            title: "News", url: "https://news.example.com/", addedAt: Date(timeIntervalSince1970: 86_400)
        ))

        guard case .folder(let work) = bar.children[1] else { return XCTFail("expected a folder") }
        XCTAssertEqual(work.title, "Work")
        XCTAssertEqual(work.children.count, 1)

        guard case .bookmark(let roadmap) = work.children[0] else { return XCTFail("expected a bookmark") }
        XCTAssertEqual(roadmap.title, "plans.example.org")
        XCTAssertNil(roadmap.addedAt)

        XCTAssertEqual(result.bookmarkCount, 2)
        XCTAssertEqual(result.folderCount, 1, "Work only — the three roots are not counted as folders")
    }

    func testChromiumIncludesUnknownRootKeysAfterTheKnownThree() throws {
        let json = """
        {"roots":{
            "bookmark_bar":{"type":"folder","name":"Bookmarks bar","children":[]},
            "other":{"type":"folder","name":"Other bookmarks","children":[]},
            "synced":{"type":"folder","name":"Mobile bookmarks","children":[]},
            "mobile_ios":{"type":"folder","name":"iOS on-device","children":[]}
        }}
        """
        let result = try ChromiumBookmarkImporter.parse(Data(json.utf8))
        XCTAssertEqual(result.roots.map(\.title), ["Bookmarks bar", "Other bookmarks", "Mobile bookmarks", "iOS on-device"])
    }

    // MARK: - Chromium JSON — timestamps

    func testChromiumZeroTimestampBecomesNil() throws {
        let result = try ChromiumBookmarkImporter.parse(minimalChromiumBookmarksData(dateAdded: "0"))
        XCTAssertNil(firstBookmark(result.roots[0])?.addedAt)
    }

    func testChromiumKnownTimestampVectorConvertsCorrectly() throws {
        // 11_644_473_600_000_000 (the 1601->1970 epoch offset) + 86_400_000_000
        // (one day, in microseconds) = 11_644_560_000_000_000, which is
        // exactly 1970-01-02 00:00:00 UTC.
        let result = try ChromiumBookmarkImporter.parse(
            minimalChromiumBookmarksData(dateAdded: "11644560000000000")
        )
        XCTAssertEqual(firstBookmark(result.roots[0])?.addedAt, Date(timeIntervalSince1970: 86_400))
    }

    // MARK: - Chromium JSON — robustness

    func testChromiumEmptyTitleFallsBackToURLHost() throws {
        let data = minimalChromiumBookmarksData(dateAdded: "0", url: "https://plans.example.org/roadmap", name: "")
        let result = try ChromiumBookmarkImporter.parse(data)
        XCTAssertEqual(firstBookmark(result.roots[0])?.title, "plans.example.org")
    }

    func testChromiumSkipsNonHTTPSchemesWithoutFailing() throws {
        let json = """
        {"roots":{"bookmark_bar":{"type":"folder","name":"Bookmarks bar","children":[
            {"type":"url","name":"JS","url":"javascript:alert(1)"},
            {"type":"url","name":"File","url":"file:///etc/passwd"},
            {"type":"url","name":"OK","url":"https://example.com/"}
        ]},"other":{"type":"folder","name":"Other bookmarks","children":[]},
           "synced":{"type":"folder","name":"Mobile bookmarks","children":[]}}}
        """
        let result = try ChromiumBookmarkImporter.parse(Data(json.utf8))
        XCTAssertEqual(result.roots[0].children, [
            .bookmark(ImportedBookmark(title: "OK", url: "https://example.com/", addedAt: nil))
        ])
    }

    func testChromiumThrowsOnGarbageJSON() {
        XCTAssertThrowsError(try ChromiumBookmarkImporter.parse(Data("not json at all {{{".utf8))) {
            XCTAssertEqual($0 as? BookmarkImportError, .malformedJSON)
        }
    }

    func testChromiumThrowsOnTruncatedJSON() {
        let full = minimalChromiumBookmarksData(dateAdded: "0")
        let truncated = full.dropLast(40)
        XCTAssertThrowsError(try ChromiumBookmarkImporter.parse(truncated)) {
            XCTAssertEqual($0 as? BookmarkImportError, .malformedJSON)
        }
    }

    func testChromiumThrowsWhenRootsIsMissing() {
        XCTAssertThrowsError(try ChromiumBookmarkImporter.parse(Data(#"{"version": 1}"#.utf8))) {
            XCTAssertEqual($0 as? BookmarkImportError, .missingRoots)
        }
    }

    /// Foundation's own `JSONSerialization` reader turns out to refuse
    /// input this deep on its own — empirically around 256 levels in this
    /// schema — before `ChromiumBookmarkImporter`'s own cap ever runs, so
    /// this surfaces as `.malformedJSON` rather than `.nestingTooDeep` here.
    /// Both are legitimate `BookmarkImportError` cases, and which one fires
    /// is an implementation detail of Foundation this test should not
    /// hard-code; what has to hold on every platform is the one thing this
    /// asserts — a pathologically nested file throws a named error instead
    /// of crashing or hanging.
    func testChromiumDeeplyNestedFoldersThrowRatherThanCrash() {
        var node: [String: Any] = ["type": "folder", "name": "Leaf", "children": []]
        for _ in 0..<(BookmarkImportLimits.maxNestingDepth + 50) {
            node = ["type": "folder", "name": "F", "children": [node]]
        }
        let root: [String: Any] = ["roots": [
            "bookmark_bar": node,
            "other": ["type": "folder", "name": "Other bookmarks", "children": []],
            "synced": ["type": "folder", "name": "Mobile bookmarks", "children": []]
        ]]
        let data = try! JSONSerialization.data(withJSONObject: root)
        XCTAssertThrowsError(try ChromiumBookmarkImporter.parse(data)) { error in
            guard let importError = error as? BookmarkImportError else {
                return XCTFail("expected a BookmarkImportError, got \(error)")
            }
            XCTAssertTrue(
                importError == .malformedJSON || importError == .nestingTooDeep,
                "expected .malformedJSON or .nestingTooDeep, got \(importError)"
            )
        }
    }

    // MARK: - Netscape HTML — standard shape

    /// Verbatim in shape to `docs/browser-feature-research.md` section 3:
    /// no `</DT>`, no `</p>` — the real-world export shape every browser
    /// actually writes.
    func testNetscapeParsesRealWorldShapeWithNoClosingDTTags() throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><H3 ADD_DATE="11644560000" LAST_MODIFIED="11644560000" PERSONAL_TOOLBAR_FOLDER="true">Bookmarks bar</H3>
            <DL><p>
                <DT><A HREF="https://example.com/" ADD_DATE="86400" ICON="data:image/png;base64,AAAA">Example</A>
            </DL><p>
            <DT><H3 ADD_DATE="11644560000">Other bookmarks</H3>
            <DL><p>
                <DT><A HREF="https://example.org/" ADD_DATE="86401">Example Org</A>
            </DL><p>
        </DL><p>
        """
        let result = try NetscapeBookmarkImporter.parse(html)

        XCTAssertEqual(result.roots.map(\.title), ["Bookmarks bar", "Other bookmarks"])
        XCTAssertEqual(result.roots[0].children, [
            .bookmark(ImportedBookmark(title: "Example", url: "https://example.com/", addedAt: Date(timeIntervalSince1970: 86_400)))
        ])
        XCTAssertEqual(result.roots[1].children, [
            .bookmark(ImportedBookmark(title: "Example Org", url: "https://example.org/", addedAt: Date(timeIntervalSince1970: 86_401)))
        ])
        XCTAssertEqual(result.bookmarkCount, 2)
        XCTAssertEqual(result.folderCount, 0, "both folders here are roots, so neither counts")
    }

    // MARK: - Netscape HTML — timestamps

    func testNetscapeZeroTimestampBecomesNil() throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <DL><p>
        <DT><A HREF="https://example.com/" ADD_DATE="0">No date</A>
        </DL><p>
        """
        let result = try NetscapeBookmarkImporter.parse(html)
        XCTAssertNil(firstBookmark(result.roots[0])?.addedAt)
    }

    func testNetscapeKnownTimestampVectorConvertsCorrectly() throws {
        // Unlike Chromium's, ADD_DATE is already Unix seconds — a different
        // base and unit that must not be run through the same conversion.
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <DL><p>
        <DT><A HREF="https://example.com/" ADD_DATE="86400">Example</A>
        </DL><p>
        """
        let result = try NetscapeBookmarkImporter.parse(html)
        XCTAssertEqual(firstBookmark(result.roots[0])?.addedAt, Date(timeIntervalSince1970: 86_400))
    }

    // MARK: - Netscape HTML — robustness

    func testNetscapeUnescapesHTMLEntitiesInTitles() throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <DL><p>
            <DT><H3>Salt &amp; Pepper</H3>
            <DL><p>
                <DT><A HREF="https://example.com/">Fish &amp; Chips &lt;Best&gt; &quot;Ever&quot; &#39;Yum&#39;</A>
            </DL><p>
        </DL><p>
        """
        let result = try NetscapeBookmarkImporter.parse(html)
        XCTAssertEqual(result.roots.first?.title, "Salt & Pepper")
        XCTAssertEqual(firstBookmark(result.roots[0])?.title, "Fish & Chips <Best> \"Ever\" 'Yum'")
    }

    func testNetscapeEmptyTitleFallsBackToURLHost() throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <DL><p>
        <DT><A HREF="https://plans.example.org/roadmap"></A>
        </DL><p>
        """
        let result = try NetscapeBookmarkImporter.parse(html)
        XCTAssertEqual(result.roots, [ImportedFolder(title: "Bookmarks", children: [
            .bookmark(ImportedBookmark(title: "plans.example.org", url: "https://plans.example.org/roadmap", addedAt: nil))
        ])])
    }

    func testNetscapeEmptyFolderTitleFallsBackToUntitled() throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <DL><p>
            <DT><H3></H3>
            <DL><p>
                <DT><A HREF="https://example.com/">Example</A>
            </DL><p>
        </DL><p>
        """
        let result = try NetscapeBookmarkImporter.parse(html)
        XCTAssertEqual(result.roots.first?.title, "Untitled folder")
    }

    func testNetscapeSkipsNonHTTPSchemesWithoutFailing() throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <DL><p>
            <DT><H3>Links</H3>
            <DL><p>
                <DT><A HREF="javascript:alert(1)">JS</A>
                <DT><A HREF="file:///etc/passwd">File</A>
                <DT><A HREF="https://example.com/">OK</A>
            </DL><p>
        </DL><p>
        """
        let result = try NetscapeBookmarkImporter.parse(html)
        XCTAssertEqual(result.roots, [ImportedFolder(title: "Links", children: [
            .bookmark(ImportedBookmark(title: "OK", url: "https://example.com/", addedAt: nil))
        ])])
    }

    func testNetscapeSkipsBookmarkWithMissingHref() throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <DL><p>
            <DT><H3>Folder</H3>
            <DL><p>
                <DT><A>No href here</A>
                <DT><A HREF="https://example.com/">OK</A>
            </DL><p>
        </DL><p>
        """
        let result = try NetscapeBookmarkImporter.parse(html)
        XCTAssertEqual(result.roots, [ImportedFolder(title: "Folder", children: [
            .bookmark(ImportedBookmark(title: "OK", url: "https://example.com/", addedAt: nil))
        ])])
    }

    func testNetscapeStrayTopLevelBookmarksShareOneSyntheticFolder() throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <DL><p>
            <DT><A HREF="https://example.com/">First</A>
            <DT><A HREF="https://example.org/">Second</A>
        </DL><p>
        """
        let result = try NetscapeBookmarkImporter.parse(html)
        XCTAssertEqual(result.roots, [ImportedFolder(title: "Bookmarks", children: [
            .bookmark(ImportedBookmark(title: "First", url: "https://example.com/", addedAt: nil)),
            .bookmark(ImportedBookmark(title: "Second", url: "https://example.org/", addedAt: nil))
        ])])
    }

    func testNetscapeThrowsOnTruncatedHTML() {
        // Cut off inside the ADD_DATE attribute's quoted value: no closing
        // quote, no '>' — the tag never finishes.
        let truncated = "<!DOCTYPE NETSCAPE-Bookmark-file-1><DL><p><DT><A HREF=\"https://example.com/\" ADD_DATE=\"17000"
        XCTAssertThrowsError(try NetscapeBookmarkImporter.parse(truncated)) {
            XCTAssertEqual($0 as? BookmarkImportError, .truncatedHTML)
        }
    }

    func testNetscapeThrowsOnGarbageHTML() {
        XCTAssertThrowsError(
            try NetscapeBookmarkImporter.parse("<html><body>Not a bookmarks file at all.</body></html>")
        ) {
            XCTAssertEqual($0 as? BookmarkImportError, .notNetscapeDocument)
        }
    }

    func testNetscapeDeeplyNestedFoldersThrowRatherThanCrash() {
        var html = "<!DOCTYPE NETSCAPE-Bookmark-file-1>\n<DL><p>\n"
        for index in 0..<(BookmarkImportLimits.maxNestingDepth + 50) {
            html += "<DT><H3>F\(index)</H3>\n<DL><p>\n"
        }
        XCTAssertThrowsError(try NetscapeBookmarkImporter.parse(html)) {
            XCTAssertEqual($0 as? BookmarkImportError, .nestingTooDeep)
        }
    }

    // MARK: - BookmarkImport counts

    func testBookmarkCountAndFolderCountAreRecursiveAndExcludeRoots() {
        let tree = BookmarkImport(roots: [
            ImportedFolder(title: "Bookmarks bar", children: [
                .bookmark(ImportedBookmark(title: "A", url: "https://a.example/", addedAt: nil)),
                .folder(ImportedFolder(title: "Sub", children: [
                    .bookmark(ImportedBookmark(title: "B", url: "https://b.example/", addedAt: nil)),
                    .folder(ImportedFolder(title: "SubSub", children: [
                        .bookmark(ImportedBookmark(title: "C", url: "https://c.example/", addedAt: nil))
                    ]))
                ]))
            ]),
            ImportedFolder(title: "Other bookmarks", children: [])
        ])

        XCTAssertEqual(tree.bookmarkCount, 3)
        XCTAssertEqual(tree.folderCount, 2, "\"Sub\" and \"SubSub\" only; neither root counts")
    }

    // MARK: - Export

    func testExporterEmitsExpectedLiteralShape() {
        let folder = BookmarkFolderRecord(title: "Tools", parentID: nil, createdAt: Date(timeIntervalSince1970: 1_700_000_000), position: 0)
        let bookmark = BookmarkRecord(
            title: "A & B", url: "https://example.com/?x=1&y=2",
            createdAt: Date(timeIntervalSince1970: 1_700_000_050), folderID: nil, position: 0
        )

        let html = NetscapeBookmarkExporter.html(folders: [folder], bookmarks: [bookmark])

        XCTAssertTrue(html.hasPrefix("<!DOCTYPE NETSCAPE-Bookmark-file-1>\n"))
        XCTAssertEqual(
            html.components(separatedBy: "PERSONAL_TOOLBAR_FOLDER=\"true\"").count, 2,
            "exactly one folder — the bar — should carry PERSONAL_TOOLBAR_FOLDER"
        )
        XCTAssertTrue(html.contains("<DT><H3 ADD_DATE=\"1700000000\" LAST_MODIFIED=\"1700000000\">Tools</H3>"))
        XCTAssertTrue(html.contains("HREF=\"https://example.com/?x=1&amp;y=2\""))
        XCTAssertTrue(html.contains(">A &amp; B<"))
    }

    /// The round trip that matters most: what Clearframe writes, Clearframe
    /// (or any other browser) must read back with the same tree, the same
    /// titles — entities included — and the same order folders and
    /// bookmarks already render in on the bar (folders first, then
    /// bookmarks, each in position order).
    func testExportImportRoundTripPreservesTreeTitlesAndOrder() throws {
        let work = BookmarkFolderRecord(title: "Work", parentID: nil, createdAt: Date(timeIntervalSince1970: 1_700_000_000), position: 0)
        let personal = BookmarkFolderRecord(title: "Personal", parentID: nil, createdAt: Date(timeIntervalSince1970: 1_700_000_010), position: 1)
        let reading = BookmarkFolderRecord(title: "Reading", parentID: work.id, createdAt: Date(timeIntervalSince1970: 1_700_000_020), position: 0)

        let example = BookmarkRecord(title: "Example", url: "https://example.com/", createdAt: Date(timeIntervalSince1970: 1_700_000_100), folderID: nil, position: 0)
        let docs = BookmarkRecord(title: "Docs", url: "https://docs.example.com/", createdAt: Date(timeIntervalSince1970: 1_700_000_110), folderID: work.id, position: 0)
        let article = BookmarkRecord(title: "Article & Notes", url: "https://example.org/article", createdAt: Date(timeIntervalSince1970: 1_700_000_120), folderID: reading.id, position: 0)

        let html = NetscapeBookmarkExporter.html(folders: [work, personal, reading], bookmarks: [example, docs, article])
        let result = try NetscapeBookmarkImporter.parse(html)

        let expected = BookmarkImport(roots: [
            ImportedFolder(title: "Bookmarks bar", children: [
                .folder(ImportedFolder(title: "Work", children: [
                    .folder(ImportedFolder(title: "Reading", children: [
                        .bookmark(ImportedBookmark(title: "Article & Notes", url: "https://example.org/article", addedAt: Date(timeIntervalSince1970: 1_700_000_120)))
                    ])),
                    .bookmark(ImportedBookmark(title: "Docs", url: "https://docs.example.com/", addedAt: Date(timeIntervalSince1970: 1_700_000_110)))
                ])),
                .folder(ImportedFolder(title: "Personal", children: [])),
                .bookmark(ImportedBookmark(title: "Example", url: "https://example.com/", addedAt: Date(timeIntervalSince1970: 1_700_000_100)))
            ])
        ])

        XCTAssertEqual(result, expected)
        XCTAssertEqual(result.bookmarkCount, 3)
        XCTAssertEqual(result.folderCount, 3, "Work, Personal, Reading — the synthetic bar root is not counted")
    }
}
