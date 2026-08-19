import Combine
import Foundation
@preconcurrency import WebKit

/// Find in page for one tab (⌘F, ⌘G, ⇧⌘G).
///
/// WebKit's `find(_:configuration:)` answers a single question — was a match
/// found — and nothing else. There is no index and no total, so this model
/// carries exactly that outcome and the bar above it says "No results" or says
/// nothing. Never present a position or a count here; the browser does not
/// have one to present.
@MainActor
final class PageFindController: ObservableObject {
    enum Outcome: Equatable {
        /// Nothing has been searched for on the page currently loaded.
        case idle
        case matched
        case noResults
    }

    @Published var query = ""
    @Published private(set) var isPresented = false
    @Published private(set) var outcome: Outcome = .idle
    /// Bumped whenever the bar should take the keyboard. The bar owns its own
    /// `FocusState`; nothing here touches the address field's focus wiring.
    @Published private(set) var focusRequest = 0

    private weak var webView: WKWebView?
    private var searchTask: Task<Void, Never>?

    init(webView: WKWebView?) {
        self.webView = webView
    }

    /// ⌘F. Pressing it again while the bar is open re-focuses the field, which
    /// is what a second ⌘F is for.
    func present() {
        isPresented = true
        focusRequest += 1
    }

    /// Escape and the bar's close button: hide the bar and drop the highlight.
    /// The query survives so ⌘G still steps through the same text afterwards.
    func close() {
        isPresented = false
        outcome = .idle
        searchTask?.cancel()
        searchTask = Task { [weak self] in await self?.clearSelection() }
    }

    /// Each edit restarts at the top of the document, so the bar always lands
    /// on the first match of what has been typed instead of skipping forward
    /// from wherever the previous keystroke left the selection.
    func queryChanged() {
        guard !query.isEmpty else {
            outcome = .idle
            searchTask?.cancel()
            searchTask = Task { [weak self] in await self?.clearSelection() }
            return
        }
        startSearch(backwards: false, fromTop: true)
    }

    /// ⌘G, ⇧⌘G, and the bar's previous/next buttons. With nothing to look for
    /// yet, the shortcut simply opens the bar.
    func step(backwards: Bool) {
        guard !query.isEmpty else {
            present()
            return
        }
        isPresented = true
        startSearch(backwards: backwards, fromTop: false)
    }

    /// A result describes the page it was found on. Once that page is replaced
    /// it is no longer true, so it is dropped rather than left on screen.
    func resetForNavigation() {
        searchTask?.cancel()
        searchTask = nil
        outcome = .idle
    }

    /// The one place a find actually runs. It returns the outcome it publishes
    /// so a test can await the answer instead of polling for it.
    @discardableResult
    func search(backwards: Bool, fromTop: Bool) async -> Outcome {
        guard let webView, !query.isEmpty else {
            outcome = .idle
            return .idle
        }
        if fromTop { await clearSelection() }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        guard let result = try? await webView.find(query, configuration: configuration) else {
            // WebKit could not run the search — the page went away underneath
            // it. That is not the same as finding nothing, so the bar says
            // nothing rather than claiming "No results".
            outcome = .idle
            return .idle
        }
        let resolved: Outcome = result.matchFound ? .matched : .noResults
        outcome = resolved
        return resolved
    }

    func teardown() {
        searchTask?.cancel()
        searchTask = nil
        webView = nil
        isPresented = false
        outcome = .idle
    }

    private func startSearch(backwards: Bool, fromTop: Bool) {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            _ = await self?.search(backwards: backwards, fromTop: fromTop)
        }
    }

    /// WebKit shows a match by selecting it, so dropping the selection is what
    /// clears the highlight — and it is also what makes the next search start
    /// from the top of the document.
    private func clearSelection() async {
        guard let webView else { return }
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript("window.getSelection().removeAllRanges()") { _, _ in
                continuation.resume()
            }
        }
    }
}
