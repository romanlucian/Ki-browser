import ClearframeCore
import SwiftUI

struct BookmarksBar: View {
    @ObservedObject var store: BrowserDataStore
    let currentPageURL: String
    let currentBookmark: BookmarkRecord?
    let open: (String) -> Void
    let addCurrentPage: (UUID?) -> Void
    let fileDroppedURL: (URL, UUID?) -> BookmarkDropResult?
    let newFolder: (UUID?) -> Void
    /// Opens the full-page bookmarks home. Every "organize" entry point on the
    /// bar leads here now (D7); the toolbar books button keeps its own quick
    /// popover.
    let openAllBookmarks: () -> Void
    @State private var isRootDropTargeted = false
    @State private var dropConfirmation: String?

    private var rootFolders: [BookmarkFolderRecord] { store.bookmarkFolders(in: nil) }
    private var rootBookmarks: [BookmarkRecord] { store.bookmarks(in: nil) }
    private var isEmpty: Bool { rootFolders.isEmpty && rootBookmarks.isEmpty }
    private var canBookmarkCurrentPage: Bool { WebURLPolicy.validatedURL(currentPageURL) != nil }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ClearframeTheme.accent)
                .accessibilityHidden(true)

            if isEmpty {
                Button {
                    openAllBookmarks()
                } label: {
                    HStack(spacing: 5) {
                        Text("Bookmarks bar is empty")
                            .fontWeight(.semibold)
                            .foregroundStyle(ClearframeTheme.textSecondary)
                        Text("Save a page or create a folder")
                            .foregroundStyle(ClearframeTheme.textTertiary)
                    }
                    .font(.system(size: 11))
                    .lineLimit(1)
                }
                .buttonStyle(.plain)
                .help("Open all bookmarks")
                .accessibilityHint("Opens the full bookmarks page where you can create folders and organize saved pages.")
                Spacer(minLength: 0)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(rootFolders) { folder in
                            BookmarkFolderMenu(
                                store: store,
                                folder: folder,
                                compact: true,
                                currentBookmark: currentBookmark,
                                canBookmarkCurrentPage: canBookmarkCurrentPage,
                                open: open,
                                addCurrentPage: addCurrentPage,
                                fileDroppedURL: fileDroppedURL,
                                reportDrop: reportDrop,
                                newFolder: newFolder,
                                organize: openAllBookmarks
                            )
                        }
                        ForEach(rootBookmarks) { bookmark in
                            BookmarkBarLink(bookmark: bookmark, open: open)
                        }
                    }
                }
                .accessibilityLabel("Bookmarks bar")
            }

            BookmarksBarAllChip(action: openAllBookmarks)

            Menu {
                if isEmpty {
                    Text("No bookmarks yet")
                } else {
                    ForEach(rootFolders) { folder in
                        BookmarkFolderMenu(
                            store: store,
                            folder: folder,
                            compact: false,
                            currentBookmark: currentBookmark,
                            canBookmarkCurrentPage: canBookmarkCurrentPage,
                            open: open,
                            addCurrentPage: addCurrentPage,
                            fileDroppedURL: fileDroppedURL,
                            reportDrop: reportDrop,
                            newFolder: newFolder,
                            organize: openAllBookmarks
                        )
                    }
                    if !rootFolders.isEmpty && !rootBookmarks.isEmpty { Divider() }
                    ForEach(rootBookmarks) { bookmark in
                        Button { open(bookmark.url) } label: {
                            Label(bookmark.title, systemImage: "bookmark")
                        }
                    }
                }
                Divider()
                if canBookmarkCurrentPage {
                    if currentBookmark == nil {
                        Button { addCurrentPage(nil) } label: {
                            Label("Add Current Page to Bookmarks", systemImage: "bookmark.badge.plus")
                        }
                    } else {
                        Text("Current page is bookmarked")
                    }
                }
                Button { newFolder(nil) } label: {
                    Label("New Bookmark Folder…", systemImage: "folder.badge.plus")
                }
                Button { openAllBookmarks() } label: {
                    Label("Open All Bookmarks", systemImage: "books.vertical")
                }
                Button { store.showsBookmarksBar = false } label: {
                    Label("Hide Bookmarks Bar", systemImage: "eye.slash")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "ellipsis")
                    Text("More")
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ClearframeTheme.textSecondary)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(ClearframeTheme.bg3, in: RoundedRectangle(cornerRadius: ClearframeTheme.radius6))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("All bookmarks and bar options")
            .accessibilityLabel("More bookmarks")

            if let dropConfirmation {
                Label(dropConfirmation, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ClearframeTheme.accent)
                    .lineLimit(1)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                    .accessibilityLabel(dropConfirmation)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 26)
        .background(isRootDropTargeted ? ClearframeTheme.accentDim : ClearframeTheme.bg1)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isRootDropTargeted ? ClearframeTheme.accent : ClearframeTheme.hairline1)
                .frame(height: isRootDropTargeted ? 2 : 1)
        }
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, let result = fileDroppedURL(url, nil) else { return false }
            reportDrop(result, folderName: "Unfiled")
            return true
        } isTargeted: { isRootDropTargeted = $0 }
        .contextMenu {
            if canBookmarkCurrentPage {
                if currentBookmark == nil {
                    Button { addCurrentPage(nil) } label: {
                        Label("Add Current Page to Bookmarks", systemImage: "bookmark.badge.plus")
                    }
                } else {
                    Button("Current Page Is Already Bookmarked") {}.disabled(true)
                }
                Divider()
            }
            Button { newFolder(nil) } label: {
                Label("New Bookmark Folder…", systemImage: "folder.badge.plus")
            }
            Button { openAllBookmarks() } label: {
                Label("Organize Bookmarks…", systemImage: "books.vertical")
            }
            Divider()
            Button { store.showsBookmarksBar = false } label: {
                Label("Hide Bookmarks Bar", systemImage: "eye.slash")
            }
        }
        .help("Drop a page link here to save it in Unfiled. Secondary-click or Control-click for more actions.")
    }

    private func reportDrop(_ result: BookmarkDropResult, folderName: String) {
        let message: String
        switch result.disposition {
        case .created: message = "Saved to \(folderName)"
        case .moved: message = "Moved to \(folderName)"
        case .alreadyFiled: message = "Already in \(folderName)"
        }
        withAnimation(.easeOut(duration: 0.16)) { dropConfirmation = message }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            guard dropConfirmation == message else { return }
            withAnimation(.easeIn(duration: 0.16)) { dropConfirmation = nil }
        }
    }
}

/// Trailing bar chip that opens the full-page bookmarks home. Same chip
/// language as the link and folder chips beside it (B4): bg3 fill, hairline
/// edge, 22pt tall.
private struct BookmarksBarAllChip: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 9, weight: .semibold))
                Text("All bookmarks")
                    .lineLimit(1)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isHovered ? ClearframeTheme.textPrimary : ClearframeTheme.textSecondary)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                isHovered ? ClearframeTheme.bg3Hover : ClearframeTheme.bg3,
                in: RoundedRectangle(cornerRadius: ClearframeTheme.radius6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ClearframeTheme.radius6)
                    .stroke(ClearframeTheme.hairline2)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Open all bookmarks (⌘⌥B)")
        .accessibilityLabel("All bookmarks")
        .accessibilityHint("Opens the full bookmarks page with every folder and saved page.")
    }
}

private struct BookmarkBarLink: View {
    let bookmark: BookmarkRecord
    let open: (String) -> Void
    @State private var isHovered = false

    @ViewBuilder
    var body: some View {
        if let url = BookmarkURLPolicy.validatedURL(bookmark.url) {
            linkButton.draggable(url)
        } else {
            linkButton
        }
    }

    private var linkButton: some View {
        Button { open(bookmark.url) } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(IdentityColor.color(forHost: URL(string: bookmark.url)?.host ?? ""))
                    .frame(width: 6, height: 6)
                Text(bookmark.title)
                    .foregroundStyle(ClearframeTheme.textPrimary)
                    .lineLimit(1)
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(isHovered ? ClearframeTheme.bg3Hover : ClearframeTheme.bg3, in: Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 180)
        .onHover { isHovered = $0 }
        .help("Open \(bookmark.title) — \(bookmark.url)")
        .accessibilityHint("Opens this bookmark in the current tab. Drag it onto a visible folder to move it.")
    }
}

private struct BookmarkFolderMenu: View {
    @ObservedObject var store: BrowserDataStore
    let folder: BookmarkFolderRecord
    let compact: Bool
    let currentBookmark: BookmarkRecord?
    let canBookmarkCurrentPage: Bool
    let open: (String) -> Void
    let addCurrentPage: (UUID?) -> Void
    let fileDroppedURL: (URL, UUID?) -> BookmarkDropResult?
    let reportDrop: (BookmarkDropResult, String) -> Void
    let newFolder: (UUID?) -> Void
    let organize: () -> Void
    @State private var isDropTargeted = false
    // Real content is measured once via FolderChipWidthKey; 140 only ever
    // shows for the first frame, before that measurement lands.
    @State private var measuredWidth: CGFloat = 140

    private var chipWidth: CGFloat { min(measuredWidth, 220) }

    @ViewBuilder
    var body: some View {
        Group {
            if compact {
                Menu { menuContents } label: { Color.clear.frame(width: chipWidth, height: 22) }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .overlay {
                        HStack(spacing: 5) {
                            Text(folder.barLabel)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(ClearframeTheme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(ClearframeTheme.textTertiary)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 7)
                        .frame(width: chipWidth, height: 22)
                        .background(
                            isDropTargeted ? ClearframeTheme.accentDimStrong : ClearframeTheme.bg3,
                            in: RoundedRectangle(cornerRadius: ClearframeTheme.radius6)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: ClearframeTheme.radius6)
                                .stroke(isDropTargeted ? ClearframeTheme.accent : ClearframeTheme.hairline2, lineWidth: isDropTargeted ? 1.5 : 1)
                        }
                        .allowsHitTesting(false)
                    }
                    .frame(width: chipWidth, height: 22)
                    .background(widthReader)
                    .onPreferenceChange(FolderChipWidthKey.self) { measuredWidth = $0 }
                    .dropDestination(for: URL.self) { urls, _ in
                        guard let url = urls.first, let result = fileDroppedURL(url, folder.id) else { return false }
                        reportDrop(result, folder.title)
                        return true
                    } isTargeted: { isDropTargeted = $0 }
            } else {
                Menu(folder.barLabel) { menuContents }
            }
        }
        .help("Open \(folder.title) folder")
        .accessibilityLabel("\(folder.title) bookmark folder")
        .accessibilityHint("Opens this folder. Drop a page link or saved bookmark here to file it in this folder.")
        .contextMenu {
            if canBookmarkCurrentPage {
                if currentBookmark?.folderID == folder.id {
                    Button("Current Page Is in This Folder") {}.disabled(true)
                } else {
                    Button { addCurrentPage(folder.id) } label: {
                        Label(
                            currentBookmark == nil ? "Add Current Page to This Folder" : "Move Current Page to This Folder",
                            systemImage: "bookmark.badge.plus"
                        )
                    }
                }
                Divider()
            }
            Button { newFolder(folder.id) } label: {
                Label("New Subfolder…", systemImage: "folder.badge.plus")
            }
            Button(action: organize) { Label("Organize Bookmarks…", systemImage: "books.vertical") }
        }
    }

    private var menuContents: some View {
        BookmarkFolderMenuContents(
            store: store,
            folder: folder,
            currentBookmark: currentBookmark,
            canBookmarkCurrentPage: canBookmarkCurrentPage,
            open: open,
            addCurrentPage: addCurrentPage,
            fileDroppedURL: fileDroppedURL,
            reportDrop: reportDrop,
            newFolder: newFolder,
            organize: organize
        )
    }

    /// Renders the same label at its natural, unconstrained size purely to
    /// report that size via `FolderChipWidthKey` — `.fixedSize()` makes it
    /// ignore whatever width the surrounding `.frame(width: chipWidth)`
    /// proposes, and `.hidden()` means nothing here is ever drawn.
    private var widthReader: some View {
        HStack(spacing: 5) {
            Text(folder.barLabel).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 7)
        .fixedSize()
        .hidden()
        .accessibilityHidden(true)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: FolderChipWidthKey.self, value: proxy.size.width)
            }
        )
    }
}

/// D12: replaces the old hardcoded-140pt bar folder chip. `reduce` keeps the
/// most recent measurement — each `BookmarkFolderMenu` reads only its own
/// `widthReader` contribution via a same-level `.onPreferenceChange`, so
/// sibling folder chips never influence each other's width.
private struct FolderChipWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 140
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct BookmarkFolderMenuContents: View {
    @ObservedObject var store: BrowserDataStore
    let folder: BookmarkFolderRecord
    let currentBookmark: BookmarkRecord?
    let canBookmarkCurrentPage: Bool
    let open: (String) -> Void
    let addCurrentPage: (UUID?) -> Void
    let fileDroppedURL: (URL, UUID?) -> BookmarkDropResult?
    let reportDrop: (BookmarkDropResult, String) -> Void
    let newFolder: (UUID?) -> Void
    let organize: () -> Void

    private var childFolders: [BookmarkFolderRecord] { store.bookmarkFolders(in: folder.id) }
    private var bookmarks: [BookmarkRecord] { store.bookmarks(in: folder.id) }

    var body: some View {
        if childFolders.isEmpty && bookmarks.isEmpty {
            Text("Empty folder")
        } else {
            ForEach(childFolders) { child in
                BookmarkFolderMenu(
                    store: store,
                    folder: child,
                    compact: false,
                    currentBookmark: currentBookmark,
                    canBookmarkCurrentPage: canBookmarkCurrentPage,
                    open: open,
                    addCurrentPage: addCurrentPage,
                    fileDroppedURL: fileDroppedURL,
                    reportDrop: reportDrop,
                    newFolder: newFolder,
                    organize: organize
                )
            }
            if !childFolders.isEmpty && !bookmarks.isEmpty { Divider() }
            ForEach(bookmarks) { bookmark in
                Button { open(bookmark.url) } label: { Label(bookmark.title, systemImage: "bookmark") }
            }
        }
    }
}
