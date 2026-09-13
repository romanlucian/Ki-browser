import XCTest
import LimeghostCore
@testable import Limeghost
@testable import LimeghostShared

@MainActor
final class HistorySheetTests: XCTestCase {
    /// A suite of its own, emptied afterwards: these tests run inside the app.
    private func makeHost() throws -> WorkspaceHost {
        let suiteName = "clearframe.iosHistory.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return WorkspaceHost.forTesting(defaults: defaults)
    }

    /// A fixed calendar, as Core's own grouping tests use, so "today" does not
    /// depend on when or where the suite runs.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Bucharest")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }()

    private func september(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    /// Visits come back as days, newest first. A search filters them before
    /// they are grouped, so a day with nothing matching does not appear.
    func testVisitsComeBackAsDaysFilteredBeforeGrouping() throws {
        let host = try makeHost()
        let store = host.workspace.dataStore
        store.recordVisit(title: "Bread", url: "https://example.com/bread", at: september(12, 9))
        store.recordVisit(title: "Soup", url: "https://example.com/soup", at: september(13, 9))
        store.recordVisit(title: "Cake", url: "https://example.com/cake", at: september(13, 11))
        let model = HistoryModel(workspace: host.workspace)
        let now = september(13, 17)

        let everything = model.days(matching: "", calendar: calendar, now: now)
        XCTAssertEqual(everything.map(\.title), ["Today", "Yesterday"])
        XCTAssertEqual(everything.first?.visits.map(\.title), ["Cake", "Soup"])

        let bread = model.days(matching: "BREAD", calendar: calendar, now: now)
        XCTAssertEqual(bread.map(\.title), ["Yesterday"])
        XCTAssertEqual(bread.first?.visits.map(\.title), ["Bread"])
    }

    /// A visit opens in the tab in front, through the same door as a bookmark.
    func testOpeningAVisitLoadsItInTheTabInFront() throws {
        let host = try makeHost()
        host.workspace.dataStore.recordVisit(title: "Example", url: "https://example.com/visited")
        let visit = try XCTUnwrap(host.workspace.dataStore.history.first)
        let tabsBefore = host.workspace.visibleTabs.count

        HistoryModel(workspace: host.workspace).open(visit)

        XCTAssertEqual(host.workspace.visibleTabs.count, tabsBefore)
        XCTAssertEqual(host.workspace.selectedTab?.session.currentURLString, "https://example.com/visited")
    }

    /// Open in New Tab puts a new tab in front, holding the visit.
    func testOpenInNewTabAddsATab() throws {
        let host = try makeHost()
        host.workspace.dataStore.recordVisit(title: "Example", url: "https://example.com/visited")
        let visit = try XCTUnwrap(host.workspace.dataStore.history.first)
        let tabsBefore = host.workspace.visibleTabs.count

        HistoryModel(workspace: host.workspace).open(visit, inNewTab: true)

        XCTAssertEqual(host.workspace.visibleTabs.count, tabsBefore + 1)
        XCTAssertEqual(host.workspace.selectedTab?.session.currentURLString, "https://example.com/visited")
    }

    /// Delete takes one visit and Clear takes them all. Clear is offered only
    /// while there is something to clear.
    func testDeleteRemovesOneVisitAndClearRemovesThemAll() throws {
        let host = try makeHost()
        let store = host.workspace.dataStore
        store.recordVisit(title: "Bread", url: "https://example.com/bread")
        store.recordVisit(title: "Soup", url: "https://example.com/soup")
        let model = HistoryModel(workspace: host.workspace)
        XCTAssertTrue(model.canClear)

        model.delete(try XCTUnwrap(store.history.first { $0.title == "Soup" }))
        XCTAssertEqual(store.history.map(\.title), ["Bread"])

        model.clear()
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertFalse(model.canClear)
    }

    /// The confirmation counts what it will remove and names this device. It
    /// never names the Mac, whose wording it was adapted from.
    func testClearingSaysHowManyVisitsAndWhere() {
        XCTAssertEqual(
            HistoryWording.clearMessage(visitCount: 1),
            "This removes 1 stored visit from this device and cannot be undone. Your bookmarks and open tabs are not affected."
        )
        XCTAssertTrue(HistoryWording.clearMessage(visitCount: 3).contains("3 stored visits"))
        XCTAssertFalse(HistoryWording.clearMessage(visitCount: 3).contains("Mac"))
    }

    /// A visit with no title shows its address, so no row is blank.
    func testAVisitWithNoTitleShowsItsAddress() {
        XCTAssertEqual(
            HistoryWording.title(of: HistoryRecord(title: "", url: "https://example.com/untitled")),
            "https://example.com/untitled"
        )
        XCTAssertEqual(HistoryWording.title(of: HistoryRecord(title: "Soup", url: "https://example.com/soup")), "Soup")
    }
}
