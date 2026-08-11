import ClearframeCore
import Combine
import Foundation

@MainActor
final class BrowserDataStore: ObservableObject {
    @Published private(set) var bookmarks: [BookmarkRecord]
    @Published private(set) var history: [HistoryRecord]

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let bookmarksKey = "clearframe.bookmarks.v1"
    private let historyKey = "clearframe.history.v1"
    private let workspaceKey = "clearframe.workspace.v1"
    private let restoreTabsKey = "clearframe.restoreTabs"
    private let saveHistoryKey = "clearframe.saveHistory"
    private let maximumHistoryItems = 500

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: restoreTabsKey) == nil {
            defaults.set(true, forKey: restoreTabsKey)
        }
        if defaults.object(forKey: saveHistoryKey) == nil {
            defaults.set(true, forKey: saveHistoryKey)
        }
        bookmarks = Self.decode([BookmarkRecord].self, key: bookmarksKey, defaults: defaults) ?? []
        history = Self.decode([HistoryRecord].self, key: historyKey, defaults: defaults) ?? []
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

    func toggleBookmark(title: String, url: String) {
        guard Self.isWebURL(url) else { return }
        if let index = bookmarks.firstIndex(where: { $0.url == url }) {
            bookmarks.remove(at: index)
        } else {
            bookmarks.insert(
                BookmarkRecord(title: title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? url, url: url),
                at: 0
            )
        }
        save(bookmarks, key: bookmarksKey)
    }

    func removeBookmark(_ bookmark: BookmarkRecord) {
        bookmarks.removeAll { $0.id == bookmark.id }
        save(bookmarks, key: bookmarksKey)
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
