import Foundation

/// A dated fact about how the AI field is moving, and where it came from.
///
/// Not a ranking, not a measurement Limeghost took, and not a live figure.
/// Every one of these is a published trend from a named source under a licence
/// that permits reuse, quoted rather than recomputed, and carrying the date it
/// was last checked.
public struct AIFieldNote: Identifiable, Sendable {
    public let id: String
    /// The number itself, short enough to read at a glance.
    public let figure: String
    /// What the number is measuring, in a phrase.
    public let measure: String
    /// Why it matters to somebody choosing a tool — the reason this is on a
    /// page about choosing, rather than a statistics page.
    public let meaning: String
    public let source: String
    public let sourceURL: URL

    public init(id: String, figure: String, measure: String, meaning: String, source: String, sourceURL: URL) {
        self.id = id
        self.figure = figure
        self.measure = measure
        self.meaning = meaning
        self.source = source
        self.sourceURL = sourceURL
    }
}

/// Somewhere to see figures Limeghost deliberately does not hold: live,
/// changing comparisons that would be wrong within days if they were compiled
/// into an app that updates when somebody reinstalls it.
public struct AIFieldReference: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let summary: String
    public let url: URL

    public init(id: String, name: String, summary: String, url: URL) {
        self.id = id
        self.name = name
        self.summary = summary
        self.url = url
    }
}

/// The small, deliberately dull set of orientation facts on the AI home.
///
/// The rule that shapes this list: **a trend, never a rank.** "Model X is best"
/// is stale within days and is the judgment layer this product removed on
/// August 30, 2026. "Training compute has grown 4.5× a year since 2010" is
/// still true next year, is somebody else's published measurement, and is
/// useful to a person deciding whether to pay for a tool this month.
///
/// Everything here is quoted from Epoch AI, whose data is published under
/// Creative Commons Attribution — "free to use, distribute, and reproduce
/// provided the source and authors are credited". The credit is the licence,
/// so `source` is drawn wherever a note is, never optionally.
public enum AIFieldNotes {
    /// When a human last opened every source below and re-read these figures.
    /// It does not move on its own; a missed review shows an older date rather
    /// than a fresher-looking lie.
    public static let lastChecked: Date = Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 9, day: 2)
    ) ?? Date(timeIntervalSince1970: 1_788_307_200)

    public static let notes: [AIFieldNote] = [
        AIFieldNote(
            id: "training-compute",
            figure: "4.5× a year",
            measure: "growth in the compute used to train notable AI models, since 2010",
            meaning: "Why the tools keep changing under you. A model that felt remarkable last year is an ordinary one now.",
            source: "Epoch AI",
            sourceURL: URL(string: "https://epoch.ai/trends")!
        ),
        AIFieldNote(
            id: "compute-efficiency",
            figure: "3× less",
            measure: "compute needed each year to reach the same performance",
            meaning: "Why capable tools keep arriving on free plans. What cost real money to run last year is cheap to run this year.",
            source: "Epoch AI",
            sourceURL: URL(string: "https://epoch.ai/trends")!
        ),
        AIFieldNote(
            id: "consumer-hardware",
            figure: "about a year",
            measure: "before frontier performance is reachable on ordinary consumer hardware",
            meaning: "Worth knowing before paying for the newest thing. Waiting is often a real option.",
            source: "Epoch AI",
            sourceURL: URL(string: "https://epoch.ai/trends")!
        ),
    ]

    /// Places that hold the live numbers. Limeghost links to these rather than
    /// copying them: a leaderboard position changes daily, this app changes
    /// when somebody reinstalls it, and a stale rank presented as current is
    /// worse than no rank at all.
    public static let references: [AIFieldReference] = [
        AIFieldReference(
            id: "lmarena",
            name: "LMArena",
            summary: "People compare two anonymous models and vote. Updated continuously.",
            url: URL(string: "https://lmarena.ai")!
        ),
        AIFieldReference(
            id: "artificial-analysis",
            name: "Artificial Analysis",
            summary: "Independent speed, price and quality comparisons across providers.",
            url: URL(string: "https://artificialanalysis.ai")!
        ),
        AIFieldReference(
            id: "ai-index",
            name: "Stanford AI Index",
            summary: "An annual, heavily sourced report on the state of the field.",
            url: URL(string: "https://hai.stanford.edu/ai-index")!
        ),
    ]
}
