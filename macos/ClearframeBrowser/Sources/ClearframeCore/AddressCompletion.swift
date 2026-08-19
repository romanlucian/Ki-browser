import Foundation

/// One place the address field could be trying to reach, with the evidence for
/// how likely it is: how often it has been opened, when it was last opened, and
/// whether it is bookmarked.
public struct AddressCandidate: Equatable, Sendable {
    public let url: String
    /// What the page called itself, for the suggestion list. Empty when only a
    /// bare address is known.
    public let title: String
    public let visits: Int
    public let lastVisit: Date
    public let isBookmarked: Bool

    public init(
        url: String,
        title: String = "",
        visits: Int,
        lastVisit: Date,
        isBookmarked: Bool
    ) {
        self.url = url
        self.title = title
        self.visits = visits
        self.lastVisit = lastVisit
        self.isBookmarked = isBookmarked
    }
}

/// One row under the address bar.
public struct AddressSuggestion: Equatable, Identifiable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Somewhere this profile has been or saved.
        case place(isBookmarked: Bool)
        /// Hand what was typed to the chosen search engine. Always offered, so
        /// there is a way out of the list that does not depend on history.
        case search
    }

    public let kind: Kind
    /// What the row reads as: a page's title, or the typed text for a search.
    public let title: String
    /// The address the row opens, already normalised. Empty for a search row,
    /// whose destination is decided by the engine at the moment it is used.
    public let url: String

    public var id: String {
        switch kind {
        case .search: return "search:\(title)"
        case .place: return "place:\(url)"
        }
    }

    public init(kind: Kind, title: String, url: String) {
        self.kind = kind
        self.title = title
        self.url = url
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
        var titles: [String: String] = [:]
        var keys: Set<String> = []

        for record in history {
            let key = presentable(record.url)
            guard !key.isEmpty else { continue }
            keys.insert(key)
            visits[key, default: 0] += 1
            // The newest visit names the page: a title can change, and the
            // current one is the one a reader would recognise.
            if lastVisit[key] == nil || record.visitedAt >= lastVisit[key]! {
                lastVisit[key] = record.visitedAt
                if !record.title.isEmpty { titles[key] = record.title }
            }
        }

        var bookmarked: Set<String> = []
        for bookmark in bookmarks {
            let key = presentable(bookmark.url)
            guard !key.isEmpty else { continue }
            keys.insert(key)
            bookmarked.insert(key)
            if visits[key] == nil { visits[key] = 0 }
            // A bookmark's name was chosen deliberately, so it wins over
            // whatever the page happened to call itself.
            if !bookmark.title.isEmpty { titles[key] = bookmark.title }
        }

        return keys.map { key in
            AddressCandidate(
                url: key,
                title: titles[key] ?? "",
                visits: visits[key] ?? 0,
                lastVisit: lastVisit[key] ?? .distantPast,
                isBookmarked: bookmarked.contains(key)
            )
        }
    }

    /// The rows to show under the address bar for what has been typed.
    ///
    /// Local only. Chrome fills part of its list by sending each keystroke to
    /// its search engine; this sends nothing anywhere. Everything offered is
    /// already in this profile, plus one row that hands the typed text to the
    /// chosen engine — an action the reader takes, not a request made while
    /// they type.
    public static func suggestions(
        for typed: String,
        in candidates: [AddressCandidate],
        limit: Int = 8
    ) -> [AddressSuggestion] {
        let trimmed = typed.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        // "garlic chilli" has to find the page "garlic" finds. Each word is
        // matched separately, and all of them must land somewhere.
        let terms = trimmed.lowercased().split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return [] }
        // Only a single unbroken word can be the start of an address.
        let needle = terms.count == 1 ? normalized(trimmed) : ""

        let matches = candidates
            .compactMap { candidate -> (AddressCandidate, MatchStrength)? in
                guard let strength = strength(of: candidate, terms: terms, needle: needle) else { return nil }
                return (candidate, strength)
            }
            .sorted { left, right in
                if left.1 != right.1 { return left.1.rawValue < right.1.rawValue }
                return isBetter(left.0, right.0)
            }
            .prefix(max(0, limit - 1))
            .map { candidate, _ in
                AddressSuggestion(
                    kind: .place(isBookmarked: candidate.isBookmarked),
                    title: candidate.title.isEmpty ? candidate.url : candidate.title,
                    url: candidate.url
                )
            }

        // The search row sits behind the best place and ahead of the rest: a
        // reader who typed a phrase wants it early, one who typed an address
        // they know wants that first.
        let search = AddressSuggestion(kind: .search, title: trimmed, url: "")
        guard let best = matches.first else { return [search] }
        return [best, search] + matches.dropFirst()
    }

    /// How well one candidate answers what was typed. Lower is better; the
    /// order of the cases is the order rows appear in.
    private enum MatchStrength: Int {
        /// The address begins with it — the thing inline completion would do.
        case addressPrefix = 0
        /// A word of the title begins with it: "gar" finding "Garlic Chilli".
        case titleWord = 1
        /// It appears somewhere in the address.
        case addressContains = 2
    }

    private static func strength(
        of candidate: AddressCandidate,
        terms: [String],
        needle: String
    ) -> MatchStrength? {
        let url = candidate.url.lowercased()
        if !needle.isEmpty, url.hasPrefix(needle) { return .addressPrefix }

        let title = candidate.title.lowercased()
        if !title.isEmpty {
            let words = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            if terms.allSatisfy({ term in words.contains { $0.hasPrefix(term) } }) { return .titleWord }
        }
        if terms.allSatisfy({ url.contains($0) }) { return .addressContains }
        return nil
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

        // What is kept of the typed text before the remainder is appended.
        //
        // Appending works by counting characters off the front of the match, so
        // it is only sound while normalising has removed characters from the
        // front too — a scheme, a `www.`, a change of case. Trailing slashes
        // come off the *back*, which leaves the counts out of step: typing
        // "google.com/" would otherwise finish as "google.com//search?q=x".
        // Dropping them here puts the two ends back in agreement.
        var kept = trimmed
        while kept.hasSuffix("/") { kept.removeLast() }

        let prefix = normalized(kept)
        guard !prefix.isEmpty else { return nil }

        // Someone who has typed a whole address has said where they are going.
        // Extending it into the deepest page under that host is how typing
        // "google.com" used to finish as an old search-results URL, and Return
        // then opened the search instead of the site.
        guard !candidates.contains(where: { $0.url.lowercased() == prefix }) else { return nil }

        let matches = candidates.filter {
            let folded = $0.url.lowercased()
            return folded.hasPrefix(prefix) && folded.count > prefix.count
        }
        guard let best = matches.min(by: isBetter) else { return nil }

        // Keep what was typed and append only the remainder, so the caret never
        // jumps and nobody's capitalisation is corrected at them.
        let remainder = best.url.dropFirst(min(prefix.count, best.url.count))
        return kept + remainder
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

    /// One address as a reader would type it: no scheme, no `www.`, no
    /// trailing slash — and with its case left alone everywhere case carries
    /// meaning.
    ///
    /// Only the host is lowered. A host is case-insensitive; a path and a query
    /// are not, and folding them destroys the address: a YouTube video id
    /// becomes `watch?v=dqw4w9wgxcq` and a Google Docs link becomes a document
    /// that does not exist. Those strings are what a suggestion row opens, so
    /// this is the difference between a working row and a dead link.
    static func presentable(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for scheme in ["https://", "http://"] where text.lowercased().hasPrefix(scheme) {
            text.removeFirst(scheme.count)
        }
        if text.lowercased().hasPrefix("www.") { text.removeFirst(4) }
        while text.hasSuffix("/") { text.removeLast() }
        guard let boundary = text.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) else {
            return text.lowercased()
        }
        return text[..<boundary].lowercased() + text[boundary...]
    }

    /// The same address folded flat, for comparing only. Never stored, never
    /// navigated to.
    static func normalized(_ value: String) -> String {
        presentable(value).lowercased()
    }
}

private extension AddressCandidate {
    /// Bookmarking something is a deliberate act, so it counts for more than a
    /// single visit — but it never outranks a site opened many times.
    var score: Int { visits + (isBookmarked ? 3 : 0) }
}
