import Foundation
import XCTest
@testable import LimeghostBrowser

/// A download's name comes from the server, and so does anything unusual
/// about it. The name only ever becomes a file inside the folder the person
/// chose, and Replace only ever replaces a file.
@MainActor
final class DownloadSafetyTests: XCTestCase {
    /// `..` and `.` are not names a file can have: `lastPathComponent` hands
    /// both back unchanged, and the save panel was then filled in with them.
    func testANameThatIsOnlyDotsBecomesDownload() {
        XCTAssertEqual(DownloadCenter.safeFilename(for: ".."), "Download")
        XCTAssertEqual(DownloadCenter.safeFilename(for: "."), "Download")
        XCTAssertEqual(DownloadCenter.safeFilename(for: "   "), "Download")
        XCTAssertEqual(DownloadCenter.safeFilename(for: ""), "Download")
    }

    /// A path is reduced to its last name, as before.
    func testAPathBecomesItsLastName() {
        XCTAssertEqual(DownloadCenter.safeFilename(for: "../../etc/passwd"), "passwd")
        XCTAssertEqual(DownloadCenter.safeFilename(for: "/tmp/report.pdf"), "report.pdf")
    }

    /// A name that would be hidden in Finder arrives visible: a download
    /// nobody can see looks like a download that never happened.
    func testAHiddenNameArrivesVisible() {
        XCTAssertEqual(DownloadCenter.safeFilename(for: ".bashrc"), "bashrc")
        XCTAssertEqual(DownloadCenter.safeFilename(for: "...notes.txt"), "notes.txt")
    }

    func testAnOrdinaryNameIsKept() {
        XCTAssertEqual(DownloadCenter.safeFilename(for: "Annual report 2026.pdf"), "Annual report 2026.pdf")
    }

    /// The save panel's Replace is consent to replace a *file*. Whatever path
    /// the panel resolves to, a folder there is never removed to make room.
    func testReplaceOnlyEverRemovesAFile() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("limeghost-download-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("existing.pdf")
        try Data("old".utf8).write(to: file)

        XCTAssertFalse(DownloadCenter.isReplaceableFile(folder), "a folder would have been deleted")
        XCTAssertTrue(DownloadCenter.isReplaceableFile(file))
    }

    /// The Downloads panel's empty state said Limeghost "asks where to save
    /// every file" whether or not it did: Settings can send downloads straight
    /// to a folder.
    func testTheEmptyDownloadsPanelSaysWhereFilesGo() {
        XCTAssertTrue(DownloadCenter.emptyStateFootnote(asksWhereToSave: true).contains("asks where to save"))
        XCTAssertFalse(DownloadCenter.emptyStateFootnote(asksWhereToSave: false).contains("asks where to save"))
    }
}
