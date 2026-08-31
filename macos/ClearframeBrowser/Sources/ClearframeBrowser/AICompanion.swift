import ClearframeCore
import Combine
import Foundation
import WebKit

/// The AI sitting beside the page.
///
/// One per **window**, not per tab. A conversation is something a person keeps
/// while they read around it: making it per-tab would mean a fresh ChatGPT every
/// time they opened a link, and a thread that vanished when they went to check
/// something.
///
/// It is an ordinary web view showing an ordinary website, signed in with the
/// person's own account. Clearframe sends it nothing: text reaches it the way it
/// reaches any site, by the person pasting it. That boundary is not a
/// preference — scripting a provider's page would be automated access to a
/// service Clearframe has no agreement with, which their consumer terms forbid.
@MainActor
final class AICompanion: ObservableObject {
    /// The assistants worth putting beside a page: the ones the catalog files
    /// under Ask & Learn, which is where the conversational tools live. Today
    /// that is ChatGPT, Claude, Gemini, Le Chat and Grok.
    static var choices: [AIToolListing] {
        AIToolCatalog.tools.filter { $0.categories.contains(.askAndLearn) }
    }

    /// How many assistants stay loaded at once.
    ///
    /// Two, because hiding a web view does not give its memory back: WebKit
    /// holds a "recently visible" claim on it for four minutes, and suspending a
    /// page pauses it rather than discarding it. Without a cap, trying every
    /// assistant would leave every assistant running. Two is what "flip between
    /// the two I am using" needs, and it is also exactly what Compare shows.
    static let maximumLiveSessions = 2

    @Published private(set) var isVisible = false
    /// Filling the window rather than sharing it with the page.
    @Published private(set) var isExpanded = false
    /// Whether this window is wide enough to show a page and the assistant at
    /// once. The view measures it; the model needs it to know whether stepping
    /// out of a page's way means shrinking or leaving.
    @Published private(set) var canShareWindow = true
    /// The assistant on the left, and the one Compare puts on the right.
    @Published private(set) var tool: AIToolListing
    @Published private(set) var comparisonTool: AIToolListing?

    /// Loaded assistants, keyed by tool. Never larger than `maximumLiveSessions`.
    @Published private(set) var live: [String: BrowserSession] = [:]
    /// Most recently used first. Decides what is dropped when a third arrives.
    private var recency: [String] = []
    /// Where a dropped assistant's conversation was, so returning reopens it
    /// rather than starting over. The conversation itself lives in the person's
    /// account on the provider's side; this is only the address of it.
    private var parked: [String: URL] = [:]

    private let makeSession: (AIToolListing, URL) -> BrowserSession
    private let rememberChoice: (String) -> Void
    /// Compare takes over the window; leaving it should give back the layout the
    /// person had, not leave them in a full-window assistant they never chose.
    private var wasExpandedBeforeComparing = false
    /// Set only when the assistant left the screen because there was no room
    /// for it, so widening the window brings it back. Closing it by hand must
    /// never set this: a window someone widens should not resurrect a panel
    /// they deliberately shut.
    private var hiddenBecauseThereWasNoRoom = false

    var isComparing: Bool { comparisonTool != nil }

    /// The assistants currently on screen, which are never dropped.
    private var shown: [String] {
        [tool.id, comparisonTool?.id].compactMap { $0 }
    }

    init(
        tool: AIToolListing,
        makeSession: @escaping (AIToolListing, URL) -> BrowserSession,
        rememberChoice: @escaping (String) -> Void
    ) {
        self.tool = tool
        self.makeSession = makeSession
        self.rememberChoice = rememberChoice
    }

    func session(for tool: AIToolListing) -> BrowserSession? { live[tool.id] }

    /// The assistant on the left, which is the only one there is unless the
    /// person asked to compare.
    var session: BrowserSession? { live[tool.id] }

    // MARK: - Showing

    func toggle() { isVisible ? hide() : show() }

    func show() {
        load(tool)
        hiddenBecauseThereWasNoRoom = false
        isVisible = true
    }

    /// Closed by the person. Deliberate, so widening the window later must not
    /// bring it back.
    func hide() {
        hiddenBecauseThereWasNoRoom = false
        isVisible = false
    }

    /// The view reporting how much room this window has.
    func setCanShareWindow(_ canShare: Bool) {
        guard canShare != canShareWindow else { return }
        canShareWindow = canShare
        // Room again for the assistant that only left because there was none.
        if canShare, hiddenBecauseThereWasNoRoom { show() }
    }

    func toggleExpanded() { isExpanded.toggle() }

    // MARK: - Choosing

    func select(_ choice: AIToolListing) {
        guard choice.id != tool.id, choice.id != comparisonTool?.id else { return }
        tool = choice
        rememberChoice(choice.id)
        if isVisible { load(choice) }
    }

    func selectComparison(_ choice: AIToolListing) {
        guard choice.id != tool.id, choice.id != comparisonTool?.id else { return }
        comparisonTool = choice
        load(choice)
    }

    // MARK: - Comparing

    /// Two assistants, side by side, for asking the same thing twice and reading
    /// the difference. Fills the window, because two columns and a page do not
    /// fit on a laptop — and the page is not what you are looking at here.
    func startComparing() {
        guard comparisonTool == nil else { return }
        // Whichever assistant they were last talking to, if it is still loaded:
        // Compare then reopens that conversation rather than a blank one.
        let recent = recency.first { $0 != tool.id }
        guard let second = Self.choices.first(where: { $0.id == recent })
            ?? Self.choices.first(where: { $0.id != tool.id }) else { return }
        wasExpandedBeforeComparing = isExpanded
        comparisonTool = second
        isExpanded = true
        show()
        load(second)
    }

    /// Closes one column.
    ///
    /// Every close button means the same thing — this column — and the last one
    /// closes the panel. There is deliberately no separate "close everything"
    /// button here: that control is about the window, not about a column, and
    /// it already lives in the toolbar (⇧⌘A). Two identical glyphs a thousand
    /// points apart doing different amounts of damage is how somebody loses a
    /// conversation they meant to keep.
    func closeColumn(_ closing: AIToolListing) {
        guard let second = comparisonTool else {
            hide()
            return
        }
        if closing.id != second.id {
            // Closing the left column leaves the right one, which becomes the
            // assistant. Its session is already loaded, so nothing reloads and
            // the conversation carries straight over.
            tool = second
            rememberChoice(second.id)
        }
        stopComparing()
    }

    func stopComparing() {
        guard comparisonTool != nil else { return }
        comparisonTool = nil
        isExpanded = wasExpandedBeforeComparing
        // The assistant that stayed **on screen** ranks above the one that left
        // it. Comparing loads the partner second, which otherwise leaves the
        // partner ranked highest and makes the next switch discard the one the
        // person still had in front of them. Screen position, not reading:
        // Clearframe does not know what anybody read.
        touch(tool.id)
        // The one that left is now the most recent hidden assistant, so coming
        // straight back to it costs nothing.
        evictBeyondLimit()
    }

    /// Steps out of a page's way.
    ///
    /// Opening a tab is a request to look at something, and a full-window
    /// assistant answers it with a page nobody can see. Comparing ends and the
    /// panel returns to the side of the window. Both conversations stay loaded,
    /// so nothing reloads and nothing is lost — only the layout changes.
    func makeRoomForPage() {
        guard isVisible else { return }
        stopComparing()
        guard canShareWindow else {
            // No layout shows both, so shrinking would reveal nothing. Sliding
            // away is the only thing that uncovers the page. The toolbar button
            // is the way back — it is already on screen, unlike a shortcut —
            // and widening the window brings it back by itself, so this reads
            // as "no room" rather than "closed".
            isVisible = false
            hiddenBecauseThereWasNoRoom = true
            return
        }
        isExpanded = false
    }

    func teardown() {
        live.values.forEach { $0.teardown() }
        live = [:]
        recency = []
        isVisible = false
    }

    // MARK: - Keeping two

    /// Makes `choice` the most recently used, loading it if it is not already,
    /// then drops whatever falls off the end.
    private func touch(_ id: String) {
        recency.removeAll { $0 == id }
        recency.insert(id, at: 0)
    }

    private func load(_ choice: AIToolListing) {
        touch(choice.id)
        if live[choice.id] == nil {
            live[choice.id] = makeSession(choice, parked[choice.id] ?? choice.officialURL)
            parked[choice.id] = nil
        }
        evictBeyondLimit()
    }

    private func evictBeyondLimit() {
        let shownNow = shown
        // Oldest first, and never one the person is looking at.
        let candidates = recency.reversed().filter { !shownNow.contains($0) }
        for id in candidates where live.count > Self.maximumLiveSessions {
            guard let session = live[id] else { continue }
            // Remember where the conversation was. ChatGPT, Claude and Gemini all
            // keep chats in the account, so reopening this address brings the
            // thread back. An unsent draft and a temporary chat are the two things
            // that genuinely do not survive.
            if let url = URL(string: session.currentURLString), url.scheme?.hasPrefix("http") == true {
                parked[id] = url
            }
            session.teardown()
            live[id] = nil
            recency.removeAll { $0 == id }
        }
    }
}
