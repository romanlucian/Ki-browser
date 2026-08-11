import ClearframeCore
import Combine
import Foundation

@MainActor
final class PageAssistantModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading(String)
        case ready
        case failed(String)
    }

    @Published var state: State = .idle
    @Published var snapshot: PageSnapshot?
    @Published var analysis: PageAnalysis?
    @Published var translatedSummary: String?
    @Published var savedSource: AnalyzedSource?
    @Published var comparison: SourceComparison?

    private let localProvider = LocalPageIntelligenceProvider()

    func clearForNavigation() {
        state = .idle
        snapshot = nil
        analysis = nil
        translatedSummary = nil
        comparison = nil
    }

    func analyzeCurrentPage(session: BrowserSession) async {
        state = .loading("Reading the visible page…")
        do {
            let page = try await session.extractPage()
            let content = try await localProvider.analyze(page: page)
            snapshot = page
            analysis = PageAnalysis(
                content: content,
                risk: RiskAnalyzer.assess(page: page),
                readingTimeMinutes: LocalAnalysisEngine.readingTime(wordCount: page.wordCount),
                mode: .local
            )
            translatedSummary = nil
            comparison = nil
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func improveWithAI(configuration: OpenAIProviderConfiguration) async {
        guard let page = snapshot, let current = analysis else { return }
        state = .loading("Building a richer, source-grounded summary…")
        do {
            let provider = OpenAIPageIntelligenceProvider(configuration: configuration)
            let content = try await provider.analyze(page: page)
            analysis = PageAnalysis(
                content: content,
                risk: current.risk,
                readingTimeMinutes: current.readingTimeMinutes,
                mode: .remoteAI
            )
            translatedSummary = nil
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func translateSummary(targetLanguage: String, configuration: OpenAIProviderConfiguration?) async {
        guard let current = analysis, let page = snapshot else { return }
        state = .loading(targetLanguage == "Plain English" ? "Simplifying locally…" : "Translating…")
        do {
            if targetLanguage == "Plain English" {
                translatedSummary = try await localProvider.translate(
                    text: current.content.summary,
                    sourceLanguage: page.language,
                    targetLanguage: targetLanguage
                )
            } else {
                guard let configuration else { throw PageIntelligenceError.localTranslationUnavailable }
                let provider = OpenAIPageIntelligenceProvider(configuration: configuration)
                translatedSummary = try await provider.translate(
                    text: current.content.summary,
                    sourceLanguage: page.language,
                    targetLanguage: targetLanguage
                )
            }
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func saveOrCompare() {
        guard let snapshot, let analysis else { return }
        let current = AnalyzedSource(snapshot: snapshot, analysis: analysis)
        if let savedSource, savedSource.url != current.url {
            comparison = SourceComparisonEngine.compare(savedSource, current)
        } else {
            savedSource = current
            comparison = nil
        }
    }

    func clearSavedSource() {
        savedSource = nil
        comparison = nil
    }
}
