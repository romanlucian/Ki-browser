import ClearframeCore
import Combine
import Foundation

@MainActor
final class BrowserDataStore: ObservableObject {
    @Published private(set) var bookmarks: [BookmarkRecord]
    @Published private(set) var bookmarkFolders: [BookmarkFolderRecord]
    @Published private(set) var history: [HistoryRecord]
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
    private let saveHistoryKey = "clearframe.saveHistory"
    private let showsBookmarksBarKey = "clearframe.showBookmarksBar"
    private let maximumHistoryItems = 500

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: restoreTabsKey) == nil {
            defaults.set(true, forKey: restoreTabsKey)
        }
        if defaults.object(forKey: saveHistoryKey) == nil {
            defaults.set(true, forKey: saveHistoryKey)
        }
        if defaults.object(forKey: showsBookmarksBarKey) == nil {
            defaults.set(true, forKey: showsBookmarksBarKey)
        }
        let savedBookmarks = Self.decode([BookmarkRecord].self, key: bookmarksKey, defaults: defaults) ?? []
        let savedFolders = Self.decode([BookmarkFolderRecord].self, key: bookmarkFoldersKey, defaults: defaults) ?? []
        let bookmarkCollection = BookmarkCollection(folders: savedFolders, bookmarks: savedBookmarks)
        bookmarks = bookmarkCollection.bookmarks
        bookmarkFolders = bookmarkCollection.folders
        history = Self.decode([HistoryRecord].self, key: historyKey, defaults: defaults) ?? []
        showsBookmarksBar = defaults.bool(forKey: showsBookmarksBarKey)
        // Re-encode legacy flat bookmarks with an explicit nil folder reference. They
        // remain visible in Unfiled and no saved page is discarded during migration.
        save(bookmarks, key: bookmarksKey)
        save(bookmarkFolders, key: bookmarkFoldersKey)
    }

    var restoresTabs: Bool {
        defaults.bool(forKey: restoreTabsKey)
    }

    func loadWorkspace() -> BrowserWorkspaceSnapshot? {
        guard restoresTabs else { return nil }
        return Self.decode(BrowserWorkspaceSnapshot.self, key: workspaceKey, defaults: defaults)?.normalized()
    }

    func saveWorkspace(_ snapshot: BrowserWorkspaceSnapshot) {
        guard restoresTabs else {
            defaults.removeObject(forKey: workspaceKey)
            return
        }
        save(snapshot.normalized(), key: workspaceKey)
    }

    func clearSavedWorkspace() {
        defaults.removeObject(forKey: workspaceKey)
    }

    func isBookmarked(_ url: String) -> Bool {
        bookmarks.contains { $0.url == url }
    }

    func bookmark(for url: String) -> BookmarkRecord? {
        bookmarks.first { $0.url == url }
    }

    @discardableResult
    func addBookmark(title: String, url: String, folderID: UUID?) -> BookmarkRecord? {
        guard Self.isWebURL(url) else { return nil }
        var collection = bookmarkCollection
        let existing = bookmarks.first { $0.url == url }
        let bookmark = BookmarkRecord(
            id: existing?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? existing?.title ?? url,
            url: url,
            createdAt: existing?.createdAt ?? Date(),
            folderID: folderID
        )
        collection.addBookmark(bookmark)
        apply(collection)
        return bookmarks.first { $0.id == bookmark.id }
    }

    func toggleBookmark(title: String, url: String) {
        guard Self.isWebURL(url) else { return }
        var collection = bookmarkCollection
        if let bookmark = bookmarks.first(where: { $0.url == url }) {
            collection.removeBookmark(id: bookmark.id)
        } else {
            collection.addBookmark(BookmarkRecord(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? url,
                url: url,
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

    @discardableResult
    func createBookmarkFolder(title: String, emoji: String, parentID: UUID?) -> BookmarkFolderRecord? {
        var collection = bookmarkCollection
        let folder = collection.createFolder(title: title, emoji: emoji, parentID: parentID)
        if folder != nil { apply(collection) }
        return folder
    }

    func updateBookmarkFolder(id: UUID, title: String, emoji: String) {
        var collection = bookmarkCollection
        collection.updateFolder(id: id, title: title, emoji: emoji)
        apply(collection)
    }

    func deleteBookmarkFolderPreservingContents(_ folder: BookmarkFolderRecord) {
        var collection = bookmarkCollection
        collection.deleteFolderPreservingContents(id: folder.id)
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

    func recordVisit(title: String, url: String, at date: Date = Date()) {
        guard defaults.bool(forKey: saveHistoryKey) else { return }
        guard Self.isWebURL(url) else { return }
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
        defaults.removeObject(forKey: historyKey)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private var bookmarkCollection: BookmarkCollection {
        BookmarkCollection(folders: bookmarkFolders, bookmarks: bookmarks)
    }

    private func apply(_ collection: BookmarkCollection) {
        bookmarkFolders = collection.folders
        bookmarks = collection.bookmarks
        save(bookmarks, key: bookmarksKey)
        save(bookmarkFolders, key: bookmarkFoldersKey)
    }

    private static func decode<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func isWebURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https"].contains(scheme)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
