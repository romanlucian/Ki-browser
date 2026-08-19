import AppKit
import ClearframeCore
import SwiftUI

/// Metrics for one row of bookmarks bar items.
///
/// The bar's rhythm is deliberately tight, like Chrome's: every item hugs its
/// own name, and only `itemGap` separates one from the next, so a row of short
/// folder names reads as an even run of labels instead of a sparse grid.
@MainActor
enum BookmarkBarMetrics {
    static let itemHeight: CGFloat = 22
    /// The bar itself. Items are shorter than this so they read as chips, but
    /// they must still take the whole height for pointing: a strip of bar
    /// above and below each one that swallowed clicks meant a right-click near
    /// an item opened the bar's own menu instead of the item's.
    static let barHeight: CGFloat = 28
    /// Padding inside one item, left and right of its content.
    static let itemPadding: CGFloat = 8
    /// Space between two adjacent items. With `itemPadding` on both sides this
    /// puts 18pt between neighbouring labels — Chrome's density.
    static let itemGap: CGFloat = 2
    /// Space between an item's site icon and its name.
    static let iconGap: CGFloat = 6
    /// How wide one item may get before its name truncates. Long titles stop
    /// stealing the row from everything saved after them.
    static let maximumItemWidth: CGFloat = 180
    static let labelFontSize: CGFloat = 12
    /// A folder's mark, sized to match the site icons it sits beside.
    static let folderIconSize: CGFloat = 13

    private static let labelFont = NSFont.systemFont(ofSize: labelFontSize, weight: .medium)
    /// Bar items re-render on every hover; measuring each label once keeps
    /// that free.
    private static var labelWidths: [String: CGFloat] = [:]

    /// Width of `label` drawn in the bar's own font.
    static func labelWidth(_ label: String) -> CGFloat {
        if let cached = labelWidths[label] { return cached }
        let measured = ceil((label as NSString).size(withAttributes: [.font: labelFont]).width)
        labelWidths[label] = measured
        return measured
    }

    /// The width one item wants: its name at natural width, its icon when it
    /// has one, plus padding — never more than `maximumItemWidth`.
    static func naturalWidth(label: String, iconWidth: CGFloat = 0) -> CGFloat {
        let icon = iconWidth > 0 ? iconWidth + iconGap : 0
        return min(labelWidth(label) + icon + itemPadding * 2, maximumItemWidth)
    }

    /// A hard width, but only for a name long enough to need the cap: that is
    /// what makes it truncate with an ellipsis. `nil` — the common case — is
    /// the instruction to leave the item hugging its own content.
    static func cappedWidth(label: String, iconWidth: CGFloat = 0) -> CGFloat? {
        let icon = iconWidth > 0 ? iconWidth + iconGap : 0
        let natural = labelWidth(label) + icon + itemPadding * 2
        return natural > maximumItemWidth ? maximumItemWidth : nil
    }
}

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
    /// Opens one saved page in a new tab, for "Open in new tab" and "Open all".
    /// Optional so a host that has no tabs of its own still builds; the bar
    /// then falls back to `open` rather than showing a dead menu entry.
    var openInNewTab: ((String) -> Void)? = nil

    @State private var isRootDropTargeted = false
    @State private var dropConfirmation: String?
    /// One sheet slot for both editors: SwiftUI presents a single sheet per
    /// view, so the bar asks for one at a time by name.
    @State private var editorRequest: BookmarksBarEditorRequest?
    @State private var pendingFolderDeletion: BookmarkFolderRecord?

    private var rootFolders: [BookmarkFolderRecord] { store.bookmarkFolders(in: nil) }
    private var rootBookmarks: [BookmarkRecord] { store.bookmarks(in: nil) }
    private var isEmpty: Bool { rootFolders.isEmpty && rootBookmarks.isEmpty }
    private var canBookmarkCurrentPage: Bool { WebURLPolicy.validatedURL(currentPageURL) != nil }
    private var currentPage: CurrentPageBookmarkState {
        CurrentPageBookmarkState(canSave: canBookmarkCurrentPage, currentBookmark: currentBookmark)
    }

    private var openInNewTabAction: (String) -> Void { openInNewTab ?? open }

    private var linkActions: BookmarkBarLinkActions {
        BookmarkBarLinkActions(
            open: open,
            openInNewTab: openInNewTabAction,
            edit: { editorRequest = .bookmark(BookmarkEditorRequest(bookmark: $0)) },
            move: { store.moveBookmark($0, to: $1) },
            delete: { store.removeBookmark($0) }
        )
    }

    private var folderActions: BookmarkBarFolderActions {
        BookmarkBarFolderActions(
            openAll: openAll(in:),
            addCurrentPage: addCurrentPage,
            newSubfolder: newFolder,
            rename: { folder in
                editorRequest = .folder(
                    BookmarkFolderEditorRequest(
                        folderID: folder.id,
                        parentID: folder.parentID,
                        title: folder.title,
                        iconID: ClearframeIconGeometry.iconID(for: folder),
            colorID: folder.colorID,
                    )
                )
            },
            delete: requestFolderDeletion(_:),
            organize: openAllBookmarks
        )
    }

    var body: some View {
        HStack(spacing: BookmarkBarMetrics.itemGap) {
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
                    .padding(.horizontal, BookmarkBarMetrics.itemPadding)
                }
                .buttonStyle(.plain)
                .help("Open all bookmarks")
                .accessibilityHint("Opens the full bookmarks page where you can create folders and organize saved pages.")
                Spacer(minLength: 0)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: BookmarkBarMetrics.itemGap) {
                        let destinations = BookmarkFolderDestination.tree(in: store)
                        ForEach(rootFolders) { folder in
                            BookmarkFolderMenu(
                                store: store,
                                folder: folder,
                                compact: true,
                                currentPage: currentPage,
                                open: open,
                                fileDroppedURL: fileDroppedURL,
                                reportDrop: reportDrop,
                                actions: folderActions
                            )
                        }
                        if !rootFolders.isEmpty && !rootBookmarks.isEmpty {
                            barSeparator
                        }
                        ForEach(rootBookmarks) { bookmark in
                            BookmarkBarLink(
                                bookmark: bookmark,
                                destinations: destinations,
                                actions: linkActions
                            )
                        }
                    }
                }
                .accessibilityLabel("Bookmarks bar")
            }

            barSeparator
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
                            currentPage: currentPage,
                            open: open,
                            fileDroppedURL: fileDroppedURL,
                            reportDrop: reportDrop,
                            actions: folderActions
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
                            Label("Add current page", systemImage: "bookmark.badge.plus")
                        }
                    } else {
                        Text("Current page is bookmarked")
                    }
                }
                Button { newFolder(nil) } label: {
                    Label("New folder…", systemImage: "folder.badge.plus")
                }
                Button { openAllBookmarks() } label: {
                    Label("All bookmarks…", systemImage: "books.vertical")
                }
                Button { store.showsBookmarksBar = false } label: {
                    Label("Hide bookmarks bar", systemImage: "eye.slash")
                }
            } label: {
                // The design's quiet overflow glyph: no chip, no caret, just
                // a chevron pair. The accessible name carries the meaning.
                Text("»")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ClearframeTheme.textTertiary)
                    .frame(width: 18, height: BookmarkBarMetrics.itemHeight)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
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
        .padding(.horizontal, 9)
        .frame(height: BookmarkBarMetrics.barHeight)
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
                        Label("Add current page", systemImage: "bookmark.badge.plus")
                    }
                } else {
                    Button("Current page is bookmarked") {}.disabled(true)
                }
                Divider()
            }
            Button { newFolder(nil) } label: {
                Label("New folder…", systemImage: "folder.badge.plus")
            }
            Button { openAllBookmarks() } label: {
                Label("All bookmarks…", systemImage: "books.vertical")
            }
            Divider()
            Button { store.showsBookmarksBar = false } label: {
                Label("Hide bookmarks bar", systemImage: "eye.slash")
            }
        }
        .help("Drop a page link here to save it in Unfiled. Secondary-click or Control-click for more actions.")
        .sheet(item: $editorRequest) { request in
            switch request {
            case .bookmark(let bookmarkRequest):
                BookmarkEditor(request: bookmarkRequest) { title, url in
                    store.updateBookmark(id: bookmarkRequest.bookmarkID, title: title, url: url)
                }
            case .folder(let folderRequest):
                BookmarkFolderEditor(request: folderRequest) { title, iconID, colorID in
                    if let folderID = folderRequest.folderID {
                        store.updateBookmarkFolder(id: folderID, title: title, iconID: iconID, colorID: colorID)
                    }
                    editorRequest = nil
                }
            }
        }
        .alert(
            "Delete folder?",
            isPresented: Binding(
                get: { pendingFolderDeletion != nil },
                set: { if !$0 { pendingFolderDeletion = nil } }
            ),
            presenting: pendingFolderDeletion
        ) { folder in
            Button("Delete folder", role: .destructive) {
                store.deleteBookmarkFolderPreservingContents(folder)
                pendingFolderDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingFolderDeletion = nil }
        } message: { folder in
            Text("\(folder.title) contains saved items. Its bookmarks and subfolders will move to the parent folder; nothing will be deleted.")
        }
    }

    /// Hairline between two runs of bar items — folders and loose bookmarks,
    /// and the row and its trailing controls.
    private var barSeparator: some View {
        Rectangle()
            .fill(ClearframeTheme.hairline2)
            .frame(width: 1, height: 14)
            .padding(.horizontal, 3)
            .accessibilityHidden(true)
    }

    private func openAll(in folder: BookmarkFolderRecord) {
        for bookmark in store.bookmarks(in: folder.id) {
            openInNewTabAction(bookmark.url)
        }
    }

    /// A folder that still holds something asks first; its contents survive
    /// either way, moving up to the parent folder.
    private func requestFolderDeletion(_ folder: BookmarkFolderRecord) {
        if store.bookmarkFolderContainsItems(folder) {
            pendingFolderDeletion = folder
        } else {
            store.deleteBookmarkFolderPreservingContents(folder)
        }
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

/// Which editor the bar is showing: renaming a folder chip and editing a
/// saved page share one sheet slot.
private enum BookmarksBarEditorRequest: Identifiable {
    case bookmark(BookmarkEditorRequest)
    case folder(BookmarkFolderEditorRequest)

    var id: UUID {
        switch self {
        case .bookmark(let request): return request.id
        case .folder(let request): return request.id
        }
    }
}

/// What every bar bookmark can do, gathered once in `BookmarksBar` so each
/// item's menu drives exactly the same code.
private struct BookmarkBarLinkActions {
    let open: (String) -> Void
    let openInNewTab: (String) -> Void
    let edit: (BookmarkRecord) -> Void
    let move: (BookmarkRecord, UUID?) -> Void
    let delete: (BookmarkRecord) -> Void
}

/// The same, for the bar's folder chips.
private struct BookmarkBarFolderActions {
    let openAll: (BookmarkFolderRecord) -> Void
    let addCurrentPage: (UUID?) -> Void
    let newSubfolder: (UUID?) -> Void
    let rename: (BookmarkFolderRecord) -> Void
    let delete: (BookmarkFolderRecord) -> Void
    let organize: () -> Void
}

/// Trailing bar item that opens the full-page bookmarks home. Same borderless
/// language as the link and folder items beside it (B4): folder glyph plus
/// name, no chip until hovered.
private struct BookmarksBarAllChip: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: BookmarkBarMetrics.iconGap) {
                Image(systemName: "folder")
                    .font(.system(size: 10, weight: .medium))
                Text("All bookmarks")
                    .lineLimit(1)
            }
            .font(.system(size: BookmarkBarMetrics.labelFontSize, weight: .medium))
            .foregroundStyle(isHovered ? ClearframeTheme.textPrimary : ClearframeTheme.textSecondary)
            .padding(.horizontal, BookmarkBarMetrics.itemPadding)
            .frame(height: BookmarkBarMetrics.itemHeight)
            .background(
                isHovered ? ClearframeTheme.itemHover : Color.clear,
                in: RoundedRectangle(cornerRadius: ClearframeTheme.radius6)
            )
            .frame(height: BookmarkBarMetrics.barHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { isHovered = $0 }
        .help("Open all bookmarks (⌘⌥B)")
        .accessibilityLabel("All bookmarks")
        .accessibilityHint("Opens the full bookmarks page with every folder and saved page.")
    }
}

private struct BookmarkBarLink: View {
    let bookmark: BookmarkRecord
    let destinations: [BookmarkFolderDestination]
    let actions: BookmarkBarLinkActions
    @State private var isHovered = false

    private static let iconWidth: CGFloat = 13

    @ViewBuilder
    var body: some View {
        if let url = BookmarkURLPolicy.validatedURL(bookmark.url) {
            linkButton.draggable(url)
        } else {
            linkButton
        }
    }

    private var linkButton: some View {
        Button { actions.open(bookmark.url) } label: {
            HStack(spacing: BookmarkBarMetrics.iconGap) {
                // A real icon once this site has been visited; the site's
                // identity square until then.
                SiteIconView(urlString: bookmark.url, size: Self.iconWidth)
                Text(bookmark.title)
                    .foregroundStyle(isHovered ? ClearframeTheme.textPrimary : ClearframeTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.system(size: BookmarkBarMetrics.labelFontSize, weight: .medium))
            .padding(.horizontal, BookmarkBarMetrics.itemPadding)
            .frame(
                width: BookmarkBarMetrics.cappedWidth(label: bookmark.title, iconWidth: Self.iconWidth),
                height: BookmarkBarMetrics.itemHeight,
                alignment: .leading
            )
            .background(
                isHovered ? ClearframeTheme.itemHover : Color.clear,
                in: RoundedRectangle(cornerRadius: ClearframeTheme.radius6)
            )
            .frame(height: BookmarkBarMetrics.barHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { isHovered = $0 }
        .help("Open \(bookmark.title) — \(bookmark.url)")
        .accessibilityHint("Opens this bookmark in the current tab. Drag it onto a visible folder to move it. Secondary-click for edit, move, and delete.")
        .contextMenu {
            BookmarkLinkMenuItems(
                bookmark: bookmark,
                destinations: destinations,
                open: { actions.open(bookmark.url) },
                openInNewTab: { actions.openInNewTab(bookmark.url) },
                edit: { actions.edit(bookmark) },
                move: { actions.move(bookmark, $0) },
                delete: { actions.delete(bookmark) }
            )
        }
    }
}

private struct BookmarkFolderMenu: View {
    @ObservedObject var store: BrowserDataStore
    let folder: BookmarkFolderRecord
    let compact: Bool
    let currentPage: CurrentPageBookmarkState
    let open: (String) -> Void
    let fileDroppedURL: (URL, UUID?) -> BookmarkDropResult?
    let reportDrop: (BookmarkDropResult, String) -> Void
    let actions: BookmarkBarFolderActions
    @State private var isDropTargeted = false
    @State private var isHovered = false

    private var chipFill: Color {
        if isDropTargeted { return ClearframeTheme.accentDimStrong }
        return isHovered ? ClearframeTheme.itemHover : Color.clear
    }

    /// Saved pages filed directly in this folder — what "Open all" opens and
    /// what the number in its title counts.
    private var directBookmarks: [BookmarkRecord] { store.bookmarks(in: folder.id) }

    /// Exactly as wide as this folder's own name, capped at
    /// `maximumItemWidth`. A borderless `Menu` hands its label to AppKit as a
    /// plain title and draws none of the label's own padding, fill, or color,
    /// so the chip is drawn in an overlay and the menu underneath is given a
    /// clear label at this measured width. That is what makes a chip hug: the
    /// number is the name's real width, known before the first frame is drawn
    /// rather than fed back from a layout pass.
    private var chipWidth: CGFloat {
        BookmarkBarMetrics.naturalWidth(
            label: folder.title,
            iconWidth: BookmarkBarMetrics.folderIconSize
        )
    }

    @ViewBuilder
    var body: some View {
        if compact {
            Menu { menuContents } label: {
                Color.clear.frame(width: chipWidth, height: BookmarkBarMetrics.barHeight)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .overlay { chipLabel }
            .frame(width: chipWidth, height: BookmarkBarMetrics.barHeight)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first, let result = fileDroppedURL(url, folder.id) else { return false }
                reportDrop(result, folder.title)
                return true
            } isTargeted: { isDropTargeted = $0 }
            .help("Open \(folder.title) folder")
            .accessibilityLabel("\(folder.title) bookmark folder")
            .accessibilityHint("Opens this folder. Drop a page link or saved bookmark here to file it in this folder. Secondary-click for folder actions.")
            .contextMenu { folderMenuItems }
        } else {
            Menu(folder.barLabel) { menuContents }
                .help("Open \(folder.title) folder")
                .accessibilityLabel("\(folder.title) bookmark folder")
        }
    }

    /// No caret: the design's folder items are a glyph and a name. It is still
    /// a Menu — only the chevron goes. Never hit-tested, so every click and
    /// drag lands on the menu it decorates.
    private var chipLabel: some View {
        HStack(spacing: BookmarkBarMetrics.iconGap) {
            BookmarkFolderIcon(folder: folder, size: BookmarkBarMetrics.folderIconSize)
            Text(folder.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .font(.system(size: BookmarkBarMetrics.labelFontSize, weight: .medium))
        }
            .foregroundStyle(isHovered ? ClearframeTheme.textPrimary : ClearframeTheme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, BookmarkBarMetrics.itemPadding)
            .frame(width: chipWidth, height: BookmarkBarMetrics.itemHeight)
            .background(chipFill, in: RoundedRectangle(cornerRadius: ClearframeTheme.radius6))
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: ClearframeTheme.radius6)
                        .stroke(ClearframeTheme.accent, lineWidth: 1.5)
                }
            }
            .allowsHitTesting(false)
    }

    private var folderMenuItems: some View {
        BookmarkFolderMenuItems(
            folder: folder,
            bookmarkCount: directBookmarks.count,
            currentPage: currentPage,
            openAll: { actions.openAll(folder) },
            addCurrentPage: { actions.addCurrentPage(folder.id) },
            newSubfolder: { actions.newSubfolder(folder.id) },
            rename: { actions.rename(folder) },
            delete: { actions.delete(folder) },
            organize: actions.organize
        )
    }

    private var menuContents: some View {
        BookmarkFolderMenuContents(
            store: store,
            folder: folder,
            currentPage: currentPage,
            open: open,
            fileDroppedURL: fileDroppedURL,
            reportDrop: reportDrop,
            actions: actions
        )
    }
}

private struct BookmarkFolderMenuContents: View {
    @ObservedObject var store: BrowserDataStore
    let folder: BookmarkFolderRecord
    let currentPage: CurrentPageBookmarkState
    let open: (String) -> Void
    let fileDroppedURL: (URL, UUID?) -> BookmarkDropResult?
    let reportDrop: (BookmarkDropResult, String) -> Void
    let actions: BookmarkBarFolderActions

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
                    currentPage: currentPage,
                    open: open,
                    fileDroppedURL: fileDroppedURL,
                    reportDrop: reportDrop,
                    actions: actions
                )
            }
            if !childFolders.isEmpty && !bookmarks.isEmpty { Divider() }
            ForEach(bookmarks) { bookmark in
                Button { open(bookmark.url) } label: { Label(bookmark.title, systemImage: "bookmark") }
            }
        }
        Divider()
        Button(BookmarkMenuCopy.openAll(count: bookmarks.count)) { actions.openAll(folder) }
            .disabled(bookmarks.isEmpty)
        Button("New subfolder…") { actions.newSubfolder(folder.id) }
    }
}
