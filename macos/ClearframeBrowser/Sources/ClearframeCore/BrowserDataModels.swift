import Foundation

public struct BrowserTabRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let url: String?
    public let title: String
    public let lastActivatedAt: Date

    public init(id: UUID, url: String?, title: String, lastActivatedAt: Date) {
        self.id = id
        self.url = url
        self.title = title
        self.lastActivatedAt = lastActivatedAt
    }

    public var restorableURL: URL? {
        guard let url,
              let parsed = URL(string: url),
              let scheme = parsed.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else { return nil }
        return parsed
    }
}

public struct BrowserWorkspaceSnapshot: Codable, Equatable, Sendable {
    public let tabs: [BrowserTabRecord]
    public let selectedTabID: UUID?

    public init(tabs: [BrowserTabRecord], selectedTabID: UUID?) {
        self.tabs = tabs
        self.selectedTabID = selectedTabID
    }

    public func normalized(maximumTabs: Int = 12) -> BrowserWorkspaceSnapshot {
        let safeLimit = max(1, maximumTabs)
        let trimmed = Array(tabs.sorted { $0.lastActivatedAt > $1.lastActivatedAt }.prefix(safeLimit))
            .sorted { left, right in
                guard let leftIndex = tabs.firstIndex(where: { $0.id == left.id }),
                      let rightIndex = tabs.firstIndex(where: { $0.id == right.id }) else { return false }
                return leftIndex < rightIndex
            }
        let selection = trimmed.contains(where: { $0.id == selectedTabID }) ? selectedTabID : trimmed.first?.id
        return BrowserWorkspaceSnapshot(tabs: trimmed, selectedTabID: selection)
    }
}

public struct BookmarkRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public let url: String
    public let createdAt: Date

    public init(id: UUID = UUID(), title: String, url: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.url = url
        self.createdAt = createdAt
    }
}

public struct HistoryRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let url: String
    public let visitedAt: Date

    public init(id: UUID = UUID(), title: String, url: String, visitedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.url = url
        self.visitedAt = visitedAt
    }
}
