import Foundation

public enum BookmarkURLPolicy {
    /// Returns a normalized, bookmark-safe web URL. Bookmark drags deliberately
    /// reject local files, script/data schemes, incomplete hosts, and credentials
    /// embedded in a URL so a drop cannot persist an unsafe or secret-bearing link.
    public static func validatedURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              let url = components.url else { return nil }
        return url
    }
}

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
    public var folderID: UUID?

    public init(
        id: UUID = UUID(),
        title: String,
        url: String,
        createdAt: Date = Date(),
        folderID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.createdAt = createdAt
        self.folderID = folderID
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, url, createdAt, folderID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        url = try container.decode(String.self, forKey: .url)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        folderID = try container.decodeIfPresent(UUID.self, forKey: .folderID)
    }
}

public struct BookmarkFolderRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var emoji: String
    public var parentID: UUID?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        emoji: String = "📁",
        parentID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        self.emoji = trimmedEmoji.isEmpty ? "📁" : String(trimmedEmoji.prefix(1))
        self.parentID = parentID
        self.createdAt = createdAt
    }

    /// One indivisible bar label prevents compact native menus from collapsing
    /// the folder title while retaining its visual emoji identifier.
    public var barLabel: String { "\(emoji) \(title)" }
}

public struct BookmarkCollection: Codable, Equatable, Sendable {
    public private(set) var folders: [BookmarkFolderRecord]
    public private(set) var bookmarks: [BookmarkRecord]

    public init(folders: [BookmarkFolderRecord] = [], bookmarks: [BookmarkRecord] = []) {
        self.folders = folders
        self.bookmarks = bookmarks
        normalizeReferences()
    }

    public func folders(in parentID: UUID?) -> [BookmarkFolderRecord] {
        folders
            .filter { $0.parentID == parentID }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    public func bookmarks(in folderID: UUID?) -> [BookmarkRecord] {
        bookmarks
            .filter { $0.folderID == folderID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func folder(id: UUID) -> BookmarkFolderRecord? {
        folders.first { $0.id == id }
    }

    public func containsItems(in folderID: UUID) -> Bool {
        bookmarks.contains { $0.folderID == folderID } || folders.contains { $0.parentID == folderID }
    }

    public mutating func createFolder(title: String, emoji: String, parentID: UUID?) -> BookmarkFolderRecord? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }
        let safeParent = parentID.flatMap(folder(id:))?.id
        let folder = BookmarkFolderRecord(title: trimmedTitle, emoji: emoji, parentID: safeParent)
        folders.append(folder)
        return folder
    }

    public mutating func updateFolder(id: UUID, title: String, emoji: String) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        folders[index].title = trimmedTitle
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        folders[index].emoji = trimmedEmoji.isEmpty ? "📁" : String(trimmedEmoji.prefix(1))
    }

    /// Deletes only the folder record. Direct bookmarks and subfolders move to its
    /// parent so a folder operation never silently destroys saved pages.
    public mutating func deleteFolderPreservingContents(id: UUID) {
        guard let folder = folder(id: id) else { return }
        for index in bookmarks.indices where bookmarks[index].folderID == id {
            bookmarks[index].folderID = folder.parentID
        }
        for index in folders.indices where folders[index].parentID == id {
            folders[index].parentID = folder.parentID
        }
        folders.removeAll { $0.id == id }
    }

    public mutating func addBookmark(_ bookmark: BookmarkRecord) {
        var safeBookmark = bookmark
        if let folderID = safeBookmark.folderID, folder(id: folderID) == nil {
            safeBookmark.folderID = nil
        }
        bookmarks.removeAll { $0.id == safeBookmark.id || $0.url == safeBookmark.url }
        bookmarks.insert(safeBookmark, at: 0)
    }

    public mutating func removeBookmark(id: UUID) {
        bookmarks.removeAll { $0.id == id }
    }

    public mutating func moveBookmark(id: UUID, to folderID: UUID?) {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        let safeFolder = folderID.flatMap(folder(id:))?.id
        bookmarks[index].folderID = safeFolder
    }

    private mutating func normalizeReferences() {
        let folderIDs = Set(folders.map(\.id))
        for index in folders.indices {
            if folders[index].parentID == folders[index].id ||
                folders[index].parentID.map({ !folderIDs.contains($0) }) == true {
                folders[index].parentID = nil
            }
        }

        // Break imported parent cycles at the first affected folder.
        for index in folders.indices {
            var seen: Set<UUID> = [folders[index].id]
            var parent = folders[index].parentID
            while let parentID = parent {
                guard seen.insert(parentID).inserted else {
                    folders[index].parentID = nil
                    break
                }
                parent = folders.first(where: { $0.id == parentID })?.parentID
            }
        }

        for index in bookmarks.indices {
            if bookmarks[index].folderID.map({ !folderIDs.contains($0) }) == true {
                bookmarks[index].folderID = nil
            }
        }
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
