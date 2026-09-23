import LimeghostCore
@testable import LimeghostShared
import Foundation
import WebKit
import XCTest

/// What a tab does with the page WebKit gives it: a load that fails, the
/// document behind a new tab, a very long page, and a page with no title.
/// Real WebKit throughout; `loadHTMLString` with a web `baseURL` stands in for
/// a server where one is not needed.
@MainActor
final class SessionPageTests: XCTestCase {
    private func settledTab(isPrivate: Bool = false) async throws -> (IsolatedWorkspace, BrowserTab) {
        let isolated = try IsolatedWorkspace.make(for: self, isPrivate: isPrivate)
        let tab = try XCTUnwrap(isolated.workspace.selectedTab)
        // Finished, not merely idle: WebKit reports `isLoading == false` for a
        // moment before it has even started a document it was just handed.
        // Generous, because the first web page in a fresh Simulator process
        // took over twenty seconds to arrive on September 22, 2026, while
        // every later one took about one; a met condition returns at once.
        let settled = await eventually(timeout: 90) { tab.session.hasCommittedNavigation && !tab.session.webView.isLoading }
        XCTAssertTrue(settled, "the new tab's own document never finished loading")
        return (isolated, tab)
    }

    private func load(_ html: String, at address: String, in session: BrowserSession) async throws {
        session.webView.loadHTMLString(html, baseURL: URL(string: address)!)
        let loaded = await eventually(timeout: 60) { session.loadState == .content && !session.isLoading }
        XCTAssertTrue(loaded, "\(address) did not finish loading; loadState=\(session.loadState)")
    }

    // MARK: - Retrying

    /// After a failed load WebKit still holds the page before it, so
    /// `webView.reload()` reloaded *that* — never the address that failed. On
    /// the phone the menu's Reload is the only way to try again.
    func testReloadAfterAFailedLoadAsksForTheFailedPageAgain() async throws {
        let (_, tab) = try await settledTab()
        let session = tab.session
        let unreachable = URL(string: "https://127.0.0.1:65530/unreachable")!
        session.load(unreachable)
        let failed = await eventually {
            if case .failed = session.loadState { return true }
            return false
        }
        XCTAssertTrue(failed, "the unreachable address did not fail; loadState=\(session.loadState)")

        session.reload()

        XCTAssertEqual(session.loadState, .loading, "Reload did not ask for the page that failed")
        XCTAssertEqual(session.currentURLString, unreachable.absoluteString)
    }

    // MARK: - The document behind a new tab

    /// Every tab first loads a document of its own, and the native guide covers
    /// it. It is uncovered while a new tab loads its first page — behind the
    /// Mac's progress card, and on the phone with nothing over it at all — and
    /// it still drew the Clearframe "C", a ⇧⌘C shortcut, and "the bar above".
    func testTheDocumentBehindANewTabShowsNothingOfItsOwn() async throws {
        let (_, tab) = try await settledTab()

        let text = try await evaluate("document.body ? document.body.innerText.trim() : ''", in: tab.session) as? String

        XCTAssertEqual(text, "", "the start document draws text of its own")
    }

    // MARK: - A very long page

    /// The extractor keeps the first 48,000 UTF-16 code units. Cut inside an
    /// emoji, that left half a surrogate pair, which `JSONSerialization`
    /// rejects outright — so on such a page Copy for AI and Reader failed every
    /// time with "could not read enough text".
    func testALongPageCutInsideAnEmojiIsStillRead() async throws {
        let (_, tab) = try await settledTab()
        let body = String(repeating: "a", count: 47_999) + "😀" + String(repeating: "b", count: 100)
        try await load(
            "<!doctype html><html><head><meta charset=\"utf-8\"><title>Long</title></head><body>\(body)</body></html>",
            at: "https://long.example/page",
            in: tab.session
        )

        let page = try await tab.session.extractPage()

        XCTAssertEqual(page.text, String(repeating: "a", count: 47_999), "the cut kept half an emoji or lost the page")
    }

    // MARK: - A page with no title

    /// A page that names itself nothing — plain text, an image, a bare HTML
    /// document — kept the placeholder "Loading…" as its title for good: on
    /// its tab, in history, and in every completion row built from history.
    func testAPageWithNoTitleIsNamedByItsAddress() async throws {
        let (isolated, tab) = try await settledTab()

        try await load("<!doctype html><p>Nothing here names this page.</p>", at: "https://untitled.example/notes", in: tab.session)

        XCTAssertEqual(tab.session.pageTitle, "untitled.example/notes")
        XCTAssertEqual(isolated.workspace.dataStore.history.first?.title, "untitled.example/notes")
    }

    /// A page that sets its title from a script after it finished loading was
    /// recorded under the placeholder, and the 30-second duplicate guard then
    /// turned away the visit that carried the real one.
    func testATitleThatArrivesAfterThePageFinishedIsWhatHistoryKeeps() async throws {
        let (isolated, tab) = try await settledTab()
        let html = """
        <!doctype html><p>Named late.</p>
        <script>setTimeout(() => { document.title = "Arrived Late"; }, 300);</script>
        """

        try await load(html, at: "https://late.example/page", in: tab.session)
        let corrected = await eventually(timeout: 5) {
            isolated.workspace.dataStore.history.first?.title == "Arrived Late"
        }

        XCTAssertTrue(corrected, "history kept \(isolated.workspace.dataStore.history.first?.title ?? "nothing")")
        XCTAssertEqual(isolated.workspace.dataStore.history.count, 1, "the corrected title became a second visit")
        XCTAssertEqual(tab.session.pageTitle, "Arrived Late")
    }

    /// A private tab records nothing, late title or not.
    func testAPrivateTabsLateTitleRecordsNothing() async throws {
        let (isolated, tab) = try await settledTab(isPrivate: true)
        let html = """
        <!doctype html><p>Private.</p>
        <script>setTimeout(() => { document.title = "Arrived Late"; }, 100);</script>
        """

        try await load(html, at: "https://private-late.example/page", in: tab.session)
        _ = await eventually(timeout: 2) { tab.session.pageTitle == "Arrived Late" }

        XCTAssertTrue(isolated.workspace.dataStore.history.isEmpty)
    }

    // MARK: - The names themselves

    func testTheNameOfAnUntitledPageIsItsHostAndPath() {
        XCTAssertEqual(BrowserSession.untitledPageName(for: URL(string: "https://www.example.com/")!), "example.com")
        XCTAssertEqual(BrowserSession.untitledPageName(for: URL(string: "https://example.com")!), "example.com")
        XCTAssertEqual(
            BrowserSession.untitledPageName(for: URL(string: "https://example.com/docs/notes.txt")!),
            "example.com/docs/notes.txt"
        )
        XCTAssertEqual(
            BrowserSession.untitledPageName(for: URL(string: "https://example.com/search?q=owls#top")!),
            "example.com/search"
        )
    }
}
