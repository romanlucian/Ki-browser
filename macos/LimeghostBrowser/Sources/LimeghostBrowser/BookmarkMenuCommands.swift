import LimeghostCore
import SwiftUI

/// The bookmarks bar's folders, as menu-bar menus.
///
/// Deliberately not the bar's own `BookmarkFolderMenu`: that one carries drop
/// targets, a compact mode, and the current page's bookmark state, none of
/// which mean anything in the menu bar. This is the same tree with nothing but
/// opening.
struct BookmarkMenuContents: View {
    @ObservedObject var store: BrowserDataStore
    let parentID: UUID?
    let open: (URL) -> Void
    /// The menu bar has no environment to read this from.
    var favicons: FaviconStore?

    private var folders: [BookmarkFolderRecord] { store.bookmarkFolders(in: parentID) }
    private var bookmarks: [BookmarkRecord] { store.bookmarks(in: parentID) }

    var body: some View {
        if folders.isEmpty && bookmarks.isEmpty {
            Text("Empty")
        } else {
            ForEach(folders) { folder in
                Menu {
                    BookmarkMenuContents(
                        store: store,
                        parentID: folder.id,
                        open: open,
                        favicons: favicons
                    )
                } label: {
                    Label(BookmarkMenuTitle.short(folder.title), systemImage: "folder")
                }
            }
            if !folders.isEmpty && !bookmarks.isEmpty { Divider() }
            ForEach(bookmarks) { bookmark in
                Button {
                    // The same boundary as everywhere else: a saved record
                    // that is not a web address is not opened.
                    guard let url = WebURLPolicy.validatedURL(bookmark.url) else { return }
                    open(url)
                } label: {
                    PageMenuRow(
                        title: BookmarkMenuTitle.short(bookmark.title),
                        url: bookmark.url,
                        store: favicons
                    )
                }
            }
        }
    }
}

enum BookmarkMenuTitle {
    /// Page titles run long and menus do not. Cut on a word where possible so
    /// the label still reads as a name rather than a fragment.
    static func short(_ title: String, limit: Int = 60) -> String {
        let collapsed = title
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard collapsed.count > limit else {
            return collapsed.isEmpty ? "Untitled" : collapsed
        }
        let cut = String(collapsed.prefix(limit))
        let onWord = cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? cut
        return onWord + "…"
    }
}
