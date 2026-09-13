import XCTest
import LimeghostCore
@testable import Limeghost
@testable import LimeghostShared

@MainActor
final class PageMenuTests: XCTestCase {
    /// A suite of its own, emptied afterwards, for the reason
    /// `StartSurfaceTests.makeHost()` gives: these tests run inside the app.
    private func makeHost() throws -> WorkspaceHost {
        let suiteName = "clearframe.iosPageMenu.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return WorkspaceHost.forTesting(defaults: defaults)
    }

    /// A model on a page, with nothing else true, unless a test says otherwise.
    private func model(
        hasPage: Bool = true,
        canGoForward: Bool = false,
        isBookmarked: Bool = false,
        prefersDesktopSite: Bool = false,
        isReaderOpen: Bool = false
    ) -> PageMenuModel {
        PageMenuModel(
            hasPage: hasPage,
            canGoForward: canGoForward,
            isBookmarked: isBookmarked,
            prefersDesktopSite: prefersDesktopSite,
            isReaderOpen: isReaderOpen
        )
    }

    // MARK: - What the menu offers

    /// On the AI guide there is no page to act on. The rows that need no page
    /// work: the two that open a new tab, and the two that open a list. The
    /// rest stay in place, greyed, and light up when a page opens.
    func testOnTheGuideOnlyTheRowsThatNeedNoPageWork() {
        let guide = model(hasPage: false)
        XCTAssertEqual(PageMenuItem.allCases.filter(guide.isEnabled), [.newTab, .newPrivateTab, .bookmarks, .history])
    }

    /// On a page every row works except Forward, while there is nowhere to
    /// go forward to.
    func testOnAPageEverythingWorksButForward() {
        let page = model()
        XCTAssertEqual(PageMenuItem.allCases.filter { !page.isEnabled($0) }, [.forward])
    }

    /// Forward follows the tab: back on the guide, the page to go forward to
    /// is still there.
    func testForwardFollowsTheTab() {
        XCTAssertTrue(model(canGoForward: true).isEnabled(.forward))
        XCTAssertTrue(model(hasPage: false, canGoForward: true).isEnabled(.forward))
    }

    /// Find in Page searches the page, and Reader covers it, so a match would
    /// be highlighted where nobody can see it. Reader itself stays available,
    /// to be closed.
    func testFindWaitsWhileReaderCoversThePage() {
        let reading = model(isReaderOpen: true)
        XCTAssertFalse(reading.isEnabled(.find))
        XCTAssertTrue(reading.isEnabled(.reader))
    }

    /// The labels that change say what a tap will do next.
    func testTheLabelsSayWhatATapWillDoNext() {
        XCTAssertEqual(model().title(.bookmark), "Add Bookmark")
        XCTAssertEqual(model(isBookmarked: true).title(.bookmark), "Remove Bookmark")
        XCTAssertEqual(model(isBookmarked: true).symbol(.bookmark), "star.fill")

        XCTAssertEqual(model().title(.desktopSite), "Request Desktop Site")
        XCTAssertEqual(model(prefersDesktopSite: true).title(.desktopSite), "Request Mobile Site")
        XCTAssertEqual(model(prefersDesktopSite: true).symbol(.desktopSite), "iphone")

        XCTAssertEqual(model().title(.reader), "Reader")
        XCTAssertEqual(model(isReaderOpen: true).title(.reader), "Close Reader")
    }

    /// The two list rows say where they go.
    func testTheListRowsSayWhereTheyGo() {
        XCTAssertEqual(model().title(.bookmarks), "Bookmarks")
        XCTAssertEqual(model().symbol(.bookmarks), "book")
        XCTAssertEqual(model().title(.history), "History")
        XCTAssertEqual(model().symbol(.history), "clock")
    }

    /// The model reads the tab in front, not a copy of it.
    func testTheModelReadsTheTabInFront() throws {
        let host = try makeHost()
        XCTAssertFalse(PageMenuModel(workspace: host.workspace).hasPage, "a fresh tab is on the guide, with no page")

        host.workspace.open("https://example.com/")
        host.workspace.toggleBookmarkForSelectedTab()
        let onAPage = PageMenuModel(workspace: host.workspace)

        XCTAssertTrue(onAPage.hasPage)
        XCTAssertTrue(onAPage.isBookmarked)
        XCTAssertFalse(onAPage.prefersDesktopSite)
        XCTAssertFalse(onAPage.isReaderOpen)
    }

    // MARK: - What the rows do

    /// New Private Tab puts a private tab in front, through the workspace's
    /// own door.
    func testNewPrivateTabPutsAPrivateTabInFront() async throws {
        let host = try makeHost()
        await PageMenuActions(workspace: host.workspace).perform(.newPrivateTab)
        XCTAssertEqual(host.workspace.selectedTab?.isPrivate, true)
    }

    /// Add Bookmark saves the page and says so. The phone has no star to show it.
    func testAddBookmarkSavesThePageAndSaysSo() async throws {
        let host = try makeHost()
        host.workspace.open("https://example.com/")

        await PageMenuActions(workspace: host.workspace).perform(.bookmark)

        XCTAssertTrue(host.workspace.dataStore.isBookmarked("https://example.com/"))
        XCTAssertEqual(host.workspace.selectedTab?.session.pageNotice, "Bookmark added.")
    }

    /// The same row on a saved page removes it, and says that instead.
    func testRemoveBookmarkRemovesItAndSaysSo() async throws {
        let host = try makeHost()
        host.workspace.open("https://example.com/")
        let actions = PageMenuActions(workspace: host.workspace)

        await actions.perform(.bookmark)
        await actions.perform(.bookmark)

        XCTAssertFalse(host.workspace.dataStore.isBookmarked("https://example.com/"))
        XCTAssertEqual(host.workspace.selectedTab?.session.pageNotice, "Bookmark removed.")
    }

    /// Request Desktop Site turns the switch on in the tab in front, and the
    /// same row turns it off again.
    func testRequestDesktopSiteTurnsTheTabsSwitchOnAndOff() async throws {
        let host = try makeHost()
        host.workspace.open("https://example.com/")
        let actions = PageMenuActions(workspace: host.workspace)

        await actions.perform(.desktopSite)
        XCTAssertEqual(host.workspace.selectedTab?.session.prefersDesktopSite, true)

        await actions.perform(.desktopSite)
        XCTAssertEqual(host.workspace.selectedTab?.session.prefersDesktopSite, false)
    }

    /// Find in Page opens the find bar.
    func testFindInPageOpensTheFindBar() async throws {
        let host = try makeHost()
        host.workspace.open("https://example.com/")

        await PageMenuActions(workspace: host.workspace).perform(.find)

        XCTAssertEqual(host.workspace.selectedTab?.find.isPresented, true)
    }

    /// Nothing copied, nothing confirmed. A tab with no page cannot be copied,
    /// and `readCurrentPage` has already said why. A confirmation on top would
    /// claim a copy that never happened.
    func testACopyThatDidNotHappenIsNotConfirmed() async throws {
        let host = try makeHost()

        await PageMenuActions(workspace: host.workspace).perform(.copyForAI)

        XCTAssertEqual(
            host.workspace.selectedTab?.session.pageNotice,
            "There is no web page in this tab to copy."
        )
    }

    // MARK: - When a row acts

    /// A tapped row closes the sheet and waits: it runs once the sheet has
    /// gone. Share is why. It presents the system's sheet from the window's
    /// root view controller, which cannot present anything while this one is
    /// still up.
    func testARowClosesTheSheetBeforeItActs() {
        var presentation = PageMenuPresentation()
        presentation.open()
        XCTAssertTrue(presentation.isPresented)

        presentation.choose(.share)

        XCTAssertFalse(presentation.isPresented)
        XCTAssertEqual(presentation.didDismiss(), .share)
    }

    /// A row runs once. The sheet closing again later runs nothing.
    func testARowActsOnlyOnce() {
        var presentation = PageMenuPresentation()
        presentation.open()
        presentation.choose(.reload)
        _ = presentation.didDismiss()

        XCTAssertNil(presentation.didDismiss())
    }

    /// Swiping the sheet away chooses nothing, and runs nothing.
    func testSwipingTheSheetAwayRunsNothing() {
        var presentation = PageMenuPresentation()
        presentation.open()
        presentation.isPresented = false

        XCTAssertNil(presentation.didDismiss())
    }

    /// Bookmarks is a sheet of its own, and SwiftUI presents one sheet at a
    /// time. Choosing it closes the menu, and Bookmarks opens only once the
    /// menu has gone. There is nothing left to run.
    func testChoosingBookmarksOpensItOnceTheMenuHasGone() {
        var presentation = PageMenuPresentation()
        presentation.open()
        presentation.choose(.bookmarks)

        XCTAssertFalse(presentation.isPresented)
        XCTAssertNil(presentation.destination, "not while the menu is still closing")
        XCTAssertNil(presentation.didDismiss(), "a list is opened, not run")
        XCTAssertEqual(presentation.destination, .bookmarks)
    }

    /// History likewise.
    func testChoosingHistoryOpensItOnceTheMenuHasGone() {
        var presentation = PageMenuPresentation()
        presentation.open()
        presentation.choose(.history)

        XCTAssertNil(presentation.destination)
        XCTAssertNil(presentation.didDismiss())
        XCTAssertEqual(presentation.destination, .history)
    }

    /// Every other row runs as before and opens no list.
    func testEveryOtherRowRunsAndOpensNoList() {
        for item in PageMenuItem.allCases where item != .bookmarks && item != .history {
            var presentation = PageMenuPresentation()
            presentation.open()
            presentation.choose(item)

            XCTAssertEqual(presentation.didDismiss(), item)
            XCTAssertNil(presentation.destination, "\(item) opened a list")
        }
    }
}
