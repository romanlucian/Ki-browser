import ClearframeCore
import Combine
import Foundation

@MainActor
protocol PageAssistantSession: AnyObject {
    var navigationVersion: Int { get }
    var currentURLString: String { get }
    func extractPage() async throws -> PageSnapshot
    func revealEvidence(_ text: String, expectedNavigationVersion: Int?) async -> Bool
}

extension BrowserSession: PageAssistantSession {}

@MainActor
final class PageAssistantModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading(String)
        case ready
        case structureNotice
        /// There is no web page in this tab to read — a start surface, or a tab
        /// whose popup has not navigated yet. A refusal, not a failure.
        case needsPage
        case failed(String)
    }

    /// Shown when Analyze page is pressed on a tab that holds no web page.
    static let needsPageMessage =
        "Open a web page in this tab, then click Analyze page. Clearframe reads only the page you are looking at, and only when you ask."
    /// Shown when the page moved between reading it and using the result.
    static let pageChangedMessage =
        "The page changed while Clearframe was reading it. Click Analyze page again to read what is on screen now."

    @Published var state: State = .idle
    @Published var snapshot: PageSnapshot?
    @Published var analysis: PageAnalysis?
    @Published var translatedSummary: String?
    @Published var savedSource: AnalyzedSource?
    @Published var comparison: SourceComparison?
    @Published var revealedEvidence: String?
    @Published var evidenceWasFoundOnPage = false
    @Published var operationMessage: String?
    @Published var operationError: String?

    private let localProvider: any PageIntelligenceProviding
    private let remoteProviderFactory: (OpenAIProviderConfiguration) -> any PageIntelligenceProviding
    private var activeTask: Task<Void, Never>?
    private var operationGeneration = 0
    private var snapshotNavigationVersion: Int?
    private var hasOverriddenStructureNotice = false

    init(
        localProvider: any PageIntelligenceProviding = LocalPageIntelligenceProvider(),
        remoteProviderFactory: @escaping (OpenAIProviderConfiguration) -> any PageIntelligenceProviding = {
            OpenAIPageIntelligenceProvider(configuration: $0)
        }
    ) {
        self.localProvider = localProvider
        self.remoteProviderFactory = remoteProviderFactory
    }

    func clearForNavigation() {
        cancelActiveOperation()
        state = .idle
        snapshot = nil
        analysis = nil
        translatedSummary = nil
        comparison = nil
        revealedEvidence = nil
        evidenceWasFoundOnPage = false
        operationMessage = nil
        operationError = nil
        snapshotNavigationVersion = nil
        hasOverriddenStructureNotice = false
    }

    func teardown() {
        cancelActiveOperation()
        state = .idle
        snapshot = nil
        analysis = nil
        translatedSummary = nil
        savedSource = nil
        comparison = nil
        revealedEvidence = nil
        evidenceWasFoundOnPage = false
        operationMessage = nil
        operationError = nil
        snapshotNavigationVersion = nil
        hasOverriddenStructureNotice = false
    }

    func analyzeCurrentPage(session: any PageAssistantSession) async {
        let generation = beginOperation()
        // A start surface, an error surface, or a popup that has not navigated
        // yet is not a web page. Reading one used to succeed and then fail the
        // identity check below, which left the panel spinning with no way back;
        // the refusal happens here instead, before any work starts.
        guard WebURLPolicy.validatedURL(session.currentURLString) != nil else {
            // Having just said there is no page to read, do not keep showing
            // what the last one said. The saved source survives: it is the
            // reader's own choice, held for a comparison.
            snapshot = nil
            analysis = nil
            translatedSummary = nil
            comparison = nil
            revealedEvidence = nil
            evidenceWasFoundOnPage = false
            snapshotNavigationVersion = nil
            state = .needsPage
            finishOperation(generation)
            return
        }
        let expectedNavigationVersion = session.navigationVersion
        state = .loading("Reading the visible page…")

        let task = Task { @MainActor [weak self, weak session] in
            guard let self else { return }
            guard let session else {
                self.resolveAbandonedWork(generation, to: .idle)
                return
            }
            do {
                try Task.checkCancellation()
                let page = try await session.extractPage()
                try Task.checkCancellation()
                // Superseded work leaves the state to whoever superseded it;
                // every other way out of here settles on a terminal state, so
                // the panel can never be left loading forever.
                guard self.isCurrent(generation) else { return }
                guard session.navigationVersion == expectedNavigationVersion else {
                    self.state = .idle
                    return
                }
                guard self.snapshotStillMatches(page, session: session) else {
                    self.state = .failed(Self.pageChangedMessage)
                    return
                }

                if LocalAnalysisEngine.assessStructure(page: page) == .listing, !self.hasOverriddenStructureNotice {
                    self.snapshot = page
                    self.snapshotNavigationVersion = expectedNavigationVersion
                    self.state = .structureNotice
                    return
                }

                let content = try await self.localProvider.analyze(page: page)
                try Task.checkCancellation()
                guard self.isCurrent(generation) else { return }
                guard session.navigationVersion == expectedNavigationVersion else {
                    self.state = .idle
                    return
                }

                self.snapshot = page
                self.snapshotNavigationVersion = expectedNavigationVersion
                self.analysis = PageAnalysis(
                    content: content,
                    risk: RiskAnalyzer.assess(page: page),
                    readingTimeMinutes: LocalAnalysisEngine.readingTime(wordCount: page.wordCount),
                    mode: .local
                )
                self.translatedSummary = nil
                self.comparison = nil
                self.revealedEvidence = nil
                self.evidenceWasFoundOnPage = false
                self.state = .ready
            } catch is CancellationError {
                // Navigation or a newer explicit action superseded this work.
            } catch {
                guard self.isCurrent(generation) else { return }
                self.state = .failed(error.localizedDescription)
            }
        }
        activeTask = task
        await task.value
        finishOperation(generation)
    }

    /// Runs the same local summarize/risk pipeline as `analyzeCurrentPage`, but on the
    /// snapshot already stored while showing `.structureNotice` — the page was already
    /// read once for the structure check, so this proceeds without extracting it again.
    func analyzeDespiteStructure(session: any PageAssistantSession) async {
        guard state == .structureNotice,
              let page = snapshot,
              let expectedNavigationVersion = snapshotNavigationVersion,
              expectedNavigationVersion == session.navigationVersion else { return }

        hasOverriddenStructureNotice = true
        let generation = beginOperation()
        state = .loading("Analyzing anyway…")

        let task = Task { @MainActor [weak self, weak session] in
            guard let self else { return }
            guard let session else {
                self.resolveAbandonedWork(generation, to: .structureNotice)
                return
            }
            do {
                try Task.checkCancellation()
                let content = try await self.localProvider.analyze(page: page)
                try Task.checkCancellation()
                guard self.isCurrent(generation) else { return }
                guard session.navigationVersion == expectedNavigationVersion else {
                    self.state = .idle
                    return
                }

                self.analysis = PageAnalysis(
                    content: content,
                    risk: RiskAnalyzer.assess(page: page),
                    readingTimeMinutes: LocalAnalysisEngine.readingTime(wordCount: page.wordCount),
                    mode: .local
                )
                self.translatedSummary = nil
                self.comparison = nil
                self.revealedEvidence = nil
                self.evidenceWasFoundOnPage = false
                self.state = .ready
            } catch is CancellationError {
                // Navigation or a newer explicit action superseded this work.
            } catch {
                guard self.isCurrent(generation) else { return }
                self.state = .failed(error.localizedDescription)
            }
        }
        activeTask = task
        await task.value
        finishOperation(generation)
    }

    func revealEvidence(for point: String, session: any PageAssistantSession) async {
        guard analysis?.mode == .local,
              let expectedNavigationVersion = snapshotNavigationVersion,
              expectedNavigationVersion == session.navigationVersion else { return }

        let generation = beginOperation()
        let task = Task { @MainActor [weak self, weak session] in
            guard let self, let session else { return }
            self.revealedEvidence = point
            let found = await session.revealEvidence(
                point,
                expectedNavigationVersion: expectedNavigationVersion
            )
            guard !Task.isCancelled,
                  self.isCurrent(generation),
                  session.navigationVersion == expectedNavigationVersion else { return }
            self.evidenceWasFoundOnPage = found
        }
        activeTask = task
        await task.value
        finishOperation(generation)
    }

    func improveWithAI(configuration: OpenAIProviderConfiguration) async {
        guard let page = snapshot, let current = analysis else { return }
        let generation = beginOperation()
        operationMessage = "Building a richer, source-grounded summary…"

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let provider = self.remoteProviderFactory(configuration)
                let content = try await provider.analyze(page: page)
                try Task.checkCancellation()
                guard self.isCurrent(generation) else { return }
                self.analysis = PageAnalysis(
                    content: content,
                    risk: current.risk,
                    readingTimeMinutes: current.readingTimeMinutes,
                    mode: .remoteAI
                )
                self.translatedSummary = nil
                self.state = .ready
            } catch is CancellationError {
                // A navigation or newer action intentionally cancelled the request.
            } catch {
                guard self.isCurrent(generation) else { return }
                self.operationError = error.localizedDescription
                self.state = .ready
            }
        }
        activeTask = task
        await task.value
        finishOperation(generation)
    }

    func translateSummary(targetLanguage: String, configuration: OpenAIProviderConfiguration?) async {
        guard let current = analysis, let page = snapshot else { return }
        let canSimplifyLocally = targetLanguage == "Plain English" &&
            LocalAnalysisEngine.canSimplifyToPlainEnglish(sourceLanguage: page.language)
        let generation = beginOperation()
        operationMessage = canSimplifyLocally ? "Simplifying locally…" : "Translating…"

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let translated: String
                if canSimplifyLocally {
                    translated = try await self.localProvider.translate(
                        text: current.content.summary,
                        sourceLanguage: page.language,
                        targetLanguage: targetLanguage
                    )
                } else {
                    guard let configuration else { throw PageIntelligenceError.localTranslationUnavailable }
                    let provider = self.remoteProviderFactory(configuration)
                    translated = try await provider.translate(
                        text: current.content.summary,
                        sourceLanguage: page.language,
                        targetLanguage: targetLanguage
                    )
                }
                try Task.checkCancellation()
                guard self.isCurrent(generation) else { return }
                self.translatedSummary = translated
                self.state = .ready
            } catch is CancellationError {
                // A navigation or newer action intentionally cancelled the request.
            } catch {
                guard self.isCurrent(generation) else { return }
                self.operationError = error.localizedDescription
                self.state = .ready
            }
        }
        activeTask = task
        await task.value
        finishOperation(generation)
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

    private func beginOperation() -> Int {
        activeTask?.cancel()
        operationGeneration &+= 1
        operationMessage = nil
        operationError = nil
        return operationGeneration
    }

    private func finishOperation(_ generation: Int) {
        guard generation == operationGeneration else { return }
        activeTask = nil
        operationMessage = nil
    }

    private func cancelActiveOperation() {
        activeTask?.cancel()
        activeTask = nil
        operationGeneration &+= 1
    }

    private func isCurrent(_ generation: Int) -> Bool {
        generation == operationGeneration && !Task.isCancelled
    }

    /// Settles work that lost the thing it was working on — the tab's session
    /// went away mid-read — onto a terminal state. Work that a newer operation
    /// superseded is left alone: that operation owns the state now.
    private func resolveAbandonedWork(_ generation: Int, to fallback: State) {
        guard isCurrent(generation) else { return }
        state = fallback
    }

    private func snapshotStillMatches(_ page: PageSnapshot, session: any PageAssistantSession) -> Bool {
        guard let pageURL = WebURLPolicy.validatedURL(page.url),
              let sessionURL = WebURLPolicy.validatedURL(session.currentURLString) else { return false }
        return pageURL.absoluteString == sessionURL.absoluteString
    }
}
