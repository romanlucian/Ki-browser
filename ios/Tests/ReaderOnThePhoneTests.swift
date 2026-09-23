import XCTest
import SwiftUI
import LimeghostCore
@testable import Limeghost
@testable import LimeghostShared

@MainActor
final class ReaderOnThePhoneTests: XCTestCase {
    /// An article the extractor is confident about, so no warning adds a
    /// third row to the header.
    private func article() throws -> ReaderArticle {
        try XCTUnwrap(ReaderArticle(page: PageSnapshot(
            title: "How owls fly without a sound",
            url: "https://example.com/owls",
            hostname: "example.com",
            scheme: "https",
            language: "en",
            text: "A barn owl can glide a few feet above a mouse without being heard. Its wings are not quieter by accident.",
            wordCount: 21,
            hasPasswordField: false,
            formActions: [],
            extractionConfidence: 0.9
        )))
    }

    /// A suite of its own, emptied afterwards, as `StartSurfaceTests.makeHost()` does.
    private func makeHost() throws -> WorkspaceHost {
        let suiteName = "clearframe.iosReader.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return WorkspaceHost.forTesting(defaults: defaults)
    }

    // MARK: - Over the page

    /// While an article is open, Reader covers the page. The web view stays
    /// mounted underneath it.
    func testReaderCoversThePageWhileAnArticleIsOpen() throws {
        let host = try makeHost()
        let tab = try XCTUnwrap(host.workspace.selectedTab)
        host.workspace.open("https://example.com/")
        XCTAssertFalse(TabSurface(tab: tab, workspace: host.workspace).showsTheReader)

        tab.readerArticle = try article()

        XCTAssertTrue(TabSurface(tab: tab, workspace: host.workspace).showsTheReader)
    }

    /// The guide is not a page, and Reader never covers it.
    func testReaderNeverCoversTheGuide() throws {
        let host = try makeHost()
        let tab = try XCTUnwrap(host.workspace.selectedTab)

        tab.readerArticle = try article()

        XCTAssertFalse(TabSurface(tab: tab, workspace: host.workspace).showsTheReader)
    }

    // MARK: - A page that failed to load

    /// A failed load drew nothing on the phone. The tab kept whatever WebKit
    /// still held — the page before, or the blank document behind a new tab —
    /// under the failed page's address, with no word of what went wrong.
    func testAFailedLoadIsSaidOverThePage() async throws {
        let host = try makeHost()
        let tab = try XCTUnwrap(host.workspace.selectedTab)

        tab.session.load(URL(string: "https://127.0.0.1:65530/unreachable")!)
        let failed = await eventually {
            if case .failed = tab.session.loadState { return true }
            return false
        }
        XCTAssertTrue(failed, "the unreachable address did not fail")

        let failure = TabSurface(tab: tab, workspace: host.workspace).shownFailure
        XCTAssertEqual(failure?.title, "Couldn’t connect to this website")
        XCTAssertEqual(failure?.retryable, true)
    }

    /// Nothing failed on a fresh tab, and the guide is never covered.
    func testNoFailureIsDrawnOverTheGuide() throws {
        let host = try makeHost()
        let tab = try XCTUnwrap(host.workspace.selectedTab)

        XCTAssertNil(TabSurface(tab: tab, workspace: host.workspace).shownFailure)
    }

    private func eventually(timeout: TimeInterval = 5, _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    // MARK: - The header

    /// Reader's header on a phone is two rows of 44 points, the smallest
    /// target Apple's guidelines give a finger, with 6 points above and
    /// below: 100 in all, at every phone width.
    ///
    /// The break this catches is the Mac's row on a phone. It fits at 428
    /// points, so a choice by width would pick it, and its buttons are 11- to
    /// 13-point text with no room around them. It also catches a row that
    /// wraps, which would make the header taller than 100.
    func testTheTouchHeaderIsTwoRowsAFingerCanUse() throws {
        let header = ReaderView.Header(article: try article(), style: .touch, copy: {}, close: {})
        for screenWidth in [375.0, 402.0, 428.0] {
            XCTAssertEqual(
                try renderedHeight(of: header, width: screenWidth),
                100,
                "on a \(Int(screenWidth))-point screen Reader's header is not two 44-point rows"
            )
        }
    }

    /// How tall a view draws at a given width, measured by rendering it.
    private func renderedHeight<Content: View>(of view: Content, width: CGFloat) throws -> CGFloat {
        let renderer = ImageRenderer(content: view.frame(width: width))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage, "the view did not render")
        return CGFloat(image.height)
    }
}
