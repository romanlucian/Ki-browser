import Foundation

public enum WebURLPolicy {
    /// Returns a normalized URL that is safe to navigate to or persist. Clearframe
    /// deliberately rejects local/script/data schemes, incomplete hosts, and URLs
    /// containing credentials so the same boundary applies to navigation, history,
    /// bookmarks, popups, and restored tabs.
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

    public static func validatedURL(_ url: URL) -> URL? {
        validatedURL(url.absoluteString)
    }
}

public enum BookmarkURLPolicy {
    /// Kept as the bookmark-facing name for source compatibility. All browser
    /// entry points now share `WebURLPolicy` rather than drifting independently.
    public static func validatedURL(_ value: String) -> URL? {
        WebURLPolicy.validatedURL(value)
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
        guard let url else { return nil }
        return WebURLPolicy.validatedURL(url)
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

/// Nested totals for one bookmark folder. Both numbers describe everything
/// *inside* the folder — the folder itself is never counted in its own
/// `subfolderCount`.
public struct BookmarkDescendantCounts: Equatable, Sendable {
    public var bookmarkCount: Int
    public var subfolderCount: Int

    public init(bookmarkCount: Int = 0, subfolderCount: Int = 0) {
        self.bookmarkCount = bookmarkCount
        self.subfolderCount = subfolderCount
    }
}

public extension BookmarkCollection {
    /// Rolled-up counts for every folder, computed in a single pass so a view
    /// showing many folder cards asks for them once per render instead of
    /// walking the tree per card.
    ///
    /// The traversal is iterative post-order (no recursion, so a pathological
    /// import cannot overflow the stack) and keeps a visited set purely as
    /// defense: `init` already normalizes parent cycles, and any folder that
    /// still ends up unreachable from a root falls back to its own direct
    /// bookmarks rather than being dropped from the result.
    func descendantCounts() -> [UUID: BookmarkDescendantCounts] {
        var childIDs: [UUID: [UUID]] = [:]
        var rootIDs: [UUID] = []
        for folder in folders {
            if let parentID = folder.parentID {
                childIDs[parentID, default: []].append(folder.id)
            } else {
                rootIDs.append(folder.id)
            }
        }

        var directBookmarkCounts: [UUID: Int] = [:]
        for bookmark in bookmarks {
            guard let folderID = bookmark.folderID else { continue }
            directBookmarkCounts[folderID, default: 0] += 1
        }

        var counts: [UUID: BookmarkDescendantCounts] = [:]
        counts.reserveCapacity(folders.count)
        var visited: Set<UUID> = []
        var stack: [(id: UUID, isRollUp: Bool)] = rootIDs.reversed().map { ($0, false) }

        while let frame = stack.popLast() {
            guard frame.isRollUp else {
                guard visited.insert(frame.id).inserted else { continue }
                stack.append((frame.id, true))
                for childID in childIDs[frame.id] ?? [] {
                    stack.append((childID, false))
                }
                continue
            }
            // Children were rolled up before this frame was popped again.
            var total = BookmarkDescendantCounts(
                bookmarkCount: directBookmarkCounts[frame.id] ?? 0,
                subfolderCount: 0
            )
            for childID in childIDs[frame.id] ?? [] {
                let child = counts[childID] ?? BookmarkDescendantCounts()
                total.bookmarkCount += child.bookmarkCount
                total.subfolderCount += child.subfolderCount + 1
            }
            counts[frame.id] = total
        }

        for folder in folders where counts[folder.id] == nil {
            counts[folder.id] = BookmarkDescendantCounts(
                bookmarkCount: directBookmarkCounts[folder.id] ?? 0,
                subfolderCount: 0
            )
        }
        return counts
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
