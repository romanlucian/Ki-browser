import AppKit
import ClearframeCore
import Foundation
import WebKit
import XCTest
@testable import ClearframeBrowser

@MainActor
final class LivePageIntelligenceAuditTests: XCTestCase {
    private struct Site {
        let name: String
        let url: String
    }

    private struct Result: Codable {
        let name: String
        let requestedURL: String
        let finalURL: String
        let loaded: Bool
        let loadMilliseconds: Int
        let assistantState: String
        let title: String
        let hostname: String
        let language: String
        let extractedCharacters: Int
        let wordCount: Int
        let structure: String
        let analysisMilliseconds: Int
        let summary: String
        let keyPoints: [String]
        let claims: [String]
        let riskScore: Int?
        let riskSignals: [String]
        let evidenceFound: Bool?
        let allEvidenceVerbatim: Bool?
    }

    func testLivePageIntelligenceMatrix() async throws {
        guard ProcessInfo.processInfo.environment["CLEARFRAME_RUN_LIVE_AUDIT"] == "1" else {
            throw XCTSkip("Set CLEARFRAME_RUN_LIVE_AUDIT=1 to exercise live websites.")
        }

        let sites = [
            Site(name: "Google start/search page", url: "https://www.google.com/"),
            Site(name: "English encyclopedia article", url: "https://en.wikipedia.org/wiki/Artificial_intelligence"),
            Site(name: "Romanian encyclopedia article", url: "https://ro.wikipedia.org/wiki/Inteligen%C8%9B%C4%83_artificial%C4%83"),
            Site(name: "French encyclopedia article", url: "https://fr.wikipedia.org/wiki/Intelligence_artificielle"),
            Site(name: "Chinese encyclopedia article", url: "https://zh.wikipedia.org/wiki/%E4%BA%BA%E5%B7%A5%E6%99%BA%E8%83%BD"),
            Site(name: "Apple support guide", url: "https://support.apple.com/guide/safari/browse-privately-ibrw1069/mac"),
            Site(name: "MDN technical documentation", url: "https://developer.mozilla.org/en-US/docs/Web/HTTP/Overview"),
            Site(name: "Hacker News listing", url: "https://news.ycombinator.com/"),
            Site(name: "ZF Romanian news homepage", url: "https://www.zf.ro/"),
            Site(name: "Reuters world listing", url: "https://www.reuters.com/world/"),
            Site(name: "Apple product marketing", url: "https://www.apple.com/macbook-air/"),
            Site(name: "Reddit community listing", url: "https://www.reddit.com/r/photography/")
        ]

        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 900),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Clearframe live Page Intelligence audit"
        window.orderFront(nil)
        defer { window.close() }

        for site in sites {
            let suiteName = "clearframe.live-audit.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let session = BrowserSession(
                downloadCenter: DownloadCenter(),
                searchSettings: SearchSettingsStore(defaults: defaults),
                isPrivate: true
            )
            window.contentView = session.webView

            let loadStart = ContinuousClock.now
            session.navigate(site.url)
            let loaded = await waitUntil(timeout: 30) {
                if case .failed = session.loadState { return true }
                return session.hasCommittedNavigation && !session.isLoading
            }
            let loadMilliseconds = milliseconds(since: loadStart)
            try? await Task.sleep(for: .milliseconds(900))

            let analysisStart = ContinuousClock.now
            let assistant = PageAssistantModel()
            await assistant.analyzeCurrentPage(session: session)
            let initiallyDetectedListing = assistant.state == .structureNotice
            if initiallyDetectedListing {
                await assistant.analyzeDespiteStructure(session: session)
            }
            let analysisMilliseconds = milliseconds(since: analysisStart)

            let snapshot = assistant.snapshot
            let analysis = assistant.analysis
            var evidenceFound: Bool?
            if let point = analysis?.content.keyPoints.first {
                await assistant.revealEvidence(for: point, session: session)
                evidenceFound = assistant.evidenceWasFoundOnPage
            }
            let verbatimItems = (analysis?.content.keyPoints ?? []) + (analysis?.content.claimsToCheck ?? [])
            let allEvidenceVerbatim = snapshot.map { page in
                verbatimItems.allSatisfy { page.text.contains($0) }
            }

            let result = Result(
                name: site.name,
                requestedURL: site.url,
                finalURL: session.currentURLString,
                loaded: loaded && session.hasCommittedNavigation,
                loadMilliseconds: loadMilliseconds,
                assistantState: stateLabel(assistant.state),
                title: snapshot?.title ?? session.pageTitle,
                hostname: snapshot?.hostname ?? URL(string: session.currentURLString)?.host ?? "",
                language: snapshot?.language ?? "",
                extractedCharacters: snapshot?.text.count ?? 0,
                wordCount: snapshot?.wordCount ?? 0,
                structure: initiallyDetectedListing ? "listing" : (snapshot.map { LocalAnalysisEngine.assessStructure(page: $0).rawValue } ?? "unknown"),
                analysisMilliseconds: analysisMilliseconds,
                summary: analysis?.content.summary ?? "",
                keyPoints: analysis?.content.keyPoints ?? [],
                claims: analysis?.content.claimsToCheck ?? [],
                riskScore: analysis?.risk.score,
                riskSignals: analysis?.risk.signals.map(\.title) ?? [],
                evidenceFound: evidenceFound,
                allEvidenceVerbatim: allEvidenceVerbatim
            )
            let data = try JSONEncoder().encode(result)
            print("CLEARFRAME_LIVE_AUDIT \(String(decoding: data, as: UTF8.self))")

            assistant.teardown()
            session.teardown()
            window.contentView = nil
        }
    }

    private func waitUntil(
        timeout: TimeInterval,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return condition()
    }

    private func milliseconds(since start: ContinuousClock.Instant) -> Int {
        let duration = start.duration(to: .now)
        return Int(duration.components.seconds * 1_000) + Int(duration.components.attoseconds / 1_000_000_000_000_000)
    }

    private func stateLabel(_ state: PageAssistantModel.State) -> String {
        switch state {
        case .idle: return "idle"
        case .loading(let message): return "loading: \(message)"
        case .ready: return "ready"
        case .structureNotice: return "structure notice"
        case .needsPage: return "needs page"
        case .failed(let message): return "failed: \(message)"
        }
    }
}
