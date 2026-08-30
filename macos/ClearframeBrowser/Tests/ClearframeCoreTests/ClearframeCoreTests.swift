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
        text: "Cities are adding shaded public spaces as summer temperatures rise. A 2025 survey of 40 cities found that tree cover can make busy streets more comfortable. Planners say shade structures are faster to install, while mature trees provide broader environmental benefits. The report recommends measuring street temperature before and after each project. Residents also asked for more drinking fountains near transit stops. Maintenance crews water young trees twice a week through the first summer. The city budget sets aside money for replacing damaged shade fabric each year. Volunteers mapped every bench in the market district last autumn. Officials plan to publish the temperature readings on an open data page. An earlier pilot in 2019 covered only three streets, according to the appendix.",
        wordCount: 122,
        hasPasswordField: false,
        formActions: []
    )

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

    func testRiskIPAddressAndOriginNormalizationAvoidFalsePositives() {
        let invalidIPv4 = PageSnapshot(
            title: article.title,
            url: "https://999.999.999.999/article",
            hostname: "999.999.999.999",
            scheme: "https",
            language: "en",
            text: article.text,
            wordCount: article.wordCount,
            hasPasswordField: false,
            formActions: []
        )
        XCTAssertFalse(RiskAnalyzer.assess(page: invalidIPv4).signals.contains { $0.title.contains("raw IP") })

        let invalidIPv6 = PageSnapshot(
            title: article.title,
            url: "https://example.org/article",
            hostname: "::::",
            scheme: "https",
            language: "en",
            text: article.text,
            wordCount: article.wordCount,
            hasPasswordField: false,
            formActions: []
        )
        XCTAssertFalse(RiskAnalyzer.assess(page: invalidIPv6).signals.contains { $0.title.contains("raw IP") })

        let ipv6 = PageSnapshot(
            title: article.title,
            url: "http://[2001:db8::1]/article",
            hostname: "[2001:db8::1]",
            scheme: "http",
            language: "en",
            text: article.text,
            wordCount: article.wordCount,
            hasPasswordField: false,
            formActions: []
        )
        XCTAssertTrue(RiskAnalyzer.assess(page: ipv6).signals.contains { $0.title.contains("raw IP") })

        let defaultPort = PageSnapshot(
            title: article.title,
            url: "https://Example.org/article",
            hostname: "Example.org",
            scheme: "https",
            language: "en",
            text: article.text,
            wordCount: article.wordCount,
            hasPasswordField: false,
            formActions: ["https://example.org:443"]
        )
        XCTAssertFalse(RiskAnalyzer.assess(page: defaultPort).signals.contains { $0.title.contains("another site") })
    }

    func testReadingTimeRoundsPartialMinutesUp() {
        XCTAssertEqual(LocalAnalysisEngine.readingTime(wordCount: 1), 1)
        XCTAssertEqual(LocalAnalysisEngine.readingTime(wordCount: 220), 1)
        XCTAssertEqual(LocalAnalysisEngine.readingTime(wordCount: 221), 2)
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

    func testSessionRestoreUsesTheCredentialFreeWebURLPolicy() {
        let invalidValues = [
            "https://user:password@example.com/private",
            "https:///missing-host",
            "https:relative-path",
            "data:text/html,private",
            "about:blank"
        ]

        for value in invalidValues {
            let record = BrowserTabRecord(
                id: UUID(),
                url: value,
                title: "Unsafe restore",
                lastActivatedAt: Date()
            )
            XCTAssertNil(record.restorableURL, "Restored an unsafe URL: \(value)")
            XCTAssertNil(WebURLPolicy.validatedURL(value), "Validated an unsafe URL: \(value)")
        }
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

    func testTabGroupNormalizesItsTitleAndRejectsUnknownColors() {
        let trimmed = TabGroupRecord(title: "  Research  ", colorID: "  BLUE ")
        XCTAssertEqual(trimmed.title, "Research")
        XCTAssertEqual(trimmed.colorID, "blue", "a color is matched case- and space-insensitively")

        XCTAssertEqual(TabGroupRecord(colorID: "chartreuse").colorID, TabGroupRecord.defaultColorID)
        XCTAssertEqual(TabGroupRecord(colorID: "").colorID, TabGroupRecord.defaultColorID)
        XCTAssertEqual(TabGroupRecord.defaultColorID, TabGroupRecord.colorIDs[0])
        XCTAssertEqual(TabGroupRecord.colorIDs.count, 8)
        XCTAssertEqual(Set(TabGroupRecord.colorIDs).count, 8, "no color identifier is listed twice")
        XCTAssertEqual(TabGroupRecord(title: "   ").title, "", "a blank name is stored as no name")
    }

    func testTabGroupDecodesUnknownColorsAndMissingFieldsAsAUsableGroup() throws {
        let id = UUID()
        let json = Data("""
        {"id":"\(id.uuidString)","colorID":"neon"}
        """.utf8)

        let decoded = try JSONDecoder().decode(TabGroupRecord.self, from: json)

        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.colorID, TabGroupRecord.defaultColorID, "an unknown saved color falls back")
        XCTAssertEqual(decoded.title, "")
        XCTAssertFalse(decoded.isCollapsed)
    }

    func testWorkspaceSnapshotRoundTripsTabGroupsAndTabMembership() throws {
        let group = TabGroupRecord(title: "Research", colorID: "cyan", isCollapsed: true)
        let grouped = BrowserTabRecord(
            id: UUID(),
            url: "https://example.com/one",
            title: "One",
            lastActivatedAt: Date(),
            groupID: group.id
        )
        let loose = BrowserTabRecord(
            id: UUID(),
            url: "https://example.com/two",
            title: "Two",
            lastActivatedAt: Date()
        )
        let snapshot = BrowserWorkspaceSnapshot(
            tabs: [grouped, loose],
            selectedTabID: grouped.id,
            groups: [group]
        )

        let restored = try JSONDecoder().decode(
            BrowserWorkspaceSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )

        XCTAssertEqual(restored, snapshot)
        XCTAssertEqual(restored.groups.first?.title, "Research")
        XCTAssertEqual(restored.groups.first?.isCollapsed, true)
        XCTAssertEqual(restored.tabs.first?.groupID, group.id)
        XCTAssertNil(restored.tabs.last?.groupID)
    }

    func testLegacySavedSessionWithoutTabGroupsRestoresExactlyAsBefore() throws {
        let id = UUID()
        let legacy = Data("""
        {"tabs":[{"id":"\(id.uuidString)","url":"https://example.com/legacy","title":"Legacy","lastActivatedAt":768000000}],
         "selectedTabID":"\(id.uuidString)"}
        """.utf8)

        let restored = try JSONDecoder().decode(BrowserWorkspaceSnapshot.self, from: legacy)

        XCTAssertEqual(restored.tabs.count, 1)
        XCTAssertEqual(restored.tabs.first?.id, id)
        XCTAssertEqual(restored.tabs.first?.title, "Legacy")
        XCTAssertNil(restored.tabs.first?.groupID, "a tab saved before groups existed restores ungrouped")
        XCTAssertTrue(restored.groups.isEmpty)
        XCTAssertEqual(restored.selectedTabID, id)
        XCTAssertEqual(restored.normalized().tabs, restored.tabs, "normalization leaves a legacy session alone")
    }

    func testWorkspaceNormalizationDropsEmptyGroupsAndDanglingMemberships() {
        let now = Date()
        let keptGroup = TabGroupRecord(title: "Kept", colorID: "blue")
        let emptyGroup = TabGroupRecord(title: "Empty", colorID: "red")
        let missingGroupID = UUID()
        let tabs = [
            BrowserTabRecord(id: UUID(), url: "https://example.com/a", title: "A", lastActivatedAt: now, groupID: keptGroup.id),
            BrowserTabRecord(id: UUID(), url: "https://example.com/b", title: "B", lastActivatedAt: now, groupID: missingGroupID),
            BrowserTabRecord(id: UUID(), url: "https://example.com/c", title: "C", lastActivatedAt: now)
        ]

        let normalized = BrowserWorkspaceSnapshot(
            tabs: tabs,
            selectedTabID: tabs[1].id,
            groups: [keptGroup, emptyGroup, keptGroup]
        ).normalized()

        XCTAssertEqual(normalized.groups.map(\.id), [keptGroup.id], "an empty or repeated group is not restored")
        XCTAssertEqual(normalized.tabs[0].groupID, keptGroup.id)
        XCTAssertNil(normalized.tabs[1].groupID, "a tab pointing at a group that is gone restores ungrouped")
        XCTAssertNil(normalized.tabs[2].groupID)
        XCTAssertEqual(normalized.tabs.map(\.id), tabs.map(\.id), "tab order is untouched")
    }

    func testTrimmingASavedSessionAlsoDropsTheGroupsItTrimmedAway() {
        let now = Date()
        let oldGroup = TabGroupRecord(title: "Old", colorID: "yellow")
        let recentGroup = TabGroupRecord(title: "Recent", colorID: "green")
        let records = (0..<15).map { index in
            BrowserTabRecord(
                id: UUID(),
                url: "https://example.com/\(index)",
                title: "Page \(index)",
                lastActivatedAt: now.addingTimeInterval(TimeInterval(index)),
                groupID: index < 2 ? oldGroup.id : recentGroup.id
            )
        }

        let normalized = BrowserWorkspaceSnapshot(
            tabs: records,
            selectedTabID: records[14].id,
            groups: [oldGroup, recentGroup]
        ).normalized(maximumTabs: 12)

        XCTAssertEqual(normalized.tabs.count, 12)
        XCTAssertEqual(normalized.groups.map(\.id), [recentGroup.id])
        XCTAssertTrue(normalized.tabs.allSatisfy { $0.groupID == recentGroup.id })
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

    /// `URLComponents.queryItems` leaves `+`, `&`, and `=` literal in a value,
    /// and every engine listed here reads a literal `+` as a space — "C++
    /// tutorial" used to be sent as "C tutorial".
    func testSearchQueryPreservesCharactersEnginesWouldOtherwiseReadAsSyntax() {
        let queries = [
            "C++ tutorial",
            "a+b=c",
            "rust & wasm",
            "swift?why",
            "100% of #1"
        ]

        for engine in SearchEngine.allCases {
            for query in queries {
                guard let url = engine.searchURL(for: query) else {
                    return XCTFail("\(engine.displayName) did not create a results URL for “\(query)”")
                }
                XCTAssertFalse(
                    url.absoluteString.contains("+"),
                    "\(engine.displayName) left a literal + in “\(query)”, which reads as a space"
                )
                // The receiving engine decodes the query string; the round trip
                // must return exactly the words that were typed.
                let decoded = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first?
                    .value
                XCTAssertEqual(decoded, query, "\(engine.displayName) altered “\(query)”")
            }
        }
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

    /// The date is only allowed to move when a review actually happened, which
    /// is what this test is for: bumping it is a deliberate edit in two places,
    /// never a side effect of shipping.
    func testAIToolCatalogReleaseHasVisibleVersionAndCheckedDate() {
        XCTAssertEqual(AIToolCatalog.release.version, "2026.08.24.1")
        let components = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(secondsFromGMT: 0)!,
            from: AIToolCatalog.release.lastChecked
        )
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 24)
    }

    func testAIToolCatalogUsesBroadAccessLabelsAndSourcedTaskRecommendations() {
        XCTAssertEqual(Set(AIToolAccessLabel.allCases.map(\.rawValue)), Set(["Free to Try", "Paid Plan", "Provider Terms"]))
        XCTAssertTrue(AIToolCatalog.tools.contains(where: { $0.access == .freeToTry }))
        XCTAssertTrue(AIToolCatalog.tools.contains(where: { $0.access == .paidPlan }))

        for tool in AIToolCatalog.tools {
            XCTAssertEqual(Set(tool.recommendations.map(\.category)).count, tool.recommendations.count)
            for recommendation in tool.recommendations {
                XCTAssertTrue(tool.categories.contains(recommendation.category))
                XCTAssertFalse(recommendation.rationale.isEmpty)
                XCTAssertEqual(recommendation.officialSourceURL.scheme, "https")
                XCTAssertNotNil(recommendation.officialSourceURL.host)
                XCTAssertNil(URLComponents(url: recommendation.officialSourceURL, resolvingAgainstBaseURL: false)?.query)
            }
        }
    }

    func testAIToolCatalogRecommendationOrderingIsTaskSpecific() {
        XCTAssertEqual(AIToolCatalog.filtered(category: .askAndLearn, query: "").first?.id, "chatgpt")
        XCTAssertEqual(AIToolCatalog.filtered(category: .write, query: "").first?.id, "claude")
        XCTAssertEqual(AIToolCatalog.filtered(category: .research, query: "").first?.id, "perplexity")
        XCTAssertEqual(AIToolCatalog.filtered(category: .translate, query: "").first?.id, "deepl")
        XCTAssertEqual(AIToolCatalog.filtered(category: .code, query: "").first?.id, "deepseek")
        XCTAssertNil(AIToolCatalog.filtered(category: nil, query: "").first?.recommendation(for: nil))
    }

    func testTrackerBlockListStaysCuratedLowercasedDeduplicatedAndSorted() {
        let domains = TrackerBlockerCatalog.current.domains
        XCTAssertGreaterThanOrEqual(domains.count, 200)
        XCTAssertLessThanOrEqual(domains.count, 300)
        XCTAssertEqual(Set(domains).count, domains.count, "the list must not repeat a domain")
        XCTAssertEqual(domains, domains.sorted(), "the list must stay sorted for byte-stable output")

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        for domain in domains {
            XCTAssertEqual(domain, domain.lowercased(), "\(domain) should be lowercase")
            XCTAssertTrue(
                CharacterSet(charactersIn: domain).isSubset(of: allowed),
                "\(domain) should use plain ASCII host characters"
            )
            XCTAssertTrue(domain.contains("."), "\(domain) should be a registrable domain")
            XCTAssertFalse(domain.hasPrefix("."), "\(domain) should not start with a separator")
            XCTAssertFalse(domain.hasSuffix("."), "\(domain) should not end with a separator")
            XCTAssertFalse(domain.hasPrefix("www."), "\(domain) should be stored without a www prefix")
        }

        for excluded in ["googletagmanager.com", "connect.facebook.net"] {
            XCTAssertFalse(
                domains.contains(excluded),
                "\(excluded) is a tag or login endpoint, not an advertising or measurement endpoint"
            )
        }
        for included in ["doubleclick.net", "criteo.com", "scorecardresearch.com", "hotjar.com"] {
            XCTAssertTrue(domains.contains(included))
        }
    }

    func testTrackerBlockListReleaseHasVisibleVersionAndCheckedDate() {
        XCTAssertEqual(TrackerBlockerCatalog.release.version, "2026.08.14.1")
        XCTAssertEqual(TrackerBlockerCatalog.current.release, TrackerBlockerCatalog.release)
        let components = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(secondsFromGMT: 0)!,
            from: TrackerBlockerCatalog.release.lastChecked
        )
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 14)
    }

    func testContentRuleListSourceEmitsOneCompilableBlockRulePerDomain() throws {
        let source = ContentRuleListSource.make(domains: TrackerBlockerCatalog.current.domains)
        let rules = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(source.utf8)) as? [[String: Any]]
        )
        XCTAssertEqual(rules.count, TrackerBlockerCatalog.current.domains.count)

        for rule in rules {
            let action = try XCTUnwrap(rule["action"] as? [String: Any])
            XCTAssertEqual(action["type"] as? String, "block", "the shipped list only blocks")
            let trigger = try XCTUnwrap(rule["trigger"] as? [String: Any])
            XCTAssertEqual(trigger["load-type"] as? [String], ["third-party"])
            XCTAssertEqual(trigger["resource-type"] as? [String], TrackerBlockerCatalog.resourceTypes)
            XCTAssertNil(trigger["unless-top-url"])
            let filter = try XCTUnwrap(trigger["url-filter"] as? String)
            XCTAssertNoThrow(
                try NSRegularExpression(pattern: filter),
                "url-filter should be a valid expression: \(filter)"
            )
        }

        let doubleclickRule = try XCTUnwrap(rules.first { rule in
            let trigger = rule["trigger"] as? [String: Any]
            return (trigger?["url-filter"] as? String)?.contains("doubleclick") == true
        })
        let doubleclickTrigger = try XCTUnwrap(doubleclickRule["trigger"] as? [String: Any])
        let expression = try NSRegularExpression(
            pattern: try XCTUnwrap(doubleclickTrigger["url-filter"] as? String)
        )
        for matching in [
            "https://doubleclick.net/pixel",
            "http://ad.doubleclick.net/tag.js",
            "https://stats.g.doubleclick.net:443/collect"
        ] {
            XCTAssertEqual(expression.numberOfMatches(in: matching, range: NSRange(matching.startIndex..., in: matching)), 1, matching)
        }
        for other in ["https://notdoubleclick.net/pixel", "https://doubleclick.net.example.com/pixel"] {
            XCTAssertEqual(expression.numberOfMatches(in: other, range: NSRange(other.startIndex..., in: other)), 0, other)
        }
    }

    func testContentRuleListSourceOmitsLoadTypeWhenFirstPartyRequestsAreIncluded() throws {
        let source = ContentRuleListSource.make(
            domains: ["127.0.0.1"],
            resourceTypes: ["script"],
            thirdPartyOnly: false
        )
        let rules = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(source.utf8)) as? [[String: Any]]
        )
        let trigger = try XCTUnwrap(rules.first?["trigger"] as? [String: Any])
        XCTAssertNil(trigger["load-type"])
        XCTAssertEqual(trigger["resource-type"] as? [String], ["script"])
        XCTAssertEqual(trigger["url-filter"] as? String, "^https?://([^/:]+\\.)?127\\.0\\.0\\.1[:/]")
    }

    func testContentRuleListSourceAddsTopURLExceptionsOnlyForDisabledSites() throws {
        let source = ContentRuleListSource.make(
            domains: ["doubleclick.net"],
            exceptionHosts: ["news.example.co.uk", "example.com"]
        )
        let rules = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(source.utf8)) as? [[String: Any]]
        )
        let trigger = try XCTUnwrap(rules.first?["trigger"] as? [String: Any])
        XCTAssertEqual(
            trigger["unless-top-url"] as? [String],
            [
                "^https?://(www\\.)?example\\.com[:/]",
                "^https?://(www\\.)?news\\.example\\.co\\.uk[:/]"
            ]
        )

        let exception = try NSRegularExpression(
            pattern: try XCTUnwrap((trigger["unless-top-url"] as? [String])?.first)
        )
        for topURL in ["https://example.com/article", "https://www.example.com/article"] {
            XCTAssertEqual(
                exception.numberOfMatches(in: topURL, range: NSRange(topURL.startIndex..., in: topURL)),
                1,
                topURL
            )
        }
    }

    func testContentRuleListSourceIsByteIdenticalForEquivalentConfigurations() {
        let first = ContentRuleListSource.make(
            domains: ["criteo.com", "doubleclick.net", "adnxs.com"],
            exceptionHosts: ["example.com", "news.example.org"]
        )
        let second = ContentRuleListSource.make(
            domains: ["adnxs.com", "criteo.com", "doubleclick.net", "criteo.com"],
            exceptionHosts: ["news.example.org", "example.com", "example.com"]
        )
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(
            first,
            ContentRuleListSource.make(
                domains: ["criteo.com", "doubleclick.net", "adnxs.com"],
                exceptionHosts: ["example.com"]
            )
        )
        XCTAssertEqual(
            ContentRuleListSource.make(domains: TrackerBlockerCatalog.current.domains),
            ContentRuleListSource.make(domains: TrackerBlockerCatalog.current.domains.reversed())
        )
    }

    func testStableHashMatchesPublishedFNV1a64Vectors() {
        XCTAssertEqual(StableHash.fnv1a64(""), 0xcbf2_9ce4_8422_2325)
        XCTAssertEqual(StableHash.fnv1a64("a"), 0xaf63_dc4c_8601_ec8c)
        XCTAssertEqual(StableHash.fnv1a64("foobar"), 0x8594_4171_f739_67e8)
        XCTAssertEqual(StableHash.fnv1a64Hex("foobar"), "85944171f73967e8")
        XCTAssertEqual(StableHash.fnv1a64Hex("").count, 16)
        XCTAssertNotEqual(StableHash.fnv1a64("example.com"), StableHash.fnv1a64("example.org"))
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

    func testBookmarkURLPolicyAcceptsOnlyCredentialFreeWebLinks() throws {
        let secure = try XCTUnwrap(BookmarkURLPolicy.validatedURL("  https://example.com/guide?q=swift  "))
        let local = try XCTUnwrap(BookmarkURLPolicy.validatedURL("http://127.0.0.1:8765/test"))

        XCTAssertEqual(secure.absoluteString, "https://example.com/guide?q=swift")
        XCTAssertEqual(local.host, "127.0.0.1")
        XCTAssertNil(BookmarkURLPolicy.validatedURL("javascript:alert(1)"))
        XCTAssertNil(BookmarkURLPolicy.validatedURL("data:text/plain,secret"))
        XCTAssertNil(BookmarkURLPolicy.validatedURL("file:///Users/example/private.txt"))
        XCTAssertNil(BookmarkURLPolicy.validatedURL("https://user:password@example.com/private"))
        XCTAssertNil(BookmarkURLPolicy.validatedURL("https:///missing-host"))
        XCTAssertNil(BookmarkURLPolicy.validatedURL("example.com/no-scheme"))
    }

    func testBookmarkFolderTreeMovesAndSafeDeletionPreserveSavedPages() throws {
        var collection = BookmarkCollection()
        let programming = try XCTUnwrap(
            collection.createFolder(title: "Programming", iconID: "terminal", parentID: nil)
        )
        let swift = try XCTUnwrap(
            collection.createFolder(title: "Swift", iconID: "branch", parentID: programming.id)
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

    func testBookmarkBarQueriesSeparateTopLevelItemsFromNestedContents() throws {
        var collection = BookmarkCollection()
        let shopping = try XCTUnwrap(
            collection.createFolder(title: "Shopping", iconID: "bag", parentID: nil)
        )
        let gifts = try XCTUnwrap(
            collection.createFolder(title: "Gifts", iconID: "package", parentID: shopping.id)
        )
        let direct = BookmarkRecord(title: "Clearframe", url: "https://example.com/clearframe")
        let nested = BookmarkRecord(title: "Gift guide", url: "https://example.com/gifts", folderID: gifts.id)
        collection.addBookmark(direct)
        collection.addBookmark(nested)

        XCTAssertEqual(collection.folders(in: nil).map(\.id), [shopping.id])
        XCTAssertEqual(collection.bookmarks(in: nil).map(\.id), [direct.id])
        XCTAssertEqual(collection.folders(in: shopping.id).map(\.id), [gifts.id])
        XCTAssertEqual(collection.bookmarks(in: gifts.id).map(\.id), [nested.id])
    }

    func testAddingAnExistingBookmarkURLRehomesItWithoutDuplication() throws {
        var collection = BookmarkCollection()
        let design = try XCTUnwrap(
            collection.createFolder(title: "Web Design", iconID: "palette", parentID: nil)
        )
        let original = BookmarkRecord(title: "Reference", url: "https://example.com/reference")
        collection.addBookmark(original)

        var refiled = original
        refiled.title = "Updated Reference"
        refiled.folderID = design.id
        collection.addBookmark(refiled)

        XCTAssertEqual(collection.bookmarks.count, 1)
        XCTAssertEqual(collection.bookmarks(in: design.id).first?.id, original.id)
        XCTAssertEqual(collection.bookmarks(in: design.id).first?.title, "Updated Reference")
        XCTAssertTrue(collection.bookmarks(in: nil).isEmpty)
    }

    func testEditingABookmarkRenamesAndRepointsItWhileKeepingItsFolderAndDate() throws {
        var collection = BookmarkCollection()
        let design = try XCTUnwrap(
            collection.createFolder(title: "Web Design", iconID: "palette", parentID: nil)
        )
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let saved = BookmarkRecord(
            title: "Palette",
            url: "https://example.com/palette",
            createdAt: created,
            folderID: design.id
        )
        collection.addBookmark(saved)

        XCTAssertTrue(
            collection.updateBookmark(
                id: saved.id,
                title: "  Colour palettes  ",
                url: " https://example.com/colour-palettes "
            )
        )

        let edited = try XCTUnwrap(collection.bookmarks.first { $0.id == saved.id })
        XCTAssertEqual(collection.bookmarks.count, 1)
        XCTAssertEqual(edited.title, "Colour palettes")
        XCTAssertEqual(edited.url, "https://example.com/colour-palettes")
        XCTAssertEqual(edited.folderID, design.id, "an edit never re-files the bookmark")
        XCTAssertEqual(edited.createdAt, created, "an edit never rewrites when the page was saved")
        XCTAssertEqual(collection.bookmarks(in: design.id).map(\.id), [saved.id])
    }

    func testEditingABookmarkRefusesAnAddressClearframeWouldNotSave() throws {
        var collection = BookmarkCollection()
        let saved = BookmarkRecord(title: "Reference", url: "https://example.com/reference")
        collection.addBookmark(saved)

        for refused in [
            "javascript:alert(1)",
            "file:///Users/example/private.txt",
            "https://user:password@example.com/private",
            "example.com/no-scheme",
            "   "
        ] {
            XCTAssertFalse(
                collection.updateBookmark(id: saved.id, title: "Renamed", url: refused),
                "\(refused) is not a saveable web address"
            )
        }

        // `saved` was built before it went into the collection, which is what
        // gives a bookmark its position; comparing against what the collection
        // holds keeps this about the edit being refused.
        let stored = try XCTUnwrap(collection.bookmarks.first)
        XCTAssertEqual(stored.id, saved.id)
        XCTAssertEqual(stored.title, saved.title)
        XCTAssertEqual(stored.url, saved.url)
        XCTAssertEqual(collection.bookmarks.count, 1, "a refused edit changes nothing at all")

        XCTAssertFalse(
            collection.updateBookmark(id: UUID(), title: "Ghost", url: "https://example.com/ghost"),
            "an unknown bookmark is not silently created"
        )
        XCTAssertEqual(collection.bookmarks.count, 1)
        XCTAssertEqual(collection.bookmarks.first?.id, saved.id)
    }

    func testEditingABookmarkOntoAnAddressAlreadySavedLeavesOneRecord() throws {
        var collection = BookmarkCollection()
        let first = BookmarkRecord(title: "Docs", url: "https://swift.org/documentation/")
        let second = BookmarkRecord(title: "Duplicate", url: "https://example.com/duplicate")
        collection.addBookmark(first)
        collection.addBookmark(second)

        XCTAssertTrue(
            collection.updateBookmark(id: second.id, title: "Swift docs", url: "https://swift.org/documentation/")
        )

        XCTAssertEqual(collection.bookmarks.count, 1)
        XCTAssertEqual(collection.bookmarks.first?.id, second.id, "the edited bookmark is the one that survives")
        XCTAssertEqual(collection.bookmarks.first?.title, "Swift docs")
    }

    func testEditingABookmarkWithAnEmptyNameFallsBackToTheSiteHost() throws {
        var collection = BookmarkCollection()
        let saved = BookmarkRecord(title: "Old name", url: "https://example.com/page")
        collection.addBookmark(saved)

        XCTAssertTrue(collection.updateBookmark(id: saved.id, title: "   ", url: "https://swift.org/documentation/"))

        XCTAssertEqual(collection.bookmarks.first?.title, "swift.org")
    }

    func testBookmarkFolderBarLabelIsThePlainTitleNowThatChipsDrawTheirOwnIcon() {
        let folder = BookmarkFolderRecord(title: "Photography References", emoji: "📷")

        XCTAssertEqual(folder.barLabel, "Photography References")
        XCTAssertEqual(folder.barLabel, folder.title)
        XCTAssertFalse(folder.barLabel.contains(folder.emoji), "the icon is drawn beside the name, not inside it")
    }

    func testBookmarkDescendantCountsRollUpThroughADeepFolderChain() throws {
        var collection = BookmarkCollection()
        let top = try XCTUnwrap(collection.createFolder(title: "Top", iconID: "folder", parentID: nil))
        let middle = try XCTUnwrap(collection.createFolder(title: "Middle", iconID: "folder", parentID: top.id))
        let bottom = try XCTUnwrap(collection.createFolder(title: "Bottom", iconID: "folder", parentID: middle.id))
        collection.addBookmark(BookmarkRecord(title: "Deep", url: "https://example.com/deep", folderID: bottom.id))

        let counts = collection.descendantCounts()

        XCTAssertEqual(counts[top.id], BookmarkDescendantCounts(bookmarkCount: 1, subfolderCount: 2))
        XCTAssertEqual(counts[middle.id], BookmarkDescendantCounts(bookmarkCount: 1, subfolderCount: 1))
        XCTAssertEqual(counts[bottom.id], BookmarkDescendantCounts(bookmarkCount: 1, subfolderCount: 0))
    }

    func testBookmarkDescendantCountsAggregateEveryBranchOfATree() throws {
        var collection = BookmarkCollection()
        let work = try XCTUnwrap(collection.createFolder(title: "Work", iconID: "briefcase", parentID: nil))
        let design = try XCTUnwrap(collection.createFolder(title: "Design", iconID: "palette", parentID: work.id))
        let code = try XCTUnwrap(collection.createFolder(title: "Code", iconID: "terminal", parentID: work.id))
        let swift = try XCTUnwrap(collection.createFolder(title: "Swift", iconID: "branch", parentID: code.id))
        let personal = try XCTUnwrap(collection.createFolder(title: "Personal", iconID: "heart", parentID: nil))
        collection.addBookmark(BookmarkRecord(title: "Brief", url: "https://example.com/brief", folderID: work.id))
        collection.addBookmark(BookmarkRecord(title: "Palette", url: "https://example.com/palette", folderID: design.id))
        collection.addBookmark(BookmarkRecord(title: "Docs", url: "https://swift.org/documentation/", folderID: swift.id))
        collection.addBookmark(BookmarkRecord(title: "Unfiled", url: "https://example.com/unfiled", folderID: nil))

        let counts = collection.descendantCounts()

        XCTAssertEqual(counts[work.id], BookmarkDescendantCounts(bookmarkCount: 3, subfolderCount: 3))
        XCTAssertEqual(counts[design.id], BookmarkDescendantCounts(bookmarkCount: 1, subfolderCount: 0))
        XCTAssertEqual(counts[code.id], BookmarkDescendantCounts(bookmarkCount: 1, subfolderCount: 1))
        XCTAssertEqual(counts[swift.id], BookmarkDescendantCounts(bookmarkCount: 1, subfolderCount: 0))
        XCTAssertEqual(counts[personal.id], BookmarkDescendantCounts(bookmarkCount: 0, subfolderCount: 0))
        XCTAssertEqual(counts.count, 5, "every folder is present, and unfiled bookmarks belong to no folder")
    }

    func testBookmarkDescendantCountsReportZeroForAnEmptyFolder() throws {
        var collection = BookmarkCollection()
        let empty = try XCTUnwrap(collection.createFolder(title: "Empty", iconID: "folder", parentID: nil))
        collection.addBookmark(BookmarkRecord(title: "Elsewhere", url: "https://example.com/elsewhere", folderID: nil))

        XCTAssertEqual(collection.descendantCounts()[empty.id], BookmarkDescendantCounts())
    }

    func testBookmarkDescendantCountsCreditNestedBookmarksToEveryAncestor() throws {
        var collection = BookmarkCollection()
        let root = try XCTUnwrap(collection.createFolder(title: "Root", iconID: "folder", parentID: nil))
        let child = try XCTUnwrap(collection.createFolder(title: "Child", iconID: "folder", parentID: root.id))
        let grandchild = try XCTUnwrap(collection.createFolder(title: "Grandchild", iconID: "folder", parentID: child.id))
        collection.addBookmark(BookmarkRecord(title: "Root page", url: "https://example.com/root", folderID: root.id))
        collection.addBookmark(BookmarkRecord(title: "Child page", url: "https://example.com/child", folderID: child.id))
        collection.addBookmark(BookmarkRecord(title: "Leaf one", url: "https://example.com/leaf-1", folderID: grandchild.id))
        collection.addBookmark(BookmarkRecord(title: "Leaf two", url: "https://example.com/leaf-2", folderID: grandchild.id))

        let counts = collection.descendantCounts()

        XCTAssertEqual(counts[root.id]?.bookmarkCount, 4)
        XCTAssertEqual(counts[child.id]?.bookmarkCount, 3)
        XCTAssertEqual(counts[grandchild.id]?.bookmarkCount, 2)
        XCTAssertEqual(collection.bookmarks(in: root.id).count, 1, "direct listings stay shallow")
    }

    /// Totals alone cannot see this: a normalization that cuts *every*
    /// folder in a cycle loose keeps the same count and the same "one root
    /// subtree each" property as one that cuts only the first. The chain
    /// that survives is the difference between an imported folder tree
    /// keeping its shape and being flattened onto the bar, so it is pinned
    /// by shape here.
    func testBreakingAnImportedCycleCutsOnlyTheFirstLinkAndKeepsTheChain() {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let collection = BookmarkCollection(
            folders: [
                BookmarkFolderRecord(id: firstID, title: "First", parentID: secondID),
                BookmarkFolderRecord(id: secondID, title: "Second", parentID: thirdID),
                BookmarkFolderRecord(id: thirdID, title: "Third", parentID: firstID)
            ],
            bookmarks: []
        )

        func parent(_ id: UUID) -> UUID? { collection.folders.first { $0.id == id }?.parentID }

        XCTAssertNil(parent(firstID), "the cycle is cut at the first folder that sees it")
        XCTAssertEqual(parent(secondID), thirdID, "the rest of the chain is left intact")
        XCTAssertEqual(parent(thirdID), firstID)
        XCTAssertEqual(
            collection.folders(in: nil).count, 1,
            "one root, not three — cutting every link would flatten the whole chain onto the bar"
        )
    }

    func testBookmarkDescendantCountsTerminateForPreviouslyCyclicImportedFolders() {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        // A cycle the initializer breaks: first → second → third → first.
        let collection = BookmarkCollection(
            folders: [
                BookmarkFolderRecord(id: firstID, title: "First", parentID: secondID),
                BookmarkFolderRecord(id: secondID, title: "Second", parentID: thirdID),
                BookmarkFolderRecord(id: thirdID, title: "Third", parentID: firstID)
            ],
            bookmarks: [
                BookmarkRecord(title: "Imported", url: "https://example.com/imported", folderID: thirdID)
            ]
        )

        let counts = collection.descendantCounts()

        XCTAssertEqual(counts.count, 3, "no folder is lost when a cycle was normalized away")
        let rootIDs = collection.folders(in: nil).map(\.id)
        XCTAssertFalse(rootIDs.isEmpty, "breaking the cycle leaves at least one reachable root")
        let foldersReachedFromRoots = rootIDs.reduce(0) { $0 + (counts[$1]?.subfolderCount ?? 0) + 1 }
        XCTAssertEqual(
            foldersReachedFromRoots,
            collection.folders.count,
            "every folder belongs to exactly one root subtree after normalization"
        )
        let bookmarksReachedFromRoots = rootIDs.reduce(0) { $0 + (counts[$1]?.bookmarkCount ?? 0) }
        XCTAssertEqual(bookmarksReachedFromRoots, 1, "the single imported bookmark is counted exactly once")
        XCTAssertTrue(
            counts.values.allSatisfy { $0.bookmarkCount <= 1 && $0.subfolderCount <= 2 },
            "no folder claims more descendants than the collection holds"
        )
    }

    func testSharedContractPageStructure() throws {
        for testCase in try localAnalysisContract().structureCases {
            XCTAssertEqual(
                LocalAnalysisEngine.assessStructure(page: testCase.page),
                testCase.expected,
                testCase.id
            )
        }
    }

    func testSharedContractRiskSignals() throws {
        for testCase in try localAnalysisContract().riskCases {
            let risk = RiskAnalyzer.assess(page: testCase.page)
            XCTAssertEqual(risk.score, testCase.expected.score, "\(testCase.id): score")
            XCTAssertEqual(risk.level, testCase.expected.level, "\(testCase.id): level")
            XCTAssertEqual(risk.signals.map(\.title), testCase.expected.signalTitles, testCase.id)
        }
    }

    func testSharedContractReadingTime() throws {
        let contract = try localAnalysisContract()
        for testCase in contract.readingTimeCases {
            XCTAssertEqual(
                LocalAnalysisEngine.readingTime(wordCount: testCase.wordCount),
                testCase.expectedMinutes
            )
        }
    }

    func testLocalAnalysisContractKeepsPlayerInterfaceTextOutOfTheReadableText() throws {
        let contract = try localAnalysisContract()
        for testCase in contract.boilerplateCases {
            let text = LocalAnalysisEngine.readableText(page: testCase.page)
            XCTAssertFalse(text.isEmpty, "\(testCase.id): produced nothing to check")
            // Recognising this boilerplate must not depend on knowing the language it
            // is written in: a site that translates its player is still a site whose
            // player controls are not the article.
            for phrase in testCase.mustNotAppear {
                XCTAssertFalse(
                    text.localizedCaseInsensitiveContains(phrase),
                    "\(testCase.id): player interface text survived — \(phrase)"
                )
            }
        }
    }

    func testLocalAnalysisContractKeepsARepeatedSentenceOnce() throws {
        let contract = try localAnalysisContract()
        for testCase in contract.duplicateSentenceCases {
            let text = LocalAnalysisEngine.readableText(page: testCase.page)
            let sentence = testCase.repeatedSentence
            // A page may print the same line twice — a headline echoed in a
            // standfirst. It is one thing the page said, so it is copied once.
            XCTAssertLessThanOrEqual(
                text.components(separatedBy: sentence).count - 1, 1,
                "\(testCase.id): the readable text repeats a sentence — \(sentence)"
            )
        }
    }

    func testLocalAnalysisContractReducesAPageOfOnlyBoilerplateToNothing() throws {
        let contract = try localAnalysisContract()
        for testCase in contract.emptyAnalysisCases {
            // Empty, not a sentence of explanation: a user-facing string here would
            // be English on a page that is not, and belongs to the interface rather
            // than to the engine.
            XCTAssertEqual(
                LocalAnalysisEngine.readableText(page: testCase.page), "",
                "\(testCase.id): engine produced text of its own"
            )
        }
    }

    func testLocalAnalysisContractSplitsSentencesTheSameWayInBothRuntimes() throws {
        let contract = try localAnalysisContract()
        for testCase in contract.segmentationCases {
            XCTAssertEqual(
                LocalAnalysisEngine.splitSentences(testCase.text, language: testCase.language),
                testCase.expected,
                "\(testCase.id): split differently"
            )
        }
    }

    private func localAnalysisContract() throws -> LocalAnalysisContract {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "local-analysis-contract", withExtension: "json")
        )
        return try JSONDecoder().decode(LocalAnalysisContract.self, from: Data(contentsOf: url))
    }
}

private struct LocalAnalysisContract: Decodable {
    let structureCases: [StructureContractCase]
    let riskCases: [RiskContractCase]
    let readingTimeCases: [ReadingTimeContractCase]
    let segmentationCases: [SegmentationContractCase]
    let boilerplateCases: [BoilerplateContractCase]
    let duplicateSentenceCases: [DuplicateSentenceContractCase]
    let emptyAnalysisCases: [EmptyAnalysisContractCase]
}

private struct SegmentationContractCase: Decodable {
    let id: String
    let language: String
    let text: String
    let expected: [String]
}

private struct DuplicateSentenceContractCase: Decodable {
    let id: String
    let page: PageSnapshot
    let repeatedSentence: String
}

private struct EmptyAnalysisContractCase: Decodable {
    let id: String
    let page: PageSnapshot
}

private struct BoilerplateContractCase: Decodable {
    let id: String
    let page: PageSnapshot
    let mustNotAppear: [String]
}

private struct StructureContractCase: Decodable {
    let id: String
    let page: PageSnapshot
    let expected: PageStructure
}

private struct RiskContractCase: Decodable {
    let id: String
    let page: PageSnapshot
    let expected: RiskContractExpectation
}

private struct RiskContractExpectation: Decodable {
    let score: Int
    let level: RiskLevel
    let signalTitles: [String]
}

private struct ReadingTimeContractCase: Decodable {
    let wordCount: Int
    let expectedMinutes: Int
}

/// Bookmarks in the order somebody put them, rather than the order they
/// happened to be saved in.
final class BookmarkOrderingTests: XCTestCase {
    private func bookmark(_ title: String, minutesAgo: Int) -> BookmarkRecord {
        BookmarkRecord(
            title: title,
            url: "https://\(title.lowercased()).example",
            createdAt: Date(timeIntervalSince1970: 1_000_000 - Double(minutesAgo * 60))
        )
    }

    /// The upgrade that must not surprise anybody: records saved before
    /// positions existed keep the order they were already being shown in,
    /// which was newest first.
    func testBookmarksSavedBeforeOrderingKeepTheOrderTheyWereShownIn() {
        let collection = BookmarkCollection(bookmarks: [
            bookmark("Oldest", minutesAgo: 300),
            bookmark("Newest", minutesAgo: 1),
            bookmark("Middle", minutesAgo: 100),
        ])
        XCTAssertEqual(
            collection.bookmarks(in: nil).map(\.title),
            ["Newest", "Middle", "Oldest"]
        )
        XCTAssertTrue(
            collection.bookmarks.allSatisfy { $0.position != nil },
            "everything gains a position on load, so later sorting is not guesswork"
        )
    }

    func testABookmarkCanBeMovedAlongTheBar() {
        var collection = BookmarkCollection(bookmarks: [
            bookmark("A", minutesAgo: 1),
            bookmark("B", minutesAgo: 2),
            bookmark("C", minutesAgo: 3),
        ])
        let c = collection.bookmarks(in: nil)[2]

        collection.moveBookmark(id: c.id, toIndex: 0)

        XCTAssertEqual(collection.bookmarks(in: nil).map(\.title), ["C", "A", "B"])
    }

    func testMovingRightwardsLandsWhereItWasDropped() {
        var collection = BookmarkCollection(bookmarks: [
            bookmark("A", minutesAgo: 1),
            bookmark("B", minutesAgo: 2),
            bookmark("C", minutesAgo: 3),
        ])
        let a = collection.bookmarks(in: nil)[0]

        collection.moveBookmark(id: a.id, toIndex: 2)

        XCTAssertEqual(collection.bookmarks(in: nil).map(\.title), ["B", "C", "A"])
    }

    /// A drop past the end means the end, rather than nothing happening.
    func testAnIndexPastTheEndClampsInsteadOfFailing() {
        var collection = BookmarkCollection(bookmarks: [
            bookmark("A", minutesAgo: 1),
            bookmark("B", minutesAgo: 2),
        ])
        let a = collection.bookmarks(in: nil)[0]

        collection.moveBookmark(id: a.id, toIndex: 99)
        XCTAssertEqual(collection.bookmarks(in: nil).map(\.title), ["B", "A"])

        collection.moveBookmark(id: a.id, toIndex: -5)
        XCTAssertEqual(collection.bookmarks(in: nil).map(\.title), ["A", "B"])
    }

    func testTheOrderSurvivesBeingSavedAndLoaded() throws {
        var collection = BookmarkCollection(bookmarks: [
            bookmark("A", minutesAgo: 1),
            bookmark("B", minutesAgo: 2),
            bookmark("C", minutesAgo: 3),
        ])
        let c = collection.bookmarks(in: nil)[2]
        collection.moveBookmark(id: c.id, toIndex: 0)

        let data = try JSONEncoder().encode(collection.bookmarks)
        let decoded = BookmarkCollection(bookmarks: try JSONDecoder().decode([BookmarkRecord].self, from: data))

        XCTAssertEqual(decoded.bookmarks(in: nil).map(\.title), ["C", "A", "B"])
    }

    /// A new bookmark joins the end, the way Chrome adds one. Arriving at the
    /// front would shuffle an arrangement somebody made by hand.
    func testANewBookmarkJoinsTheEndOfItsFolder() {
        var collection = BookmarkCollection(bookmarks: [
            bookmark("A", minutesAgo: 1),
            bookmark("B", minutesAgo: 2),
        ])
        collection.addBookmark(BookmarkRecord(title: "New", url: "https://new.example"))

        XCTAssertEqual(collection.bookmarks(in: nil).map(\.title), ["A", "B", "New"])
    }

    /// Ordering is per folder: moving inside one leaves the other alone.
    func testEachFolderIsOrderedIndependently() {
        let folder = BookmarkFolderRecord(title: "Work", emoji: "📁")
        var collection = BookmarkCollection(folders: [folder], bookmarks: [
            bookmark("Loose1", minutesAgo: 1),
            bookmark("Loose2", minutesAgo: 2),
        ])
        collection.addBookmark(
            BookmarkRecord(title: "Filed1", url: "https://filed1.example", folderID: folder.id)
        )
        collection.addBookmark(
            BookmarkRecord(title: "Filed2", url: "https://filed2.example", folderID: folder.id)
        )
        let filed2 = try? XCTUnwrap(collection.bookmarks(in: folder.id).last)

        collection.moveBookmark(id: filed2!.id, toIndex: 0)

        XCTAssertEqual(collection.bookmarks(in: folder.id).map(\.title), ["Filed2", "Filed1"])
        XCTAssertEqual(collection.bookmarks(in: nil).map(\.title), ["Loose1", "Loose2"])
    }

    /// A bookmark dragged into a folder arrives at that folder's end rather
    /// than keeping a position that belonged to where it came from.
    func testMovingIntoAFolderPutsItAtThatFoldersEnd() {
        let folder = BookmarkFolderRecord(title: "Work", emoji: "📁")
        var collection = BookmarkCollection(folders: [folder], bookmarks: [
            bookmark("Loose", minutesAgo: 1),
        ])
        collection.addBookmark(
            BookmarkRecord(title: "Filed", url: "https://filed.example", folderID: folder.id)
        )
        let loose = collection.bookmarks(in: nil)[0]

        collection.moveBookmark(id: loose.id, to: folder.id)

        XCTAssertEqual(collection.bookmarks(in: folder.id).map(\.title), ["Filed", "Loose"])
        XCTAssertTrue(collection.bookmarks(in: nil).isEmpty)
    }
}

/// Folders in the order somebody put them, rather than alphabetically.
final class BookmarkFolderOrderingTests: XCTestCase {
    private func folder(_ title: String) -> BookmarkFolderRecord {
        BookmarkFolderRecord(title: title)
    }

    /// The upgrade that must not surprise anybody: folders saved before
    /// positions existed keep the order they were being shown in, by name.
    func testFoldersSavedBeforeOrderingKeepTheirAlphabeticalOrder() {
        let collection = BookmarkCollection(folders: [
            folder("Work"), folder("Art"), folder("Music"),
        ])
        XCTAssertEqual(collection.folders(in: nil).map(\.title), ["Art", "Music", "Work"])
        XCTAssertTrue(collection.folders.allSatisfy { $0.position != nil })
    }

    func testAFolderCanBeMovedAlongTheBar() {
        var collection = BookmarkCollection(folders: [
            folder("Art"), folder("Music"), folder("Work"),
        ])
        let work = collection.folders(in: nil)[2]

        collection.moveFolder(id: work.id, toIndex: 0)

        XCTAssertEqual(collection.folders(in: nil).map(\.title), ["Work", "Art", "Music"])
    }

    /// Once arranged by hand, the order stops being alphabetical and stays
    /// where it was put.
    func testAnArrangedOrderIsNotResortedByName() {
        var collection = BookmarkCollection(folders: [
            folder("Art"), folder("Music"), folder("Work"),
        ])
        let work = collection.folders(in: nil)[2]
        collection.moveFolder(id: work.id, toIndex: 0)

        let data = try? JSONEncoder().encode(collection.folders)
        let reloaded = BookmarkCollection(
            folders: (try? JSONDecoder().decode([BookmarkFolderRecord].self, from: data ?? Data())) ?? []
        )

        XCTAssertEqual(reloaded.folders(in: nil).map(\.title), ["Work", "Art", "Music"])
    }

    func testANewFolderJoinsTheEndRatherThanItsAlphabeticalPlace() {
        var collection = BookmarkCollection(folders: [folder("Art"), folder("Work")])
        _ = collection.createFolder(title: "Music", iconID: "folder", parentID: nil)

        XCTAssertEqual(collection.folders(in: nil).map(\.title), ["Art", "Work", "Music"])
    }

    func testSubfoldersAreOrderedWithinTheirOwnFolder() {
        var collection = BookmarkCollection(folders: [folder("Parent")])
        let parent = collection.folders(in: nil)[0]
        _ = collection.createFolder(title: "One", iconID: "folder", parentID: parent.id)
        _ = collection.createFolder(title: "Two", iconID: "folder", parentID: parent.id)
        let two = collection.folders(in: parent.id)[1]

        collection.moveFolder(id: two.id, toIndex: 0)

        XCTAssertEqual(collection.folders(in: parent.id).map(\.title), ["Two", "One"])
        XCTAssertEqual(collection.folders(in: nil).map(\.title), ["Parent"])
    }

    func testAnIndexPastTheEndClamps() {
        var collection = BookmarkCollection(folders: [folder("Art"), folder("Work")])
        let art = collection.folders(in: nil)[0]

        collection.moveFolder(id: art.id, toIndex: 99)

        XCTAssertEqual(collection.folders(in: nil).map(\.title), ["Work", "Art"])
    }
}
