import Combine
import LimeghostCore
@testable import LimeghostShared
import Foundation
import WebKit
import XCTest

/// A download collaborator that cannot save anything, as on the phone.
@MainActor
final class RefusingDownloads: DownloadTracking {
    private(set) var tracked = 0
    var acceptsDownloads: Bool { false }
    func track(_ download: WKDownload, sourceURL: URL?) { tracked += 1 }
    let objectWillChange = ObservableObjectPublisher()
    func clearAllRecords() {}
}

@MainActor
final class TypedAddressAndFileTests: XCTestCase {
    private func makeSession(downloads: DownloadTracking? = nil) throws -> BrowserSession {
        let suiteName = "clearframe.typedAddress.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let session = BrowserSession(
            platform: RecordingPlatform(),
            downloadCenter: downloads ?? NoDownloads(),
            searchSettings: SearchSettingsStore(defaults: defaults)
        )
        addTeardownBlock { @MainActor in session.teardown() }
        return session
    }

    // MARK: - Machines on this network

    /// A router's page, a printer's, a development server: typed without a
    /// scheme, they were all asked for over https, which they almost never
    /// serve, and failed. Every browser opens these over http — Chrome keeps
    /// IP addresses and local names out of its HTTPS upgrades for this reason.
    func testALocalMachineTypedWithoutASchemeIsOpenedOverHTTP() throws {
        let cases = [
            ("192.168.1.1", "http://192.168.1.1"),
            ("10.0.0.2:8080/admin", "http://10.0.0.2:8080/admin"),
            ("localhost:3000", "http://localhost:3000"),
            ("printer.local/status", "http://printer.local/status")
        ]
        for (typed, expected) in cases {
            let session = try makeSession()
            session.navigate(typed)
            XCTAssertEqual(session.currentURLString, expected, "typed \(typed)")
        }
    }

    /// A public name typed without a scheme still asks for https.
    func testAWebsiteTypedWithoutASchemeIsStillOpenedOverHTTPS() throws {
        let session = try makeSession()
        session.navigate("example.com/owls")
        XCTAssertEqual(session.currentURLString, "https://example.com/owls")
    }

    // MARK: - A file this device cannot save

    /// On the phone, tapping a link to a file did nothing at all: WebKit
    /// handed the download over to a collaborator that drops it, and no page,
    /// error or word followed. The page now says so.
    func testAFileThisDeviceCannotSaveIsSaidRatherThanDropped() async throws {
        let downloads = RefusingDownloads()
        let session = try makeSession(downloads: downloads)
        _ = await eventually(timeout: 90) { session.hasCommittedNavigation && !session.webView.isLoading }
        session.webView.loadHTMLString(
            #"<!doctype html><a id="file" download="notes.txt" href="data:text/plain,hello">Notes</a>"#,
            baseURL: URL(string: "https://files.example/")!
        )
        let loaded = await eventually(timeout: 60) { session.loadState == .content && !session.isLoading }
        XCTAssertTrue(loaded, "the page with the file never loaded")

        _ = try await evaluate("document.getElementById('file').click()", in: session)
        let said = await eventually(timeout: 20) { session.pageNotice != nil }

        XCTAssertTrue(said, "tapping a file did nothing at all")
        XCTAssertEqual(downloads.tracked, 0, "a download was handed to a collaborator that cannot save it")
    }

    // MARK: - A page that will not stop asking

    /// A page can loop `alert()`, and every dialog must be answered before
    /// anything else in the app can be used — so such a page locked
    /// somebody out of the whole browser, and a relaunch restored it.
    /// From a site's second dialog on, the person is offered a way to stop
    /// them, and once taken, that site's dialogs are answered unseen.
    func testASiteThatKeepsAskingCanBeSilenced() {
        var guardian = PageDialogGuard()

        XCTAssertFalse(guardian.isSilenced(host: "loop.example"))
        XCTAssertFalse(guardian.willShow(host: "loop.example"), "the first dialog is shown plainly")
        XCTAssertTrue(guardian.willShow(host: "loop.example"), "the second offers a way to stop them")

        guardian.silence(host: "loop.example")

        XCTAssertTrue(guardian.isSilenced(host: "loop.example"))
        XCTAssertFalse(guardian.isSilenced(host: "other.example"), "another site is not silenced with it")
    }

    /// The count is per site: a tab that moves on starts counting again.
    func testAnotherSiteStartsWithAPlainDialog() {
        var guardian = PageDialogGuard()
        _ = guardian.willShow(host: "first.example")
        _ = guardian.willShow(host: "first.example")

        XCTAssertFalse(guardian.willShow(host: "second.example"))
    }
}
