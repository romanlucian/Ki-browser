import Foundation

public enum AIToolCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case askAndLearn = "Ask & Learn"
    case write = "Write"
    case research = "Research"
    case createImages = "Create Images"
    case createVideos = "Create Videos"
    case translate = "Translate"
    case code = "Code"

    public var id: String { rawValue }

    public var symbolName: String {
        switch self {
        case .askAndLearn: return "lightbulb.max"
        case .write: return "text.badge.plus"
        case .research: return "books.vertical"
        case .createImages: return "photo.on.rectangle.angled"
        case .createVideos: return "film.stack"
        case .translate: return "character.book.closed"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

public enum AIToolAccessLabel: String, CaseIterable, Codable, Sendable {
    case freeToTry = "Free to Try"
    case paidPlan = "Paid Plan"
    case providerTerms = "Provider Terms"
}

public enum AIToolRecommendationBadge: String, CaseIterable, Codable, Sendable {
    case bestOverall = "Best Overall"
    case bestValue = "Best Value"
    case easiestToStart = "Easiest to Start"

    fileprivate var sortPriority: Int {
        switch self {
        case .bestOverall: return 0
        case .bestValue: return 1
        case .easiestToStart: return 2
        }
    }
}

public struct AIToolRecommendation: Equatable, Sendable {
    public let category: AIToolCategory
    public let badge: AIToolRecommendationBadge
    public let rationale: String
    public let officialSourceURL: URL

    public init(
        category: AIToolCategory,
        badge: AIToolRecommendationBadge,
        rationale: String,
        officialSourceURL: URL
    ) {
        self.category = category
        self.badge = badge
        self.rationale = rationale
        self.officialSourceURL = officialSourceURL
    }
}

public struct AIToolCatalogRelease: Equatable, Sendable {
    public let version: String
    public let lastChecked: Date

    public init(version: String, lastChecked: Date) {
        self.version = version
        self.lastChecked = lastChecked
    }
}

public struct AIToolListing: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let maker: String
    public let monogram: String
    public let kind: String
    public let bestFor: String
    public let access: AIToolAccessLabel
    public let officialURL: URL
    public let categories: [AIToolCategory]
    public let recommendations: [AIToolRecommendation]

    public init(
        id: String,
        name: String,
        maker: String,
        monogram: String,
        kind: String,
        bestFor: String,
        access: AIToolAccessLabel,
        officialURL: URL,
        categories: [AIToolCategory],
        recommendations: [AIToolRecommendation] = []
    ) {
        self.id = id
        self.name = name
        self.maker = maker
        self.monogram = monogram
        self.kind = kind
        self.bestFor = bestFor
        self.access = access
        self.officialURL = officialURL
        self.categories = categories
        self.recommendations = recommendations
    }

    public func recommendation(for category: AIToolCategory?) -> AIToolRecommendation? {
        guard let category else { return nil }
        return recommendations.first(where: { $0.category == category })
    }
}

public enum AIToolCatalog {
    /// A small, bundled editorial catalog. Its checked date and configuration
    /// are intentionally explicit; the app never fetches arbitrary remote data.
    public static let release = AIToolCatalogRelease(
        version: "2026.08.11.1",
        lastChecked: Calendar(identifier: .gregorian).date(
            from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 8, day: 11)
        )!
    )

    public static let tools: [AIToolListing] = AIToolCatalogData.tools

    public static func filtered(
        category: AIToolCategory?,
        query rawQuery: String
    ) -> [AIToolListing] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matches = tools.enumerated().filter { _, tool in
            let isInCategory = category.map { tool.categories.contains($0) } ?? true
            guard isInCategory else { return false }
            guard !query.isEmpty else { return true }
            let searchable = [
                tool.name,
                tool.maker,
                tool.kind,
                tool.bestFor,
                tool.access.rawValue,
                tool.recommendations.map(\.rationale).joined(separator: " "),
                tool.categories.map(\.rawValue).joined(separator: " ")
            ].joined(separator: " ").lowercased()
            return query.split(whereSeparator: \.isWhitespace).allSatisfy { searchable.contains($0) }
        }

        return matches.sorted { left, right in
            let leftPriority = left.element.recommendation(for: category)?.badge.sortPriority ?? Int.max
            let rightPriority = right.element.recommendation(for: category)?.badge.sortPriority ?? Int.max
            if leftPriority == rightPriority { return left.offset < right.offset }
            return leftPriority < rightPriority
        }.map(\.element)
    }
}
