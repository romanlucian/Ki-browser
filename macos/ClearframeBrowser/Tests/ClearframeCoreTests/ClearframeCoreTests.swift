import Foundation
import XCTest
@testable import ClearframeCore

final class ClearframeCoreTests: XCTestCase {
    private let article = PageSnapshot(
        title: "Cities expand shaded public spaces",
        url: "https://example.org/cities",
        hostname: "example.org",
        scheme: "https",
        language: "en",
        text: "Cities are adding shaded public spaces as summer temperatures rise. A 2025 survey of 40 cities found that tree cover can make busy streets more comfortable. Planners say shade structures are faster to install, while mature trees provide broader environmental benefits. The report recommends measuring street temperature before and after each project. Residents also asked for more drinking fountains near transit stops.",
        wordCount: 61,
        hasPasswordField: false,
        formActions: []
    )

    func testLocalSummaryIsGroundedAndFindsClaims() {
        let result = LocalAnalysisEngine.summarize(page: article)
        XCTAssertGreaterThan(result.summary.count, 80)
        XCTAssertFalse(result.keyPoints.isEmpty)
        XCTAssertTrue(result.claimsToCheck.contains { $0.contains("2025") })
    }

    func testRomanianSummaryIgnoresRepeatedMediaControlBoilerplate() {
        let repeatedPlayerText = Array(
            repeating: "subtitles settings, opens subtitles settings dialog ",
            count: 8
        ).joined() + "Video Player is loading. Stream Type LIVE. Playback controls. "
        let romanianText = """
        Bursa de Valori București a deschis ședința de tranzacționare cu un nou maxim al indicelui principal. Investitorul Corneliu Manole a discutat despre evoluția pieței și companiile urmărite în portofoliu. România continuă să atragă centre de tehnologie și servicii ale unor grupuri internaționale. Companiile au anunțat zece proiecte majore în ultimul an, potrivit informațiilor publicate de Ziarul Financiar. Evoluția dobânzilor și rezultatele trimestriale rămân importante pentru investitori.
        """
        let page = PageSnapshot(
            title: "Ziarul Financiar - știri economice",
            url: "https://www.zf.ro/",
            hostname: "www.zf.ro",
            scheme: "https",
            language: "ro",
            text: repeatedPlayerText + romanianText,
            wordCount: 126,
            hasPasswordField: false,
            formActions: []
        )

        let result = LocalAnalysisEngine.summarize(page: page)

        XCTAssertGreaterThan(result.summary.count, 120)
        XCTAssertTrue(result.summary.contains("Bursa de Valori București"))
        let allAnalysisText = ([result.summary] + result.keyPoints + result.claimsToCheck)
            .joined(separator: " ")
        for pollutedPhrase in [
            "subtitles settings",
            "Video Player is loading",
            "Stream Type LIVE",
            "Playback controls"
        ] {
            XCTAssertFalse(
                allAnalysisText.localizedCaseInsensitiveContains(pollutedPhrase),
                "Media-player UI leaked into local analysis: \(pollutedPhrase)"
            )
        }
    }

    func testSingleMediaPhraseInLegitimateArticleTextIsPreserved() {
        let page = PageSnapshot(
            title: "Troubleshooting a training video",
            url: "https://example.org/troubleshooting",
            hostname: "example.org",
            scheme: "https",
            language: "en",
            text: "The support guide explains why a video player is loading slowly on older computers. Readers should verify the connection before changing browser settings. The guide also recommends testing the same lesson on a second network. These steps preserve the original course progress and do not require sharing private information.",
            wordCount: 48,
            hasPasswordField: false,
            formActions: []
        )

        let result = LocalAnalysisEngine.summarize(page: page)
        XCTAssertTrue(result.summary.localizedCaseInsensitiveContains("video player is loading"))
    }

    func testOrdinaryHTTPSArticleHasLowSignals() {
        let result = RiskAnalyzer.assess(page: article)
        XCTAssertEqual(result.level, .low)
        XCTAssertEqual(result.score, 0)
    }

    func testSecretRequestAndPasswordRaiseRisk() {
        let risky = PageSnapshot(
            title: article.title,
            url: "http://192.168.1.8/login",
            hostname: "192.168.1.8",
            scheme: "http",
            language: "en",
            text: "Act immediately. Send your recovery phrase to restore the account.",
            wordCount: 10,
            hasPasswordField: true,
            formActions: []
        )
        let result = RiskAnalyzer.assess(page: risky)
        XCTAssertEqual(result.level, .high)
        XCTAssertGreaterThanOrEqual(result.score, 80)
    }

    func testPlainEnglishRewritesFormalWords() {
        XCTAssertEqual(LocalAnalysisEngine.simplifyEnglish("Individuals utilize numerous tools."), "people use many tools.")
    }

    func testComparisonDoesNotClaimAgreement() {
        let analysis = PageAnalysis(
            content: LocalAnalysisEngine.summarize(page: article),
            risk: RiskAnalyzer.assess(page: article),
            readingTimeMinutes: 1,
            mode: .local
        )
        let first = AnalyzedSource(snapshot: article, analysis: analysis)
        let secondPage = PageSnapshot(
            title: "Shade plans at transit stops",
            url: "https://second.example/shade",
            hostname: "second.example",
            scheme: "https",
            language: "en",
            text: article.text,
            wordCount: article.wordCount,
            hasPasswordField: false,
            formActions: []
        )
        let second = AnalyzedSource(snapshot: secondPage, analysis: analysis)
        let comparison = SourceComparisonEngine.compare(first, second)
        XCTAssertGreaterThan(comparison.overlapPercent, 0)
        XCTAssertTrue(comparison.note.contains("not factual agreement"))
    }

    func testSessionRestoreRejectsNonWebURLs() {
        let record = BrowserTabRecord(
            id: UUID(),
            url: "file:///Users/example/private.txt",
            title: "Private file",
            lastActivatedAt: Date()
        )

        XCTAssertNil(record.restorableURL)
    }

    func testSessionRestoreCapsTabsAndKeepsAValidSelection() {
        let now = Date()
        let records = (0..<15).map { index in
            BrowserTabRecord(
                id: UUID(),
                url: "https://example.com/\(index)",
                title: "Page \(index)",
                lastActivatedAt: now.addingTimeInterval(TimeInterval(index))
            )
        }
        let snapshot = BrowserWorkspaceSnapshot(tabs: records, selectedTabID: records[14].id)
            .normalized(maximumTabs: 12)

        XCTAssertEqual(snapshot.tabs.count, 12)
        XCTAssertEqual(snapshot.selectedTabID, records[14].id)
        XCTAssertFalse(snapshot.tabs.contains(where: { $0.id == records[0].id }))
    }

    func testEverySearchEngineBuildsAnHTTPSResultsURL() {
        let query = "clearframe privacy & sources"

        for engine in SearchEngine.allCases {
            guard let url = engine.searchURL(for: query),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return XCTFail("\(engine.displayName) did not create a results URL")
            }

            XCTAssertEqual(components.scheme, "https")
            XCTAssertEqual(components.host, engine.resultsHost)
            XCTAssertEqual(components.queryItems?.first?.value, query)
        }
    }

    func testSearchEngineRejectsAnEmptyQuery() {
        XCTAssertNil(SearchEngine.google.searchURL(for: "  \n "))
    }

    func testAIToolCatalogUsesSafeOfficialWebLinksAndUniqueIDs() {
        XCTAssertEqual(Set(AIToolCatalog.tools.map(\.id)).count, AIToolCatalog.tools.count)
        XCTAssertGreaterThanOrEqual(AIToolCatalog.tools.count, 12)

        for tool in AIToolCatalog.tools {
            XCTAssertEqual(tool.officialURL.scheme, "https", "\(tool.name) should use HTTPS")
            XCTAssertNotNil(tool.officialURL.host, "\(tool.name) should have a web host")
            let components = URLComponents(url: tool.officialURL, resolvingAgainstBaseURL: false)
            XCTAssertNil(components?.query, "\(tool.name) should not include tracking or affiliate query parameters")
            XCTAssertFalse(tool.categories.isEmpty, "\(tool.name) should appear in a task category")
        }
    }

    func testAIToolCatalogCoversEveryTaskAndFiltersLocally() {
        for category in AIToolCategory.allCases {
            let matches = AIToolCatalog.filtered(category: category, query: "")
            XCTAssertGreaterThanOrEqual(matches.count, 3, "\(category.rawValue) needs a useful curated selection")
            XCTAssertLessThanOrEqual(matches.count, 6, "\(category.rawValue) should stay focused")
        }

        let translationMatches = AIToolCatalog.filtered(category: nil, query: "translation")
        XCTAssertTrue(translationMatches.contains(where: { $0.id == "deepl" }))
        XCTAssertTrue(AIToolCatalog.filtered(category: .code, query: "technical").contains(where: { $0.id == "deepseek" }))
        XCTAssertTrue(AIToolCatalog.filtered(category: .createVideos, query: "unmatched phrase").isEmpty)
        XCTAssertTrue(AIToolCatalog.filtered(category: .createImages, query: "Nano Banana").contains(where: { $0.id == "gemini" }))

        let videoTools = AIToolCatalog.filtered(category: .createVideos, query: "")
        XCTAssertTrue(videoTools.contains(where: { $0.id == "veo" && $0.officialURL.host == "labs.google" }))
        XCTAssertTrue(videoTools.contains(where: { $0.id == "seedance" && $0.officialURL.host == "seed.bytedance.com" }))
    }

    func testOnboardingCompletionPersistsLocallyAndCanReset() throws {
        let suiteName = "clearframe.onboarding.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = OnboardingPreferences(defaults: defaults)
        XCTAssertFalse(preferences.hasCompletedIntroduction)

        preferences.markIntroductionCompleted()
        XCTAssertTrue(OnboardingPreferences(defaults: defaults).hasCompletedIntroduction)

        preferences.resetIntroduction()
        XCTAssertFalse(OnboardingPreferences(defaults: defaults).hasCompletedIntroduction)
    }
}
