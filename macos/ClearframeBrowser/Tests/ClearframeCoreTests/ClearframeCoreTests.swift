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

    func testLocalExtractionProducesSourceLanguageResultsAcrossTestedLanguages() {
        let mediaPollution = """
        subtitles settings, opens subtitles settings dialog
        Video Player is loading. Stream Type LIVE. Playback controls.
        """
        let cases: [(language: String, title: String, text: String, expectedFragment: String)] = [
            (
                "en",
                "Community library expands evening access",
                """
                The community library will open three evenings each week so working families can visit after normal office hours.
                The pilot begins in September and includes study rooms, children's activities, and help with digital public services.
                Librarians will record attendance and ask visitors which evening programs are most useful.
                The city approved funding for six months before deciding whether the longer schedule should continue.
                Residents can submit feedback in person or through a short form on the library website.
                """,
                "community library"
            ),
            (
                "fr",
                "La bibliothèque municipale élargit ses horaires",
                """
                La bibliothèque municipale ouvrira trois soirs par semaine afin que les familles puissent venir après leur journée de travail.
                Le projet commencera en septembre avec des salles d'étude, des activités pour enfants et une aide aux démarches numériques.
                Les bibliothécaires mesureront la fréquentation et demanderont aux visiteurs quels services sont les plus utiles.
                La ville a financé une période pilote de six mois avant de décider si ces horaires doivent devenir permanents.
                Les habitants pourront transmettre leurs commentaires sur place ou au moyen d'un formulaire public.
                """,
                "bibliothèque municipale"
            ),
            (
                "zh-Hans",
                "城市图书馆延长晚间开放时间",
                """
                城市图书馆将每周增加三个晚间开放时段，方便上班家庭在工作结束后使用公共服务。
                试点计划将于九月开始，并提供自习空间、儿童活动以及数字政务咨询服务。
                图书馆工作人员会记录到访人数，并询问读者哪些晚间项目最有帮助。
                市政府已经批准六个月的试点经费，之后再决定是否长期保留新的开放时间。
                居民可以在现场提交意见，也可以通过图书馆网站上的公开表格提供反馈。
                """,
                "城市图书馆"
            )
        ]

        for testCase in cases {
            let page = PageSnapshot(
                title: testCase.title,
                url: "https://example.org/\(testCase.language)",
                hostname: "example.org",
                scheme: "https",
                language: testCase.language,
                text: mediaPollution + "\n" + testCase.text,
                wordCount: 120,
                hasPasswordField: false,
                formActions: []
            )

            let result = LocalAnalysisEngine.summarize(page: page)
            let allAnalysisText = ([result.summary] + result.keyPoints + result.claimsToCheck)
                .joined(separator: " ")

            XCTAssertFalse(result.summary.isEmpty, "\(testCase.language) needs a local gist")
            XCTAssertFalse(result.keyPoints.isEmpty, "\(testCase.language) needs local key points")
            XCTAssertTrue(
                result.summary.localizedCaseInsensitiveContains(testCase.expectedFragment),
                "\(testCase.language) should preserve the source language"
            )
            for pollutedPhrase in ["subtitles settings", "Video Player is loading", "Stream Type LIVE", "Playback controls"] {
                XCTAssertFalse(
                    allAnalysisText.localizedCaseInsensitiveContains(pollutedPhrase),
                    "Media-player UI leaked into \(testCase.language) analysis: \(pollutedPhrase)"
                )
            }
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

    func testPlainEnglishLocalSimplifierIsLimitedToEnglishSources() async throws {
        let provider = LocalPageIntelligenceProvider()
        let simplified = try await provider.translate(
            text: "Individuals utilize numerous tools.",
            sourceLanguage: "en-US",
            targetLanguage: "Plain English"
        )
        XCTAssertEqual(simplified, "people use many tools.")

        do {
            _ = try await provider.translate(
                text: "La bibliothèque municipale ouvre plus tard.",
                sourceLanguage: "fr",
                targetLanguage: "Plain English"
            )
            XCTFail("French-to-English translation must not be presented as a local simplification")
        } catch let error as PageIntelligenceError {
            XCTAssertEqual(error.localizedDescription, PageIntelligenceError.localTranslationUnavailable.localizedDescription)
        }
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

    func testLegacyFlatBookmarksMigrateToUnfiledWithoutDataLoss() throws {
        struct LegacyBookmark: Encodable {
            let id: UUID
            let title: String
            let url: String
            let createdAt: Date
        }

        let legacy = LegacyBookmark(
            id: UUID(),
            title: "Saved before folders",
            url: "https://example.com/legacy",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let encoded = try JSONEncoder().encode([legacy])
        let decoded = try JSONDecoder().decode([BookmarkRecord].self, from: encoded)
        let collection = BookmarkCollection(bookmarks: decoded)

        XCTAssertEqual(collection.bookmarks.count, 1)
        XCTAssertEqual(collection.bookmarks.first?.id, legacy.id)
        XCTAssertEqual(collection.bookmarks.first?.title, legacy.title)
        XCTAssertNil(collection.bookmarks.first?.folderID)
        XCTAssertEqual(collection.bookmarks(in: nil).first?.url, legacy.url)
    }

    func testBookmarkFolderTreeMovesAndSafeDeletionPreserveSavedPages() throws {
        var collection = BookmarkCollection()
        let programming = try XCTUnwrap(
            collection.createFolder(title: "Programming", emoji: "💻", parentID: nil)
        )
        let swift = try XCTUnwrap(
            collection.createFolder(title: "Swift", emoji: "🐦", parentID: programming.id)
        )
        let nestedBookmark = BookmarkRecord(
            title: "Swift documentation",
            url: "https://swift.org/documentation/",
            folderID: swift.id
        )
        let rootBookmark = BookmarkRecord(
            title: "Developer news",
            url: "https://example.com/news",
            folderID: programming.id
        )
        collection.addBookmark(nestedBookmark)
        collection.addBookmark(rootBookmark)

        XCTAssertEqual(collection.folders(in: programming.id).map(\.id), [swift.id])
        XCTAssertEqual(collection.bookmarks(in: swift.id).map(\.id), [nestedBookmark.id])
        XCTAssertTrue(collection.containsItems(in: programming.id))

        collection.moveBookmark(id: rootBookmark.id, to: swift.id)
        XCTAssertEqual(Set(collection.bookmarks(in: swift.id).map(\.id)), [nestedBookmark.id, rootBookmark.id])

        collection.deleteFolderPreservingContents(id: programming.id)
        XCTAssertNil(collection.folder(id: programming.id))
        XCTAssertNil(collection.folder(id: swift.id)?.parentID)
        XCTAssertEqual(collection.bookmarks.count, 2)
        XCTAssertEqual(Set(collection.bookmarks(in: swift.id).map(\.id)), [nestedBookmark.id, rootBookmark.id])
    }

    func testBookmarkCollectionNormalizesInvalidImportedReferences() {
        let missingFolderID = UUID()
        let bookmark = BookmarkRecord(
            title: "Imported page",
            url: "https://example.com/imported",
            folderID: missingFolderID
        )
        let collection = BookmarkCollection(bookmarks: [bookmark])

        XCTAssertNil(collection.bookmarks.first?.folderID)
        XCTAssertEqual(collection.bookmarks(in: nil).count, 1)
    }
}
