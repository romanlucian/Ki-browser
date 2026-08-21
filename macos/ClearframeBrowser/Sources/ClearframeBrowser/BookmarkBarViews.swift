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
    static let folderIconSize: CGFloat = ClearframeTheme.siteIconSize

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
    @Environment(\.openWindow) private var openWindow
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
            delete: { store.removeBookmark($0) },
            openInNewWindow: { BookmarkWindowOpener.open([$0.url], isPrivate: false, using: openWindow) },
            openInPrivateWindow: { BookmarkWindowOpener.open([$0.url], isPrivate: true, using: openWindow) },
            dropAtPlace: { url, target in placeDroppedURL(url, before: target) }
        )
    }

    /// Puts a dragged address where it was dropped on the bar.
    ///
    /// An address already saved moves to that place. One arriving from
    /// somewhere else — the address field's own chip, a link from a page — is
    /// saved into the same folder as the bookmark it landed on and takes that
    /// place, rather than going to the end where it would have to be found and
    /// dragged back.
    private func placeDroppedURL(_ url: URL, before target: BookmarkRecord) -> Bool {
        guard let normalized = BookmarkURLPolicy.validatedURL(url.absoluteString) else { return false }
        let siblings = store.bookmarks(in: target.folderID)
        guard let index = siblings.firstIndex(where: { $0.id == target.id }) else { return false }

        if let existing = store.bookmarks.first(where: { $0.url == normalized.absoluteString }) {
            guard existing.id != target.id else { return false }
            if existing.folderID != target.folderID {
                store.moveBookmark(existing, to: target.folderID)
            }
            store.moveBookmark(existing.id, toIndex: index)
            let moved = store.bookmarks.first { $0.id == existing.id } ?? existing
            reportDrop(
                BookmarkDropResult(bookmark: moved, disposition: .moved),
                folderName: folderName(target.folderID)
            )
            return true
        }

        guard let result = fileDroppedURL(url, target.folderID),
              let saved = store.bookmarks.first(where: { $0.url == normalized.absoluteString })
        else { return false }
        store.moveBookmark(saved.id, toIndex: index)
        reportDrop(result, folderName: folderName(target.folderID))
        return true
    }

    /// Puts a dragged folder where the folder it was dropped on sits. A folder
    /// only moves among its own siblings: dropping one from inside a folder
    /// onto a folder on the bar would be a move to a different level, which is
    /// what the Move menu is for.
    private func placeDroppedFolder(_ draggedID: UUID, before target: BookmarkFolderRecord) -> Bool {
        guard draggedID != target.id,
              let dragged = store.bookmarkFolders.first(where: { $0.id == draggedID }),
              dragged.parentID == target.parentID
        else { return false }
        let siblings = store.bookmarkFolders(in: target.parentID)
        guard let index = siblings.firstIndex(where: { $0.id == target.id }) else { return false }
        store.moveFolder(draggedID, toIndex: index)
        return true
    }

    private func folderName(_ folderID: UUID?) -> String {
        guard let folderID else { return "Unfiled" }
        return store.bookmarkFolders.first { $0.id == folderID }?.title ?? "Unfiled"
    }

    private var folderActions: BookmarkBarFolderActions {
        BookmarkBarFolderActions(
            reorder: { dragged, target in placeDroppedFolder(dragged, before: target) },
            openAll: openAll(in:),
            openAllInNewWindow: { folder in
                BookmarkWindowOpener.open(
                    store.bookmarks(in: folder.id).map(\.url),
                    isPrivate: false,
                    using: openWindow
                )
            },
            openAllInPrivateWindow: { folder in
                BookmarkWindowOpener.open(
                    store.bookmarks(in: folder.id).map(\.url),
                    isPrivate: true,
                    using: openWindow
                )
            },
            addCurrentPage: addCurrentPage,
            newSubfolder: newFolder,
            rename: { folder in
                editorRequest = .folder(
                    BookmarkFolderEditorRequest(
                        folderID: folder.id,
                        parentID: folder.parentID,
                        title: folder.title,
                        iconID: ClearframeIconGeometry.iconID(for: folder),
                        colorID: folder.colorID
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
                    .frame(width: 18, height: BookmarkBarMetrics.barHeight)
                    .contentShape(Rectangle())
            }
            // As with the folder chips: `.borderlessButton` flattens this label
            // into a plain control title, discarding the frame and the colour
            // it names, and leaves a hit target the size of the glyph rather
            // than the bar row. `.menuStyle(.button)` keeps the label a label.
            .buttonStyle(.plain)
            .menuStyle(.button)
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
/// Makes a folder chip draggable without changing what it looks like.
private struct DraggableFolder: ViewModifier {
    let folder: BookmarkFolderRecord

    func body(content: Content) -> some View {
        if let payload = BookmarkDragPayload.folderURL(folder.id) {
            content.draggable(payload)
        } else {
            content
        }
    }
}

private struct BookmarkBarLinkActions {
    let open: (String) -> Void
    let openInNewTab: (String) -> Void
    let edit: (BookmarkRecord) -> Void
    let move: (BookmarkRecord, UUID?) -> Void
    let delete: (BookmarkRecord) -> Void
    let openInNewWindow: (BookmarkRecord) -> Void
    let openInPrivateWindow: (BookmarkRecord) -> Void
    /// Drops a dragged address at this bookmark's place in the bar, so the bar
    /// can be put in the order somebody wants rather than the order things
    /// were saved. Reports whether it landed.
    let dropAtPlace: (URL, BookmarkRecord) -> Bool
}

/// The same, for the bar's folder chips.
private struct BookmarkBarFolderActions {
    /// Puts the dragged folder where the one it was dropped on sits. Reports
    /// whether it landed.
    let reorder: (UUID, BookmarkFolderRecord) -> Bool
    let openAll: (BookmarkFolderRecord) -> Void
    let openAllInNewWindow: (BookmarkFolderRecord) -> Void
    let openAllInPrivateWindow: (BookmarkFolderRecord) -> Void
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
    @State private var isDropTargeted = false

    private static let iconWidth: CGFloat = ClearframeTheme.siteIconSize

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
        // Dropping one bookmark on another puts it in that place. The same
        // drag that files a bookmark into a folder therefore also arranges the
        // bar, rather than there being two different gestures to learn.
        .dropDestination(for: URL.self) { urls, _ in
            // A folder dropped on a bookmark is declined: folders and saved
            // pages are two rows on this bar, and a folder's place is among
            // the other folders.
            guard let url = urls.first, BookmarkDragPayload.folderID(from: url) == nil else { return false }
            return actions.dropAtPlace(url, bookmark)
        } isTargeted: { isDropTargeted = $0 }
        .overlay(alignment: .leading) {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 1)
                    .fill(ClearframeTheme.accent)
                    .frame(width: 2)
                    .padding(.vertical, 4)
            }
        }
        .help("Open \(bookmark.title) — \(bookmark.url)")
        .accessibilityHint("Opens this bookmark in the current tab. Drag it along the bar to reorder it, or onto a visible folder to move it into it. Secondary-click for edit, move, and delete.")
        .contextMenu {
            BookmarkLinkMenuItems(
                bookmark: bookmark,
                destinations: destinations,
                open: { actions.open(bookmark.url) },
                openInNewTab: { actions.openInNewTab(bookmark.url) },
                openInNewWindow: { actions.openInNewWindow(bookmark) },
                openInPrivateWindow: { actions.openInPrivateWindow(bookmark) },
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
    /// `maximumItemWidth`. The number is the name's real width, known before
    /// the first frame is drawn rather than fed back from a layout pass, which
    /// is what makes a chip hug its own label.
    private var chipWidth: CGFloat {
        BookmarkBarMetrics.naturalWidth(
            label: folder.title,
            iconWidth: BookmarkBarMetrics.folderIconSize
        )
    }

    @ViewBuilder
    var body: some View {
        if compact {
            // The chip is the menu's own label, not an overlay on top of one.
            //
            // It used to be drawn over a `Menu` whose label was a clear
            // rectangle at the chip's width, under `.menuStyle(.borderlessButton)`.
            // That style does not host a SwiftUI label inside the control — it
            // flattens the label into an `NSPopUpButton`'s title and image, so
            // a clear rectangle became an empty title and the control collapsed
            // to the intrinsic size of the menu indicator. Measured on this
            // machine: an 11x14 point control inside a 110x28 chip, under six
            // per cent of what a reader is aiming at, which is why opening a
            // folder worked only when a click happened to land in the middle of
            // its name. Hover, drop, and secondary-click all hung off the outer
            // wrapper and covered the whole chip, so the chip lit up under the
            // pointer and invited clicks that then did nothing.
            //
            // `.menuStyle(.button)` hosts the label instead of flattening it,
            // and creates no AppKit control at all, so the hit region is the
            // label's own `contentShape` — the chip exactly.
            Menu { menuContents } label: {
                chipLabel
                    .frame(width: chipWidth, height: BookmarkBarMetrics.barHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            .onHover { isHovered = $0 }
            .modifier(DraggableFolder(folder: folder))
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                // A folder landing on a folder means "put it here"; anything
                // else means "file this page in this folder".
                if let dragged = BookmarkDragPayload.folderID(from: url) {
                    return actions.reorder(dragged, folder)
                }
                guard let result = fileDroppedURL(url, folder.id) else { return false }
                reportDrop(result, folder.title)
                return true
            } isTargeted: { isDropTargeted = $0 }
            .help("Open \(folder.title) folder")
            .accessibilityLabel("\(folder.title) bookmark folder")
            .accessibilityHint("Opens this folder. Drop a page link or saved bookmark here to file it in this folder. Secondary-click for folder actions.")
            .contextMenu { folderMenuItems }
        } else {
            // A subfolder inside a dropdown. It carries a folder mark for the
            // same reason the saved pages beside it carry their site icons:
            // a column of bare text gives the eye nothing to sort by.
            Menu {
                menuContents
            } label: {
                Label(folder.barLabel, systemImage: "folder")
            }
            .help("Open \(folder.title) folder")
            .accessibilityLabel("\(folder.title) bookmark folder")
        }
    }

    /// No caret: the design's folder items are a glyph and a name. It is still
    /// a Menu — only the chevron goes. This is the menu's label rather than a
    /// decoration over it, so it must stay hit-testable: it is what a click
    /// lands on.
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
    }

    private var folderMenuItems: some View {
        BookmarkFolderMenuItems(
            folder: folder,
            bookmarkCount: directBookmarks.count,
            currentPage: currentPage,
            openAll: { actions.openAll(folder) },
            openAllInNewWindow: { actions.openAllInNewWindow(folder) },
            openAllInPrivateWindow: { actions.openAllInPrivateWindow(folder) },
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
                Button { open(bookmark.url) } label: {
                    BookmarkMenuRow(title: bookmark.title, url: bookmark.url)
                }
            }
        }
        Divider()
        Button(BookmarkMenuCopy.openAll(count: bookmarks.count)) { actions.openAll(folder) }
            .disabled(bookmarks.isEmpty)
        Button("New subfolder…") { actions.newSubfolder(folder.id) }
    }
}
