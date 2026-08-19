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
}
