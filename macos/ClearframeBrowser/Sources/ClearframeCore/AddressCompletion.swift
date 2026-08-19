import Foundation

/// One place the address field could be trying to reach, with the evidence for
/// how likely it is: how often it has been opened, when it was last opened, and
/// whether it is bookmarked.
public struct AddressCandidate: Equatable, Sendable {
    public let url: String
    public let visits: Int
    public let lastVisit: Date
    public let isBookmarked: Bool

    public init(url: String, visits: Int, lastVisit: Date, isBookmarked: Bool) {
        self.url = url
        self.visits = visits
        self.lastVisit = lastVisit
        self.isBookmarked = isBookmarked
    }
}

/// Finishes an address the reader has started typing, from what this Mac has
/// already visited.
///
/// Entirely local and entirely historical: it proposes only addresses already
/// in this profile's own history or bookmarks, never a guess, a popular-sites
/// list, or anything fetched. Typing a prefix that matches nothing completes to
/// nothing rather than inventing a plausible host — the whole point is that a
/// completion is a place the reader has actually been.
///
/// Foundation-only, and pure: the same inputs give the same completion, which
/// is what makes the ranking testable rather than a matter of opinion.
public enum AddressCompletion {
    /// Gathers what the field can complete to. Repeated visits to one address
    /// are the frequency signal — history stores a record per visit, so the
    /// count falls out of grouping rather than needing its own column.
    public static func candidates(
        history: [HistoryRecord],
        bookmarks: [BookmarkRecord]
    ) -> [AddressCandidate] {
        var visits: [String: Int] = [:]
        var lastVisit: [String: Date] = [:]
        var canonical: [String: String] = [:]

        for record in history {
            let key = normalized(record.url)
            guard !key.isEmpty else { continue }
            visits[key, default: 0] += 1
            if let seen = lastVisit[key] {
                lastVisit[key] = max(seen, record.visitedAt)
            } else {
                lastVisit[key] = record.visitedAt
            }
            canonical[key] = key
        }

        var bookmarked: Set<String> = []
        for bookmark in bookmarks {
            let key = normalized(bookmark.url)
            guard !key.isEmpty else { continue }
            bookmarked.insert(key)
            canonical[key] = key
            if visits[key] == nil { visits[key] = 0 }
        }

        return canonical.keys.map { key in
            AddressCandidate(
                url: key,
                visits: visits[key] ?? 0,
                lastVisit: lastVisit[key] ?? .distantPast,
                isBookmarked: bookmarked.contains(key)
            )
        }
    }

    /// What the field should show for what has been typed so far, or `nil` to
    /// leave it alone.
    ///
    /// The reader's own keystrokes are preserved exactly — only the tail is
    /// added — so completing never rewrites what someone has already typed,
    /// including its capitalisation.
    public static func completion(for typed: String, in candidates: [AddressCandidate]) -> String? {
        let trimmed = typed.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // A space means the reader is writing a search phrase, not an address.
        guard !trimmed.contains(" ") else { return nil }

        let prefix = normalized(trimmed)
        guard !prefix.isEmpty else { return nil }

        let matches = candidates.filter { $0.url.hasPrefix(prefix) && $0.url.count > prefix.count }
        guard let best = matches.min(by: isBetter) else { return nil }

        // Keep what was typed verbatim and append only the remainder, so the
        // caret never jumps and nobody's capitalisation is corrected at them.
        let remainder = best.url.dropFirst(prefix.count)
        return trimmed + remainder
    }

    /// The ranking, in order of what actually decides it.
    private static func isBetter(_ a: AddressCandidate, _ b: AddressCandidate) -> Bool {
        // A site's front door beats a page inside it: typing "you" should offer
        // youtube.com, not the last video watched there.
        let aRoot = isBareHost(a.url)
        let bRoot = isBareHost(b.url)
        if aRoot != bRoot { return aRoot }

        if a.score != b.score { return a.score > b.score }
        if a.lastVisit != b.lastVisit { return a.lastVisit > b.lastVisit }
        if a.url.count != b.url.count { return a.url.count < b.url.count }
        return a.url < b.url
    }

    private static func isBareHost(_ normalizedURL: String) -> Bool {
        !normalizedURL.contains("/")
    }

    /// One address reduced to what a reader would type: no scheme, no `www.`,
    /// no trailing slash, lowercased. Typing "you" has to match
    /// `https://www.youtube.com/` or the feature is useless on real history.
    static func normalized(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for scheme in ["https://", "http://"] where text.hasPrefix(scheme) {
            text.removeFirst(scheme.count)
        }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }
}

private extension AddressCandidate {
    /// Bookmarking something is a deliberate act, so it counts for more than a
    /// single visit — but it never outranks a site opened many times.
    var score: Int { visits + (isBookmarked ? 3 : 0) }
}
