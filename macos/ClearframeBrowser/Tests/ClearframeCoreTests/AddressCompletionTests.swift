import Foundation
import XCTest
@testable import ClearframeCore

/// Address completion is a ranking problem, and a ranking is an opinion until
/// it is pinned down. These tests are the opinion: what a prefix should finish
/// to, and — just as important — when it should finish to nothing.
final class AddressCompletionTests: XCTestCase {

    private func candidate(
        _ url: String,
        visits: Int = 1,
        daysAgo: Double = 1,
        bookmarked: Bool = false
    ) -> AddressCandidate {
        AddressCandidate(
            url: AddressCompletion.normalized(url),
            visits: visits,
            lastVisit: Date(timeIntervalSince1970: 1_000_000 - daysAgo * 86_400),
            isBookmarked: bookmarked
        )
    }

    // MARK: - Matching what a reader would actually type

    func testTypingOneLetterFinishesTheSiteBehindIt() {
        let candidates = [candidate("https://www.youtube.com/", visits: 40)]

        XCTAssertEqual(AddressCompletion.completion(for: "y", in: candidates), "youtube.com")
        XCTAssertEqual(AddressCompletion.completion(for: "you", in: candidates), "youtube.com")
        XCTAssertEqual(AddressCompletion.completion(for: "youtube.co", in: candidates), "youtube.com")
    }

    /// History stores full addresses; readers type the middle of them. Without
    /// this the feature never fires on real data.
    func testSchemeAndWwwAndTrailingSlashDoNotBlockAMatch() {
        for stored in [
            "https://www.youtube.com/",
            "http://youtube.com",
            "https://youtube.com/",
            "YouTube.com"
        ] {
            XCTAssertEqual(
                AddressCompletion.completion(for: "you", in: [candidate(stored)]),
                "youtube.com",
                "\(stored) should be reachable by typing 'you'"
            )
        }
    }

    func testWhatWasTypedIsNeverRewritten() {
        let candidates = [candidate("https://youtube.com", visits: 10)]
        // The tail is appended; the reader's own capitals stay theirs.
        XCTAssertEqual(AddressCompletion.completion(for: "You", in: candidates), "Youtube.com")
    }

    // MARK: - When it must stay quiet

    func testNothingIsInventedForAPrefixNobodyHasVisited() {
        let candidates = [candidate("https://youtube.com", visits: 99)]
        XCTAssertNil(AddressCompletion.completion(for: "z", in: candidates))
        XCTAssertNil(AddressCompletion.completion(for: "youtube.com.evil", in: candidates))
    }

    func testASpaceMeansASearchAndNeverCompletes() {
        let candidates = [candidate("https://youtube.com", visits: 99)]
        XCTAssertNil(AddressCompletion.completion(for: "you tube", in: candidates))
        XCTAssertNil(AddressCompletion.completion(for: "how to ", in: candidates))
    }

    func testAnAlreadyCompleteAddressIsLeftAlone() {
        let candidates = [candidate("https://youtube.com", visits: 99)]
        XCTAssertNil(
            AddressCompletion.completion(for: "youtube.com", in: candidates),
            "there is nothing left to add, so nothing should be selected"
        )
    }

    func testEmptyInputCompletesToNothing() {
        let candidates = [candidate("https://youtube.com", visits: 99)]
        XCTAssertNil(AddressCompletion.completion(for: "", in: candidates))
        XCTAssertNil(AddressCompletion.completion(for: "   ", in: candidates))
        XCTAssertNil(AddressCompletion.completion(for: "y", in: []))
    }

    // MARK: - The ranking

    /// The single most important rule: typing a couple of letters must offer
    /// the site, not the last page read on it.
    func testASitesFrontDoorBeatsAPageInsideIt() {
        let candidates = [
            candidate("https://youtube.com/watch?v=abcdefg", visits: 50),
            candidate("https://youtube.com", visits: 2)
        ]

        XCTAssertEqual(AddressCompletion.completion(for: "you", in: candidates), "youtube.com")
    }

    func testTheMoreVisitedSiteWins() {
        let candidates = [
            candidate("https://yahoo.com", visits: 2),
            candidate("https://youtube.com", visits: 30)
        ]

        XCTAssertEqual(AddressCompletion.completion(for: "y", in: candidates), "youtube.com")
    }

    func testRecencyBreaksATieOnVisits() {
        let candidates = [
            candidate("https://yahoo.com", visits: 5, daysAgo: 90),
            candidate("https://yandex.com", visits: 5, daysAgo: 1)
        ]

        XCTAssertEqual(AddressCompletion.completion(for: "ya", in: candidates), "yandex.com")
    }

    /// Bookmarking is deliberate, so it counts for more than one stray visit —
    /// but it must not outrank somewhere opened every day.
    func testABookmarkOutranksAStrayVisitButNotADailyHabit() {
        let bookmarkWins = [
            candidate("https://yahoo.com", visits: 1),
            candidate("https://yandex.com", visits: 0, bookmarked: true)
        ]
        XCTAssertEqual(AddressCompletion.completion(for: "ya", in: bookmarkWins), "yandex.com")

        let habitWins = [
            candidate("https://yahoo.com", visits: 40),
            candidate("https://yandex.com", visits: 0, bookmarked: true)
        ]
        XCTAssertEqual(AddressCompletion.completion(for: "ya", in: habitWins), "yahoo.com")
    }

    func testTheSameAddressIsOneCandidateHoweverOftenItWasVisited() {
        let visits = (0..<5).map {
            HistoryRecord(
                title: "YouTube",
                url: "https://www.youtube.com/",
                visitedAt: Date(timeIntervalSince1970: 1_000 + Double($0))
            )
        }
        let candidates = AddressCompletion.candidates(history: visits, bookmarks: [])

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.url, "youtube.com")
        XCTAssertEqual(candidates.first?.visits, 5, "repeat visits are the frequency signal")
        XCTAssertEqual(candidates.first?.lastVisit, Date(timeIntervalSince1970: 1_004))
    }

    func testBookmarksAreCandidatesEvenWhenNeverVisited() {
        let candidates = AddressCompletion.candidates(
            history: [],
            bookmarks: [BookmarkRecord(title: "Docs", url: "https://developer.apple.com/documentation")]
        )

        XCTAssertEqual(candidates.count, 1)
        XCTAssertTrue(candidates.first?.isBookmarked == true)
        XCTAssertEqual(
            AddressCompletion.completion(for: "developer", in: candidates),
            "developer.apple.com/documentation"
        )
    }

    /// One address held in both places is one candidate, carrying both signals.
    func testAVisitedBookmarkIsNotCountedTwice() {
        let candidates = AddressCompletion.candidates(
            history: [HistoryRecord(title: "YouTube", url: "https://youtube.com")],
            bookmarks: [BookmarkRecord(title: "YouTube", url: "https://www.youtube.com/")]
        )

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.visits, 1)
        XCTAssertTrue(candidates.first?.isBookmarked == true)
    }

    /// The completion has to be something the browser can actually open: it is
    /// handed straight to the address bar's own resolver.
    func testACompletionResolvesToARealAddress() {
        let candidates = [candidate("https://www.youtube.com/")]
        let completed = AddressCompletion.completion(for: "you", in: candidates)

        XCTAssertEqual(completed, "youtube.com")
        XCTAssertNotNil(WebURLPolicy.validatedURL("https://\(completed ?? "")"))
    }

    func testRankingIsStableForCandidatesThatTieOnEverything() {
        let a = candidate("https://alpha.com", visits: 3, daysAgo: 5)
        let b = candidate("https://alpine.com", visits: 3, daysAgo: 5)

        XCTAssertEqual(
            AddressCompletion.completion(for: "alp", in: [a, b]),
            AddressCompletion.completion(for: "alp", in: [b, a]),
            "the same history must complete the same way whatever order it arrives in"
        )
    }

    // MARK: - The suggestion list

    private func titled(_ url: String, _ title: String, visits: Int = 1, bookmarked: Bool = false) -> AddressCandidate {
        AddressCandidate(
            url: AddressCompletion.normalized(url),
            title: title,
            visits: visits,
            lastVisit: Date(timeIntervalSince1970: 1_000),
            isBookmarked: bookmarked
        )
    }

    func testTheBestPlaceLeadsAndASearchAlwaysFollowsIt() {
        let candidates = [
            titled("https://youtube.com", "YouTube", visits: 20),
            titled("https://youtube.com/watch?v=abc", "A video - YouTube", visits: 3)
        ]
        let rows = AddressCompletion.suggestions(for: "you", in: candidates)

        XCTAssertEqual(rows.first?.url, "youtube.com", "the front door leads")
        XCTAssertEqual(rows[1].kind, .search, "a way to search is always the second option")
        XCTAssertEqual(rows[1].title, "you", "the search row offers what was typed")
        XCTAssertEqual(rows.last?.url, "youtube.com/watch?v=abc")
    }

    /// Somewhere unvisited must still be reachable: the list can never be a
    /// dead end just because history has nothing to say.
    func testAPrefixMatchingNothingStillOffersASearch() {
        let rows = AddressCompletion.suggestions(for: "kjhgfd", in: [titled("https://youtube.com", "YouTube")])

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.kind, .search)
        XCTAssertEqual(rows.first?.title, "kjhgfd")
    }

    func testNothingTypedShowsNothing() {
        XCTAssertTrue(AddressCompletion.suggestions(for: "", in: [titled("https://a.com", "A")]).isEmpty)
        XCTAssertTrue(AddressCompletion.suggestions(for: "  ", in: [titled("https://a.com", "A")]).isEmpty)
    }

    /// Typing a word from a page's name has to find it — that is most of what
    /// the list is for, and it is the half inline completion cannot do.
    func testAWordOfATitleFindsThePage() {
        let candidates = [titled("https://example.com/recipes/42", "Garlic Chilli Oil Recipe")]
        let rows = AddressCompletion.suggestions(for: "garlic", in: candidates)

        XCTAssertEqual(rows.first?.url, "example.com/recipes/42")
        XCTAssertEqual(rows.first?.title, "Garlic Chilli Oil Recipe")
    }

    func testAnAddressMatchOutranksATitleMatchWhichOutranksAMidAddressMatch() {
        let candidates = [
            titled("https://elsewhere.com/news", "News about mail", visits: 50),
            titled("https://mail.com", "Mail", visits: 1),
            titled("https://host.com/mail-archive", "Archive", visits: 90)
        ]
        let rows = AddressCompletion.suggestions(for: "mail", in: candidates).filter { $0.kind != .search }

        XCTAssertEqual(rows.map(\.url), ["mail.com", "elsewhere.com/news", "host.com/mail-archive"],
                       "address prefix, then title word, then anywhere in the address")
    }

    func testTheListIsCappedSoItCannotSwallowTheWindow() {
        let candidates = (0..<40).map { titled("https://example.com/page\($0)", "Page \($0)") }
        let rows = AddressCompletion.suggestions(for: "example", in: candidates, limit: 6)

        XCTAssertEqual(rows.count, 6)
        XCTAssertEqual(rows.filter { $0.kind == .search }.count, 1, "exactly one search row, however many places match")
    }

    func testARowCarriesWhetherItWasBookmarked() {
        let rows = AddressCompletion.suggestions(
            for: "you",
            in: [titled("https://youtube.com", "YouTube", bookmarked: true)]
        )

        XCTAssertEqual(rows.first?.kind, .place(isBookmarked: true))
    }

    func testARowWithoutATitleFallsBackToItsAddress() {
        let rows = AddressCompletion.suggestions(for: "you", in: [titled("https://youtube.com", "")])

        XCTAssertEqual(rows.first?.title, "youtube.com", "a row must never render blank")
    }

    func testABookmarksOwnNameWinsOverWhateverThePageCalledItself() {
        let candidates = AddressCompletion.candidates(
            history: [HistoryRecord(title: "YouTube - random video page", url: "https://youtube.com")],
            bookmarks: [BookmarkRecord(title: "Videos", url: "https://youtube.com")]
        )

        XCTAssertEqual(candidates.first?.title, "Videos")
    }

    // MARK: - Rebuilding the text

    /// Completion appends by counting characters off the front of the match,
    /// which only works while normalising strips from the front. Trailing
    /// slashes come off the back, and that mismatch used to produce a doubled
    /// slash: typing "google.com/" finished as "google.com//search?q=x".
    func testATrailingSlashDoesNotDoubleItself() {
        let candidates = [candidate("https://google.com/search?q=x")]

        XCTAssertEqual(
            AddressCompletion.completion(for: "google.com/", in: candidates),
            "google.com/search?q=x"
        )
        XCTAssertEqual(
            AddressCompletion.completion(for: "google.com//", in: candidates),
            "google.com/search?q=x",
            "however many slashes are typed, the address has the ones it has"
        )
    }

    /// Whatever it produces has to survive the resolver it is handed to.
    func testEveryCompletionResolvesToAParseableAddress() {
        let candidates = [
            candidate("https://google.com/search?q=filme%20online"),
            candidate("https://youtube.com/watch?v=abc&t=90"),
            candidate("http://localhost:3000/admin")
        ]
        for typed in [
            "goo", "google.com/", "google.com/search",
            "you", "youtube.com/", "youtube.com/watch",
            "www.goo", "https://goo", "localhost:3"
        ] {
            guard let completed = AddressCompletion.completion(for: typed, in: candidates) else { continue }
            XCTAssertFalse(
                completed.replacingOccurrences(of: "://", with: "").contains("//"),
                "\(typed) produced a doubled slash: \(completed)"
            )
            let absolute = completed.contains("://") ? completed : "https://\(completed)"
            XCTAssertNotNil(
                WebURLPolicy.validatedURL(absolute),
                "\(typed) completed to something unopenable: \(completed)"
            )
        }
    }

    /// A query string is the whole point of a past search being in history; it
    /// has to come back exactly as it went in.
    func testAQueryStringSurvivesCompletion() {
        let candidates = [candidate("https://google.com/search?q=filme%20online&hl=en")]

        XCTAssertEqual(
            AddressCompletion.completion(for: "google.com/s", in: candidates),
            "google.com/search?q=filme%20online&hl=en"
        )
    }

    func testTypingASchemeOrWwwStillLandsOnTheRightAddress() {
        let candidates = [candidate("https://www.youtube.com/")]

        XCTAssertEqual(AddressCompletion.completion(for: "www.you", in: candidates), "www.youtube.com")
        XCTAssertEqual(AddressCompletion.completion(for: "https://you", in: candidates), "https://youtube.com")
    }

    // MARK: - Defects found by adversarial review

    /// The one that shipped and bit. Typing a whole address used to complete
    /// past it into the deepest page under that host, so "google.com" finished
    /// as an old "google.com/search?q=…" and Return opened the search.
    func testTypingAWholeAddressDoesNotRunOnIntoAPageUnderIt() {
        let history = [
            candidate("https://google.com", visits: 7),
            candidate("https://google.com/search?q=youtube", visits: 5),
            candidate("https://google.com/search?q=lucianroman", visits: 4)
        ]

        XCTAssertEqual(AddressCompletion.completion(for: "goo", in: history), "google.com")
        XCTAssertEqual(AddressCompletion.completion(for: "google.co", in: history), "google.com")
        XCTAssertNil(
            AddressCompletion.completion(for: "google.com", in: history),
            "the address is complete; finishing it further changes where Return goes"
        )
        XCTAssertNil(AddressCompletion.completion(for: "google.com/", in: history))
    }

    /// A host is case-insensitive. A path and a query are not, and folding them
    /// turns a real link into a dead one.
    func testCaseIsKeptWhereItCarriesMeaning() {
        XCTAssertEqual(
            AddressCompletion.presentable("HTTPS://WWW.YouTube.com/watch?v=dQw4w9WgXcQ"),
            "youtube.com/watch?v=dQw4w9WgXcQ",
            "the host folds, the video id does not"
        )
        XCTAssertEqual(
            AddressCompletion.presentable("https://docs.google.com/document/d/1AbCdEfG/edit"),
            "docs.google.com/document/d/1AbCdEfG/edit"
        )

        let candidates = AddressCompletion.candidates(
            history: [HistoryRecord(title: "Video", url: "https://www.YouTube.com/watch?v=dQw4w9WgXcQ")],
            bookmarks: []
        )
        XCTAssertEqual(candidates.first?.url, "youtube.com/watch?v=dQw4w9WgXcQ")

        // And a reader typing in any case still finds it.
        XCTAssertEqual(
            AddressCompletion.completion(for: "YOUTUBE.COM/W", in: candidates),
            "YOUTUBE.COM/Watch?v=dQw4w9WgXcQ"
        )
        XCTAssertEqual(
            AddressCompletion.suggestions(for: "youtube", in: candidates).first?.url,
            "youtube.com/watch?v=dQw4w9WgXcQ"
        )
    }

    /// Several words have to find a page by its name; one word already did.
    func testEveryWordTypedHasToLandForATitleToMatch() {
        let candidates = [
            titled("https://example.com/r/42", "Garlic Chilli Oil Recipe"),
            titled("https://example.com/r/7", "Garlic Bread")
        ]

        XCTAssertEqual(
            AddressCompletion.suggestions(for: "garlic chilli", in: candidates)
                .filter { $0.kind != .search }.map(\.url),
            ["example.com/r/42"],
            "both words must land, so the bread drops out"
        )
        XCTAssertEqual(
            AddressCompletion.suggestions(for: "garlic", in: candidates)
                .filter { $0.kind != .search }.count,
            2
        )
        XCTAssertEqual(
            AddressCompletion.suggestions(for: "oil garlic", in: candidates)
                .filter { $0.kind != .search }.map(\.url),
            ["example.com/r/42"],
            "word order is not a requirement"
        )
    }

    /// A phrase is still a search, whatever it matches.
    func testAPhraseAlwaysKeepsItsSearchRow() {
        let candidates = [titled("https://example.com/r/42", "Garlic Chilli Oil Recipe")]
        let rows = AddressCompletion.suggestions(for: "garlic chilli", in: candidates)

        XCTAssertTrue(rows.contains { $0.kind == .search && $0.title == "garlic chilli" })
        XCTAssertNil(
            AddressCompletion.completion(for: "garlic chilli", in: candidates),
            "a phrase is never completed inline"
        )
    }
}
