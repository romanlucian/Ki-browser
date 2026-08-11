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

    public init(
        title: String,
        url: String,
        hostname: String,
        scheme: String,
        language: String,
        text: String,
        wordCount: Int,
        hasPasswordField: Bool,
        formActions: [String]
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
    }
}

public struct PageAnalysisContent: Codable, Equatable, Sendable {
    public let summary: String
    public let keyPoints: [String]
    public let claimsToCheck: [String]

    public init(summary: String, keyPoints: [String], claimsToCheck: [String]) {
        self.summary = summary
        self.keyPoints = keyPoints
        self.claimsToCheck = claimsToCheck
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

public enum AnalysisMode: String, Codable, Sendable {
    case local = "Local"
    case remoteAI = "AI"
}

public struct PageAnalysis: Codable, Equatable, Sendable {
    public let content: PageAnalysisContent
    public let risk: RiskAssessment
    public let readingTimeMinutes: Int
    public let mode: AnalysisMode

    public init(
        content: PageAnalysisContent,
        risk: RiskAssessment,
        readingTimeMinutes: Int,
        mode: AnalysisMode
    ) {
        self.content = content
        self.risk = risk
        self.readingTimeMinutes = readingTimeMinutes
        self.mode = mode
    }
}

public struct AnalyzedSource: Codable, Equatable, Sendable {
    public let title: String
    public let url: String
    public let hostname: String
    public let content: PageAnalysisContent

    public init(snapshot: PageSnapshot, analysis: PageAnalysis) {
        title = snapshot.title
        url = snapshot.url
        hostname = snapshot.hostname
        content = analysis.content
    }
}

public struct SourceComparison: Codable, Equatable, Sendable {
    public let overlapPercent: Int
    public let sharedThemes: [String]
    public let firstNumbers: [String]
    public let secondNumbers: [String]
    public let note: String

    public init(
        overlapPercent: Int,
        sharedThemes: [String],
        firstNumbers: [String],
        secondNumbers: [String],
        note: String
    ) {
        self.overlapPercent = overlapPercent
        self.sharedThemes = sharedThemes
        self.firstNumbers = firstNumbers
        self.secondNumbers = secondNumbers
        self.note = note
    }
}

public enum PageIntelligenceError: LocalizedError, Sendable {
    case noReadableText
    case localTranslationUnavailable
    case invalidResponse
    case remoteFailure(String)

    public var errorDescription: String? {
        switch self {
        case .noReadableText:
            return "This page does not expose enough readable text."
        case .localTranslationUnavailable:
            return "Translation needs Optional AI. Plain English simplification is local only for English pages."
        case .invalidResponse:
            return "The AI returned an unexpected response."
        case .remoteFailure(let message):
            return message
        }
    }
}
