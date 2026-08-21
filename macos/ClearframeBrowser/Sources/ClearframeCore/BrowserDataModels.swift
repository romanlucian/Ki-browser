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

/// One tab group: a named, colored enclosure around a run of tabs.
///
/// Foundation-only by design — the actual colors live in the macOS UI layer.
/// This record carries only the palette's stable identifier, so a restored
/// session paints the same color it was saved with even after the palette is
/// re-tuned, and an identifier this build does not know falls back to the
/// first color instead of leaving the strip to guess.
public struct TabGroupRecord: Codable, Equatable, Identifiable, Sendable {
    /// The eight colors a group can take, in the order the group editor shows
    /// them. Stored as text rather than an index so reordering the swatch row
    /// never repaints somebody's saved groups.
    public static let colorIDs = ["grey", "blue", "red", "yellow", "green", "pink", "purple", "cyan"]
    /// The fallback for an empty or unknown color: the first palette entry.
    public static let defaultColorID = "grey"

    public let id: UUID
    /// May be empty: an unnamed group shows as a colored dot, like Chrome's.
    public var title: String
    public var colorID: String
    public var isCollapsed: Bool
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String = "",
        colorID: String = TabGroupRecord.defaultColorID,
        isCollapsed: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = Self.normalizedTitle(title)
        self.colorID = Self.normalizedColorID(colorID)
        self.isCollapsed = isCollapsed
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, colorID, isCollapsed, createdAt
    }

    /// Tolerant on purpose: every field except the identifier can be missing
    /// or unrecognized, and the group still restores as a usable group.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = Self.normalizedTitle(try container.decodeIfPresent(String.self, forKey: .title) ?? "")
        colorID = Self.normalizedColorID(try container.decodeIfPresent(String.self, forKey: .colorID) ?? "")
        isCollapsed = try container.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    public static func normalizedColorID(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return colorIDs.contains(trimmed) ? trimmed : defaultColorID
    }

    public static func normalizedTitle(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct BrowserTabRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let url: String?
    public let title: String
    public let lastActivatedAt: Date
    /// The group this tab belonged to, or `nil` for an ungrouped tab. Older
    /// saved sessions have no such key at all and restore ungrouped.
    public let groupID: UUID?
    /// Whether this tab was pinned. Older saved sessions have no such key at
    /// all and restore unpinned, same as `groupID`.
    public let isPinned: Bool

    public init(
        id: UUID,
        url: String?,
        title: String,
        lastActivatedAt: Date,
        groupID: UUID? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.lastActivatedAt = lastActivatedAt
        self.groupID = groupID
        self.isPinned = isPinned
    }

    private enum CodingKeys: String, CodingKey {
        case id, url, title, lastActivatedAt, groupID, isPinned
    }

    /// Written out the same way the legacy bookmark `folderID` migration is:
    /// a record saved before tab groups or pinning existed decodes cleanly
    /// and simply has no group and is not pinned.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        title = try container.decode(String.self, forKey: .title)
        lastActivatedAt = try container.decode(Date.self, forKey: .lastActivatedAt)
        groupID = try container.decodeIfPresent(UUID.self, forKey: .groupID)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    public var restorableURL: URL? {
        guard let url else { return nil }
        return WebURLPolicy.validatedURL(url)
    }

    /// This record with a different group reference, used when normalization
    /// has to drop a group a tab still points at.
    public func withGroupID(_ groupID: UUID?) -> BrowserTabRecord {
        BrowserTabRecord(
            id: id,
            url: url,
            title: title,
            lastActivatedAt: lastActivatedAt,
            groupID: groupID,
            isPinned: isPinned
        )
    }
}

public struct BrowserWorkspaceSnapshot: Codable, Equatable, Sendable {
    public let tabs: [BrowserTabRecord]
    public let selectedTabID: UUID?
    public let groups: [TabGroupRecord]

    public init(tabs: [BrowserTabRecord], selectedTabID: UUID?, groups: [TabGroupRecord] = []) {
        self.tabs = tabs
        self.selectedTabID = selectedTabID
        self.groups = groups
    }

    private enum CodingKeys: String, CodingKey {
        case tabs, selectedTabID, groups
    }

    /// A session saved before tab groups existed has no `groups` key and
    /// restores exactly as it always did.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tabs = try container.decode([BrowserTabRecord].self, forKey: .tabs)
        selectedTabID = try container.decodeIfPresent(UUID.self, forKey: .selectedTabID)
        groups = try container.decodeIfPresent([TabGroupRecord].self, forKey: .groups) ?? []
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

        // A group only survives if one of the kept tabs still belongs to it,
        // and a tab only keeps a group reference the snapshot can resolve —
        // so trimming a session can never restore an empty or dangling group.
        var seenGroupIDs: Set<UUID> = []
        let referencedGroupIDs = Set(trimmed.compactMap(\.groupID))
        let keptGroups = groups.filter {
            seenGroupIDs.insert($0.id).inserted && referencedGroupIDs.contains($0.id)
        }
        let keptGroupIDs = Set(keptGroups.map(\.id))
        let reconciledTabs = trimmed.map { tab -> BrowserTabRecord in
            guard let groupID = tab.groupID, !keptGroupIDs.contains(groupID) else { return tab }
            return tab.withGroupID(nil)
        }

        return BrowserWorkspaceSnapshot(
            tabs: reconciledTabs,
            selectedTabID: selection,
            groups: keptGroups
        )
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
    /// The emoji this folder was saved with, before Clearframe had drawn icons.
    ///
    /// Kept, never rewritten: it is the reader's own data, and it is what
    /// `resolvedIconID` reads when a folder has not chosen an icon yet. Folders
    /// made from here on simply carry the default and choose an `iconID`.
    public var emoji: String
    /// The chosen Clearframe icon, or `nil` for a folder that predates the set
    /// or has never been edited since.
    public var iconID: String?
    /// Which of the set's four tints this folder's icon draws in, or `nil` for
    /// a folder that has never chosen one and takes the default.
    public var colorID: String?
    public var parentID: UUID?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        emoji: String = "📁",
        iconID: String? = nil,
        colorID: String? = nil,
        parentID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        self.emoji = trimmedEmoji.isEmpty ? "📁" : String(trimmedEmoji.prefix(1))
        self.iconID = Self.normalizedIconID(iconID)
        self.colorID = ClearframeIconColor.normalizedID(colorID)
        self.parentID = parentID
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, emoji, iconID, colorID, parentID, createdAt
    }

    /// Written the same way the tab-group migration is: a folder saved before
    /// the icon set existed has no `iconID` key at all, decodes cleanly, keeps
    /// its emoji, and resolves to the closest drawn icon.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji) ?? "📁"
        iconID = Self.normalizedIconID(try container.decodeIfPresent(String.self, forKey: .iconID))
        colorID = ClearframeIconColor.normalizedID(try container.decodeIfPresent(String.self, forKey: .colorID))
        parentID = try container.decodeIfPresent(UUID.self, forKey: .parentID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    /// The icon this folder draws, wherever it appears: its own choice first,
    /// then its legacy emoji's closest match, then the plain folder. Every
    /// surface asks this rather than deciding for itself.
    public var resolvedIconID: String {
        ClearframeIconCatalog.resolvedIconID(iconID: iconID, legacyEmoji: emoji)
    }

    /// The tint this folder's icon draws in, falling back to the set's default.
    public var resolvedColor: ClearframeIconColor {
        ClearframeIconColor(id: colorID) ?? .mint
    }

    /// One indivisible label prevents compact native menus from collapsing the
    /// folder title. It is the plain title now: chips and rows draw the icon
    /// themselves, beside the text rather than inside it.
    public var barLabel: String { title }

    /// Blank is the same as unset, so an empty field never shadows a folder's
    /// legacy emoji.
    private static func normalizedIconID(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
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

    public mutating func createFolder(
        title: String,
        iconID: String,
        colorID: String? = nil,
        parentID: UUID?
    ) -> BookmarkFolderRecord? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }
        let safeParent = parentID.flatMap(folder(id:))?.id
        let folder = BookmarkFolderRecord(
            title: trimmedTitle,
            iconID: iconID,
            colorID: colorID,
            parentID: safeParent
        )
        folders.append(folder)
        return folder
    }

    /// Renaming and re-icon-ing one folder. The folder's legacy `emoji` is left
    /// exactly as it was saved: choosing an icon adds a choice, it does not
    /// erase what came before.
    public mutating func updateFolder(id: UUID, title: String, iconID: String, colorID: String? = nil) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        folders[index].title = trimmedTitle
        let trimmedIconID = iconID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedIconID.isEmpty { folders[index].iconID = trimmedIconID }
        if let normalized = ClearframeIconColor.normalizedID(colorID) { folders[index].colorID = normalized }
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

    /// Applies an edited name and web address to one saved bookmark, and
    /// reports whether the edit was accepted.
    ///
    /// The record keeps its identity: same `id`, same folder, same creation
    /// date, same position in the list. An address that `WebURLPolicy` rejects
    /// changes nothing, so an editor can keep its sheet open and explain the
    /// problem, and an unknown `id` is a no-op rather than a new record. An
    /// empty name falls back to the address' host, matching how a page saved
    /// from the toolbar is named. Editing a bookmark onto an address another
    /// record already holds leaves exactly one bookmark at that address — the
    /// edited one — which is the same rule `addBookmark` applies.
    @discardableResult
    public mutating func updateBookmark(id: UUID, title: String, url: String) -> Bool {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }),
              let safeURL = WebURLPolicy.validatedURL(url) else { return false }

        let normalizedURL = safeURL.absoluteString
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = bookmarks[index]
        let updated = BookmarkRecord(
            id: existing.id,
            title: trimmedTitle.isEmpty ? (safeURL.host ?? normalizedURL) : trimmedTitle,
            url: normalizedURL,
            createdAt: existing.createdAt,
            folderID: existing.folderID
        )
        bookmarks.removeAll { $0.id != updated.id && $0.url == normalizedURL }
        guard let editedIndex = bookmarks.firstIndex(where: { $0.id == updated.id }) else { return false }
        bookmarks[editedIndex] = updated
        return true
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
