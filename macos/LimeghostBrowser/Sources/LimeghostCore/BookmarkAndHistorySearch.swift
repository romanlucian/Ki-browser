import Foundation

/// Filtering bookmarks by what was typed. The Mac's bookmarks home and the
/// phone's Bookmarks sheet both search through this, so the two platforms
/// cannot come to disagree about what a search finds.
///
/// Pure and static, so it is tested without a view. Matching mirrors the
/// organizer: case-insensitive `contains` on the page title and web address,
/// plus the folder title.
public enum BookmarksHomeSearch {
    public static func folders(_ folders: [BookmarkFolderRecord], matching query: String) -> [BookmarkFolderRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return folders }
        return folders.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    public static func bookmarks(_ bookmarks: [BookmarkRecord], matching query: String) -> [BookmarkRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return bookmarks }
        return bookmarks.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || $0.url.localizedCaseInsensitiveContains(trimmed)
        }
    }
}

/// Filtering history by what was typed, for the Mac's history home and the
/// phone's History sheet alike. Pure and static, so it is tested without a
/// view.
public enum HistoryHomeSearch {
    public static func visits(_ visits: [HistoryRecord], matching search: String) -> [HistoryRecord] {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return visits }
        return visits.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) || $0.url.localizedCaseInsensitiveContains(trimmed)
        }
    }
}
