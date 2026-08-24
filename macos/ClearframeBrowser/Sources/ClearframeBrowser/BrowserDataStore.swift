import ClearframeCore
import Combine
import Foundation

@MainActor
final class BrowserDataStore: ObservableObject {
    @Published private(set) var bookmarks: [BookmarkRecord] { didSet { cachedBookmarkCollection = nil } }
    @Published private(set) var bookmarkFolders: [BookmarkFolderRecord] { didSet { cachedBookmarkCollection = nil } }
    @Published private(set) var history: [HistoryRecord]
    @Published private(set) var recoveryNotice: String?
    @Published var showsBookmarksBar: Bool {
        didSet { defaults.set(showsBookmarksBar, forKey: showsBookmarksBarKey) }
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let bookmarksKey = "clearframe.bookmarks.v1"
    private let bookmarkFoldersKey = "clearframe.bookmarkFolders.v2"
    private let historyKey = "clearframe.history.v1"
    private let workspaceKey = "clearframe.workspace.v1"
    private let restoreTabsKey = "clearframe.restoreTabs"
    private let reloadRestoredTabsKey = "clearframe.reloadRestoredTabs"
    private let saveHistoryKey = "clearframe.saveHistory"
    private let showsBookmarksBarKey = "clearframe.showBookmarksBar"
    private let maximumHistoryItems = 500

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: reloadRestoredTabsKey) == nil {
            defaults.set(false, forKey: reloadRestoredTabsKey)
        }
        if defaults.object(forKey: restoreTabsKey) == nil {
            defaults.set(true, forKey: restoreTabsKey)
        }
        if defaults.object(forKey: saveHistoryKey) == nil {
            defaults.set(true, forKey: saveHistoryKey)
        }
        if defaults.object(forKey: showsBookmarksBarKey) == nil {
            defaults.set(true, forKey: showsBookmarksBarKey)
        }
        let bookmarkLoad = Self.loadRecovering([BookmarkRecord].self, key: bookmarksKey, defaults: defaults)
        let folderLoad = Self.loadRecovering([BookmarkFolderRecord].self, key: bookmarkFoldersKey, defaults: defaults)
        let historyLoad = Self.loadRecovering([HistoryRecord].self, key: historyKey, defaults: defaults)
        let bookmarkCollection = BookmarkCollection(
            folders: folderLoad.value ?? [],
            bookmarks: bookmarkLoad.value ?? []
        )
        bookmarks = bookmarkCollection.bookmarks
        bookmarkFolders = bookmarkCollection.folders
        history = historyLoad.value ?? []
        showsBookmarksBar = defaults.bool(forKey: showsBookmarksBarKey)
        let recoveredNames = [
            bookmarkLoad.wasRecovered ? "bookmarks" : nil,
            folderLoad.wasRecovered ? "bookmark folders" : nil,
            historyLoad.wasRecovered ? "history" : nil
        ].compactMap { $0 }
        let unreadableNames = [
            bookmarkLoad.isUnreadable ? "bookmarks" : nil,
            folderLoad.isUnreadable ? "bookmark folders" : nil,
            historyLoad.isUnreadable ? "history" : nil
        ].compactMap { $0 }
        if !unreadableNames.isEmpty {
            recoveryNotice = "Clearframe could not read saved \(unreadableNames.joined(separator: ", ")). The original data was preserved for recovery and was not replaced."
        } else if !recoveredNames.isEmpty {
            recoveryNotice = "Clearframe restored \(recoveredNames.joined(separator: ", ")) from the last known-good local backup."
        } else {
            recoveryNotice = nil
        }
        // Re-encode legacy flat bookmarks with an explicit nil folder reference. They
        // remain visible in Unfiled and no saved page is discarded during migration.
        if !bookmarkLoad.isUnreadable { save(bookmarks, key: bookmarksKey) }
        if !folderLoad.isUnreadable { save(bookmarkFolders, key: bookmarkFoldersKey) }
    }

    var restoresTabs: Bool {
        defaults.bool(forKey: restoreTabsKey)
    }

    /// Whether every restored tab loads its page at start, rather than the
    /// selected one loading and the rest waiting to be opened.
    ///
    /// Off by default, which is what every mainstream browser does: a window
    /// of twelve restored tabs would otherwise mean twelve page loads nobody
    /// asked for, competing for the network on the slowest minute of the day.
    /// The tabs and their icons are there either way.
    var reloadsRestoredTabs: Bool {
        defaults.bool(forKey: reloadRestoredTabsKey)
    }

    func loadWorkspace() -> BrowserWorkspaceSnapshot? {
        guard restoresTabs else { return nil }
        let load = Self.loadRecovering(BrowserWorkspaceSnapshot.self, key: workspaceKey, defaults: defaults)
        if load.wasRecovered {
            recoveryNotice = "Clearframe restored the previous tab session from the last known-good local backup."
        } else if load.isUnreadable {
            recoveryNotice = "Clearframe could not read the previous tab session. The original data was preserved and no unsafe URL was restored."
        }
        return load.value?.normalized()
    }

    func saveWorkspace(_ snapshot: BrowserWorkspaceSnapshot) {
        guard restoresTabs else {
            removeStoredValue(forKey: workspaceKey)
            return
        }
        save(snapshot.normalized(), key: workspaceKey)
    }

    func clearSavedWorkspace() {
        removeStoredValue(forKey: workspaceKey)
    }

    func isBookmarked(_ url: String) -> Bool {
        bookmarks.contains { $0.url == url }
    }

    func bookmark(for url: String) -> BookmarkRecord? {
        bookmarks.first { $0.url == url }
    }

    @discardableResult
    func addBookmark(title: String, url: String, folderID: UUID?) -> BookmarkRecord? {
        guard let safeURL = BookmarkURLPolicy.validatedURL(url) else { return nil }
        let normalizedURL = safeURL.absoluteString
        var collection = bookmarkCollection
        let existing = bookmarks.first { $0.url == normalizedURL }
        let proposedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedProposedTitle = proposedTitle
            .lowercased()
            .replacingOccurrences(of: "…", with: "...")
        let usableTitle = ["loading", "loading...", "new tab"]
            .contains(normalizedProposedTitle) ? nil : proposedTitle.nilIfEmpty
        let bookmark = BookmarkRecord(
            id: existing?.id ?? UUID(),
            title: usableTitle ?? existing?.title ?? safeURL.host ?? normalizedURL,
            url: normalizedURL,
            createdAt: existing?.createdAt ?? Date(),
            folderID: folderID
        )
        collection.addBookmark(bookmark)
        apply(collection)
        return bookmarks.first { $0.id == bookmark.id }
    }

    /// Files a URL delivered by a native drag. An exact normalized URL is unique:
    /// dropping it again reuses and, when needed, moves the existing record.
    @discardableResult
    func fileBookmarkFromDrop(_ url: URL, title: String?, to folderID: UUID?) -> BookmarkDropResult? {
        guard let safeURL = BookmarkURLPolicy.validatedURL(url.absoluteString) else { return nil }
        if let folderID, bookmarkFolder(id: folderID) == nil { return nil }

        let normalizedURL = safeURL.absoluteString
        let existing = bookmark(for: normalizedURL)
        guard let bookmark = addBookmark(
            title: title ?? existing?.title ?? safeURL.host ?? normalizedURL,
            url: normalizedURL,
            folderID: folderID
        ) else { return nil }

        let disposition: BookmarkDropDisposition
        if let existing {
            disposition = existing.folderID == bookmark.folderID ? .alreadyFiled : .moved
        } else {
            disposition = .created
        }
        return BookmarkDropResult(bookmark: bookmark, disposition: disposition)
    }

    func toggleBookmark(title: String, url: String) {
        guard let safeURL = BookmarkURLPolicy.validatedURL(url) else { return }
        let normalizedURL = safeURL.absoluteString
        var collection = bookmarkCollection
        if let bookmark = bookmarks.first(where: { $0.url == normalizedURL }) {
            collection.removeBookmark(id: bookmark.id)
        } else {
            collection.addBookmark(BookmarkRecord(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? normalizedURL,
                url: normalizedURL,
                folderID: nil
            ))
        }
        apply(collection)
    }

    func removeBookmark(_ bookmark: BookmarkRecord) {
        var collection = bookmarkCollection
        collection.removeBookmark(id: bookmark.id)
        apply(collection)
    }

    /// Saves an edited bookmark name and address. Returns `false` — and writes
    /// nothing — when the address is not a credential-free web link or the
    /// bookmark no longer exists, so the editor can stay open and say why.
    @discardableResult
    func updateBookmark(id: UUID, title: String, url: String) -> Bool {
        var collection = bookmarkCollection
        guard collection.updateBookmark(id: id, title: title, url: url) else { return false }
        apply(collection)
        return true
    }

    @discardableResult
    func createBookmarkFolder(title: String, iconID: String, colorID: String? = nil, parentID: UUID?) -> BookmarkFolderRecord? {
        var collection = bookmarkCollection
        let folder = collection.createFolder(title: title, iconID: iconID, colorID: colorID, parentID: parentID)
        if folder != nil { apply(collection) }
        return folder
    }

    func updateBookmarkFolder(id: UUID, title: String, iconID: String, colorID: String? = nil) {
        var collection = bookmarkCollection
        collection.updateFolder(id: id, title: title, iconID: iconID, colorID: colorID)
        apply(collection)
    }

    func deleteBookmarkFolderPreservingContents(_ folder: BookmarkFolderRecord) {
        var collection = bookmarkCollection
        collection.deleteFolderPreservingContents(id: folder.id)
        apply(collection)
    }

    /// Puts a folder at a given place among the ones beside it.
    func moveFolder(_ id: UUID, toIndex index: Int) {
        var collection = bookmarkCollection
        collection.moveFolder(id: id, toIndex: index)
        apply(collection)
    }

    /// Puts a bookmark at a given place among the ones beside it, which is
    /// what dragging one along the bar means.
    func moveBookmark(_ id: UUID, toIndex index: Int) {
        var collection = bookmarkCollection
        collection.moveBookmark(id: id, toIndex: index)
        apply(collection)
    }

    func moveBookmark(_ bookmark: BookmarkRecord, to folderID: UUID?) {
        var collection = bookmarkCollection
        collection.moveBookmark(id: bookmark.id, to: folderID)
        apply(collection)
    }

    func bookmarkFolder(id: UUID) -> BookmarkFolderRecord? {
        bookmarkCollection.folder(id: id)
    }

    func bookmarkFolders(in parentID: UUID?) -> [BookmarkFolderRecord] {
        bookmarkCollection.folders(in: parentID)
    }

    func bookmarks(in folderID: UUID?) -> [BookmarkRecord] {
        bookmarkCollection.bookmarks(in: folderID)
    }

    func bookmarkFolderContainsItems(_ folder: BookmarkFolderRecord) -> Bool {
        bookmarkCollection.containsItems(in: folder.id)
    }

    /// Nested totals for every folder in one pass. Views that show many folders
    /// call this once per render and look each folder up in the result.
    func bookmarkDescendantCounts() -> [UUID: BookmarkDescendantCounts] {
        bookmarkCollection.descendantCounts()
    }

    func recordVisit(title: String, url: String, at date: Date = Date()) {
        guard defaults.bool(forKey: saveHistoryKey) else { return }
        guard BookmarkURLPolicy.validatedURL(url) != nil else { return }
        if history.first?.url == url, date.timeIntervalSince(history.first?.visitedAt ?? .distantPast) < 30 {
            return
        }
        history.insert(
            HistoryRecord(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? url,
                url: url,
                visitedAt: date
            ),
            at: 0
        )
        if history.count > maximumHistoryItems {
            history.removeLast(history.count - maximumHistoryItems)
        }
        save(history, key: historyKey)
    }

    func removeHistory(_ item: HistoryRecord) {
        history.removeAll { $0.id == item.id }
        save(history, key: historyKey)
    }

    func clearHistory() {
        history = []
        removeStoredValue(forKey: historyKey)
    }

    func clearAllBrowserRecords() {
        bookmarks = []
        bookmarkFolders = []
        history = []
        removeStoredValue(forKey: bookmarksKey)
        removeStoredValue(forKey: bookmarkFoldersKey)
        removeStoredValue(forKey: historyKey)
        removeStoredValue(forKey: workspaceKey)
        recoveryNotice = nil
    }

    func dismissRecoveryNotice() {
        recoveryNotice = nil
    }

    private func save<T: Codable>(_ value: T, key: String) {
        guard let data = try? encoder.encode(value) else { return }
        if let current = defaults.data(forKey: key),
           (try? decoder.decode(T.self, from: current)) != nil {
            defaults.set(current, forKey: Self.backupKey(for: key))
        }
        defaults.set(data, forKey: key)
    }

    /// Rebuilt only when the records actually change, never per read.
    ///
    /// This used to be a plain computed property, and every read accessor
    /// below goes through it — `bookmarkFolders(in:)`, `bookmarks(in:)`,
    /// `bookmarkFolder(id:)`, `bookmarkFolderContainsItems(_:)`,
    /// `bookmarkDescendantCounts()`. Those are exactly what SwiftUI view
    /// bodies call, once per folder, per render. So one bookmarks-bar
    /// layout rebuilt and re-normalized the whole collection once per chip,
    /// and moving the window — which re-lays out the chrome — stalled for
    /// seconds once somebody had imported a few hundred bookmarks.
    ///
    /// Correctness rests on `didSet` above: any write to either array drops
    /// the cache, so there is no path that can serve a stale collection.
    private var cachedBookmarkCollection: BookmarkCollection?

    private var bookmarkCollection: BookmarkCollection {
        if let cachedBookmarkCollection { return cachedBookmarkCollection }
        let built = BookmarkCollection(folders: bookmarkFolders, bookmarks: bookmarks)
        cachedBookmarkCollection = built
        return built
    }

    private func apply(_ collection: BookmarkCollection) {
        bookmarkFolders = collection.folders
        bookmarks = collection.bookmarks
        // Seeded after both assignments, because each one clears the cache.
        // `collection` is already normalized — it came from a normalized
        // collection through a mutation that maintains that — so this saves
        // the first read after every change from rebuilding it.
        cachedBookmarkCollection = collection
        save(bookmarks, key: bookmarksKey)
        save(bookmarkFolders, key: bookmarkFoldersKey)
    }

    private func removeStoredValue(forKey key: String) {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: Self.backupKey(for: key))
        defaults.removeObject(forKey: Self.corruptKey(for: key))
    }

    private static func loadRecovering<T: Decodable>(
        _ type: T.Type,
        key: String,
        defaults: UserDefaults
    ) -> PersistenceLoad<T> {
        guard let primary = defaults.data(forKey: key) else {
            return PersistenceLoad(value: nil, wasRecovered: false, isUnreadable: false)
        }
        if let value = try? JSONDecoder().decode(type, from: primary) {
            return PersistenceLoad(value: value, wasRecovered: false, isUnreadable: false)
        }

        defaults.set(primary, forKey: corruptKey(for: key))
        if let backup = defaults.data(forKey: backupKey(for: key)),
           let recovered = try? JSONDecoder().decode(type, from: backup) {
            defaults.set(backup, forKey: key)
            return PersistenceLoad(value: recovered, wasRecovered: true, isUnreadable: false)
        }
        return PersistenceLoad(value: nil, wasRecovered: false, isUnreadable: true)
    }

    private static func backupKey(for key: String) -> String { "\(key).lastKnownGood" }
    private static func corruptKey(for key: String) -> String { "\(key).unreadable" }

}

private struct PersistenceLoad<Value> {
    let value: Value?
    let wasRecovered: Bool
    let isUnreadable: Bool
}

enum BookmarkDropDisposition: Equatable {
    case created
    case moved
    case alreadyFiled
}

struct BookmarkDropResult {
    let bookmark: BookmarkRecord
    let disposition: BookmarkDropDisposition
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
