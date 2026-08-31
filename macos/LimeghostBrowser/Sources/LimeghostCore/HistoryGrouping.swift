import Foundation

/// One day's worth of visits, for a history page that reads as a diary
/// rather than as one unbroken list.
public struct HistoryDayGroup: Equatable, Identifiable, Sendable {
    /// Stable across a redraw because it names the day, not the position.
    public var id: String { title }
    /// "Today", "Yesterday", or the date itself.
    public let title: String
    /// Newest first, the same order the store keeps.
    public let visits: [HistoryRecord]

    public init(title: String, visits: [HistoryRecord]) {
        self.title = title
        self.visits = visits
    }
}

/// Splits stored visits into days.
///
/// Foundation-only, and pure: the calendar and "now" are passed in rather
/// than read from the machine, so the boundaries between today, yesterday
/// and everything before them can be tested without waiting for midnight or
/// pretending a DST change does not happen.
///
/// Cheap by construction. History is capped at a few hundred visits and the
/// store keeps it newest-first, so this is one pass with no index, no
/// pagination, and nothing to invalidate.
public enum HistoryDayGrouping {
    /// Groups `visits` by the day they happened, newest day first.
    ///
    /// Sorts defensively rather than trusting the input: `recordVisit`
    /// accepts an arbitrary date, so a test — or a clock that moved
    /// backwards — can produce records out of order, and a diary that jumps
    /// backwards and forwards reads as a bug.
    ///
    /// Repeat visits to the same address are deliberately *not* collapsed.
    /// The store keeps one record per visit, and that repetition is the
    /// frequency signal the address bar ranks on; hiding it here would make
    /// the page disagree with what is actually stored.
    public static func groups(
        _ visits: [HistoryRecord],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [HistoryDayGroup] {
        guard !visits.isEmpty else { return [] }

        let ordered = visits.sorted { $0.visitedAt > $1.visitedAt }
        var groups: [HistoryDayGroup] = []
        var currentDay: Date?
        var currentVisits: [HistoryRecord] = []

        func closeCurrentDay() {
            guard let currentDay, !currentVisits.isEmpty else { return }
            groups.append(HistoryDayGroup(
                title: title(for: currentDay, calendar: calendar, now: now),
                visits: currentVisits
            ))
            currentVisits = []
        }

        for visit in ordered {
            let day = calendar.startOfDay(for: visit.visitedAt)
            if day != currentDay {
                closeCurrentDay()
                currentDay = day
            }
            currentVisits.append(visit)
        }
        closeCurrentDay()
        return groups
    }

    /// What to call a day. "Today" and "Yesterday" are what a person would
    /// say; anything older is named by its date, because "3 days ago" makes
    /// the reader do the arithmetic.
    static func title(for day: Date, calendar: Calendar, now: Date) -> String {
        if calendar.isDate(day, inSameDayAs: calendar.startOfDay(for: now)) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .autoupdatingCurrent
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return formatter.string(from: day)
    }
}
