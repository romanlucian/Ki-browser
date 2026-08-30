import Foundation

public struct PageSnapshot: Codable, Equatable, Sendable {
    public let title: String
    public let url: String
    public let hostname: String
    public let scheme: String
    public let language: String
    public let text: String
    public let wordCount: Int
    public let hasPasswordField: Bool
    public let formActions: [String]
    /// What share of the page's reading text the extractor's chosen container held.
    ///
    /// Optional because the shared contract's fixtures predate it and describe text
    /// directly rather than a page it was pulled from. `0` means extraction found no
    /// dominant body of text and fell back to reading the whole document, so the
    /// result is a guess and the interface should say so rather than present it
    /// as the article.
    public let extractionConfidence: Double?

    public init(
        title: String,
        url: String,
        hostname: String,
        scheme: String,
        language: String,
        text: String,
        wordCount: Int,
        hasPasswordField: Bool,
        formActions: [String],
        extractionConfidence: Double? = nil
    ) {
        self.title = title
        self.url = url
        self.hostname = hostname
        self.scheme = scheme
        self.language = language
        self.text = text
        self.wordCount = wordCount
        self.hasPasswordField = hasPasswordField
        self.formActions = formActions
        self.extractionConfidence = extractionConfidence
    }
}

public struct RiskSignal: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let points: Int
    public let title: String
    public let detail: String

    public init(id: UUID = UUID(), points: Int, title: String, detail: String) {
        self.id = id
        self.points = points
        self.title = title
        self.detail = detail
    }
}

public enum RiskLevel: String, Codable, Sendable {
    case low = "Low"
    case caution = "Caution"
    case high = "High"
}

public struct RiskAssessment: Codable, Equatable, Sendable {
    public let score: Int
    public let level: RiskLevel
    public let signals: [RiskSignal]
    public let secureConnection: Bool

    public init(score: Int, level: RiskLevel, signals: [RiskSignal], secureConnection: Bool) {
        self.score = score
        self.level = level
        self.signals = signals
        self.secureConnection = secureConnection
    }
}

public enum PageStructure: String, Codable, Sendable {
    case article
    case listing
}

/// What Analyze Page can say about a page without reading it.
///
/// Both members are computed, not judged: the risk assessment is a fixed set of
/// signals with published rules, and the reading time is a word count divided by a
/// constant. Nothing here claims to know what the page is about.
public struct PageAnalysis: Codable, Equatable, Sendable {
    public let risk: RiskAssessment
    public let readingTimeMinutes: Int

    public init(risk: RiskAssessment, readingTimeMinutes: Int) {
        self.risk = risk
        self.readingTimeMinutes = readingTimeMinutes
    }
}
public enum PageIntelligenceError: LocalizedError, Sendable {
    case noReadableText

    public var errorDescription: String? {
        switch self {
        case .noReadableText:
            return "This page does not expose enough readable text."
        }
    }
}
