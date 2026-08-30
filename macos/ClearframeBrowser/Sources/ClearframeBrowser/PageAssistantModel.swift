import ClearframeCore
import Combine
import Foundation

@MainActor
protocol PageAssistantSession: AnyObject {
    var navigationVersion: Int { get }
    var currentURLString: String { get }
    func extractPage() async throws -> PageSnapshot
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
    /// The page's readable text, with interface noise removed — what Copy for AI
    /// puts on the clipboard. Computed once per analysis rather than per redraw.
    @Published private(set) var readableText: String = ""
    @Published var operationMessage: String?
    @Published var operationError: String?

    private var activeTask: Task<Void, Never>?
    private var operationGeneration = 0
    private var snapshotNavigationVersion: Int?
    private var hasOverriddenStructureNotice = false

    func clearForNavigation() {
        cancelActiveOperation()
        state = .idle
        snapshot = nil
        analysis = nil
        readableText = ""
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
        readableText = ""
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
            // what the last one said.
            snapshot = nil
            analysis = nil
            readableText = ""
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

                self.snapshot = page
                self.snapshotNavigationVersion = expectedNavigationVersion
                self.analysis = PageAnalysis(
                    risk: RiskAnalyzer.assess(page: page),
                    readingTimeMinutes: LocalAnalysisEngine.readingTime(wordCount: page.wordCount)
                )
                self.readableText = LocalAnalysisEngine.readableText(page: page)
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
                try Task.checkCancellation()
                guard self.isCurrent(generation) else { return }
                guard session.navigationVersion == expectedNavigationVersion else {
                    self.state = .idle
                    return
                }

                self.analysis = PageAnalysis(
                    risk: RiskAnalyzer.assess(page: page),
                    readingTimeMinutes: LocalAnalysisEngine.readingTime(wordCount: page.wordCount)
                )
                self.readableText = LocalAnalysisEngine.readableText(page: page)
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
