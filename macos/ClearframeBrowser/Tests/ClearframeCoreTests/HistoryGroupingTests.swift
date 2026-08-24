import Foundation
import XCTest
@testable import ClearframeCore

/// Grouping stored visits into days. Pure, with the calendar and "now"
/// injected, so the boundaries can be tested without waiting for midnight.
final class HistoryGroupingTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Bucharest")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func visit(_ title: String, at when: Date) -> HistoryRecord {
        HistoryRecord(title: title, url: "https://example.com/\(title)", visitedAt: when)
    }

    func testEmptyHistoryHasNoGroups() {
        XCTAssertTrue(HistoryDayGrouping.groups([], calendar: calendar, now: date(2026, 8, 24)).isEmpty)
    }

    func testVisitsSplitIntoTodayYesterdayAndTheDayBefore() {
        let now = date(2026, 8, 24, 17)
        let groups = HistoryDayGrouping.groups([
            visit("a", at: date(2026, 8, 24, 9)),
            visit("b", at: date(2026, 8, 23, 22)),
            visit("c", at: date(2026, 8, 22, 8))
        ], calendar: calendar, now: now)

        XCTAssertEqual(groups.map(\.title), ["Today", "Yesterday", "Saturday 22 August"])
        XCTAssertEqual(groups.map { $0.visits.count }, [1, 1, 1])
    }

    func testVisitsOnOneDayStayTogetherNewestFirst() {
        let now = date(2026, 8, 24, 23)
        let groups = HistoryDayGrouping.groups([
            visit("morning", at: date(2026, 8, 24, 9)),
            visit("evening", at: date(2026, 8, 24, 21)),
            visit("noon", at: date(2026, 8, 24, 12))
        ], calendar: calendar, now: now)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].visits.map(\.title), ["evening", "noon", "morning"])
    }

    /// `recordVisit` takes an arbitrary date, so out-of-order input is
    /// reachable. A diary that jumps backwards and forwards reads as a bug.
    func testOutOfOrderInputIsSortedRatherThanTrusted() {
        let now = date(2026, 8, 24, 17)
        let groups = HistoryDayGrouping.groups([
            visit("older", at: date(2026, 8, 22, 8)),
            visit("newest", at: date(2026, 8, 24, 9)),
            visit("middle", at: date(2026, 8, 23, 22))
        ], calendar: calendar, now: now)

        XCTAssertEqual(groups.map(\.title), ["Today", "Yesterday", "Saturday 22 August"])
    }

    /// Midnight belongs to the day it starts, not the one it ends.
    func testAVisitAtMidnightBelongsToThatDay() {
        let now = date(2026, 8, 24, 17)
        let groups = HistoryDayGrouping.groups([
            visit("midnight", at: date(2026, 8, 24, 0, 0))
        ], calendar: calendar, now: now)

        XCTAssertEqual(groups.map(\.title), ["Today"])
    }

    /// A day that is 23 or 25 hours long must still be one day. Bucketing by
    /// subtracting 86,400 seconds would put these in the wrong group.
    func testADaylightSavingChangeDoesNotSplitOrMergeDays() {
        // Romania moves its clocks on the last Sunday of October.
        let now = date(2026, 10, 26, 12)
        let groups = HistoryDayGrouping.groups([
            visit("after", at: date(2026, 10, 25, 23)),
            visit("before", at: date(2026, 10, 25, 1)),
            visit("previous", at: date(2026, 10, 24, 12))
        ], calendar: calendar, now: now)

        XCTAssertEqual(groups.count, 2, "the long day is still one day")
        XCTAssertEqual(groups[0].visits.count, 2)
        XCTAssertEqual(groups[1].visits.count, 1)
    }

    /// Nothing is dropped or merged, whatever the cap holds.
    func testEveryVisitSurvivesGroupingAtTheStoredCap() {
        let now = date(2026, 8, 24, 23, 59)
        let visits = (0..<500).map { index in
            visit("v\(index)", at: calendar.date(byAdding: .minute, value: -index, to: now)!)
        }

        let groups = HistoryDayGrouping.groups(visits, calendar: calendar, now: now)

        XCTAssertEqual(groups.reduce(0) { $0 + $1.visits.count }, 500)
        XCTAssertEqual(Set(groups.flatMap { $0.visits.map(\.id) }).count, 500, "no visit is duplicated")
    }

    /// The store keeps one record per visit and the address bar ranks on that
    /// repetition, so the page must not quietly collapse it.
    func testRepeatVisitsToOneAddressAreAllKept() {
        let now = date(2026, 8, 24, 17)
        let repeated = (0..<4).map { index in
            HistoryRecord(
                title: "Same",
                url: "https://example.com/same",
                visitedAt: calendar.date(byAdding: .hour, value: -index, to: now)!
            )
        }

        let groups = HistoryDayGrouping.groups(repeated, calendar: calendar, now: now)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].visits.count, 4, "four visits are four rows, not one")
    }

    func testGroupTitleIdentifiesTheGroup() {
        let now = date(2026, 8, 24, 17)
        let groups = HistoryDayGrouping.groups([visit("a", at: now)], calendar: calendar, now: now)
        XCTAssertEqual(groups.first?.id, "Today")
    }
}
