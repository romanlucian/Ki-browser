import LimeghostCore
import SwiftUI

/// The full-page bookmarks home (⌘⌥B, the bookmarks bar's "All bookmarks"
/// chip, and the bar's organize actions). It shows the same local records the
/// bookmarks bar and the toolbar's quick library popover show — this is a
/// second, roomier view of one store, never a second copy of the data.
///
/// Deliberately excluded from the imported design concept, because nothing in
/// Limeghost backs them today: tags, a reading list, tracker charts or
/// blocked-request counts (WebKit cannot report per-page counts), the floating
/// bottom glass toolbar, the phone layout, a `halo://` scheme, and "SHARED"
/// badges. Adding any of them would mean inventing state the browser does not
/// have.
struct BookmarksHomePage: View {
    @ObservedObject var store: BrowserDataStore
    let open: (String, Bool) -> Void

    @State private var search = ""
    @State private var currentFolderID: UUID?
    /// Which branches of the sidebar tree are open.
    ///
    /// Held here rather than inside a `DisclosureGroup` so the page can open a
    /// path it did not open itself — picking a folder out of search results has
    /// to reveal where that folder actually lives.
    @State private var expandedFolderIDs: Set<UUID> = []
    @State private var editorRequest: BookmarkFolderEditorRequest?
    @State private var bookmarkEditorRequest: BookmarkEditorRequest?
    @State private var pendingDeletion: BookmarkFolderRecord?
    @State private var dropConfirmation: String?
    @State private var showsBookmarkImport = false

    private var trimmedSearch: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool { !trimmedSearch.isEmpty }

    var body: some View {
        // One rolled-up pass per render: every card and row below reads its
        // counts out of this snapshot instead of walking the tree itself.
        let stats = BookmarksHomeStats(store: store)
        HStack(spacing: 0) {
            sidebar(stats: stats)
            Rectangle()
                .fill(LimeghostTheme.hairline1)
                .frame(width: 1)
            content(stats: stats)
        }
        .background(LimeghostTheme.bg0)
        .sheet(item: $editorRequest) { request in
            BookmarkFolderEditor(request: request) { title, iconID, colorID in
                if let folderID = request.folderID {
                    store.updateBookmarkFolder(id: folderID, title: title, iconID: iconID, colorID: colorID)
                } else {
                    _ = store.createBookmarkFolder(title: title, iconID: iconID, colorID: colorID, parentID: request.parentID)
                }
                editorRequest = nil
            }
        }
        .alert(
            "Delete folder?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { folder in
            Button("Delete folder", role: .destructive) {
                store.deleteBookmarkFolderPreservingContents(folder)
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { folder in
            Text("\(folder.title) contains saved items. Its bookmarks and subfolders will move to the parent folder; nothing will be deleted.")
        }
        .sheet(isPresented: $showsBookmarkImport) {
            // Already the surface a completed import would open — no further
            // navigation needed once the sheet closes.
            BookmarkImportSheet(store: store) { _ in showsBookmarkImport = false }
        }
        .accessibilityLabel("All bookmarks")
    }

    // MARK: - Sidebar

    private func sidebar(stats: BookmarksHomeStats) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BOOKMARKS")
                .font(LimeghostTheme.metaFont)
                .tracking(LimeghostTheme.metaTracking)
                .foregroundStyle(LimeghostTheme.textTertiary)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

            Text("\(store.bookmarks.count) saved \(store.bookmarks.count == 1 ? "page" : "pages")")
                .font(.system(size: 12))
                .foregroundStyle(LimeghostTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)

            folderTree(stats: stats)

            Spacer(minLength: 12)

            // The visible way in when someone lands here realizing their
            // bookmarks are missing — bringing them from another browser, or
            // taking Limeghost's with them, in one click from the surface
            // where that decision actually comes up.
            VStack(alignment: .leading, spacing: 2) {
                sidebarActionRow("Import Bookmarks…", symbol: "square.and.arrow.down") {
                    showsBookmarkImport = true
                }
                sidebarActionRow("Export Bookmarks…", symbol: "square.and.arrow.up") {
                    BookmarkExportCommand.run(store: store)
                }
            }
            .padding(.bottom, 4)

            Label("Stored only in this Mac user profile.", systemImage: "lock")
                .font(.system(size: 10.5))
                .foregroundStyle(LimeghostTheme.textTertiary)
                .padding(.horizontal, 10)
        }
        .padding(.vertical, 22)
        // Wider than history's 210. The two pages otherwise keep an identical
        // sidebar on purpose, but this one now holds a tree: at 210 a folder
        // two levels down loses its name to the truncation before the count.
        .frame(width: 250, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(LimeghostTheme.bg1)
    }

    /// The hierarchy, where a hierarchy belongs.
    ///
    /// This page used to be a drill-down: one folder at a time, a back arrow,
    /// and — to compensate for having no sense of place — a grid of cards for
    /// the top level *and* a flat alphabetical list of all 96 folders below it,
    /// showing the same folders twice under two different counts. Four levels
    /// deep, the only way to know where you were was to press back and look.
    ///
    /// A tree answers that by being one. Collapsed, the founder's collection is
    /// eleven rows instead of ninety-six.
    private func folderTree(stats: BookmarksHomeStats) -> some View {
        let rows = BookmarkTree.rows(
            folders: store.bookmarkFolders,
            bookmarks: store.bookmarks,
            expanded: expandedFolderIDs
        )
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                BookmarkTreeRowView(
                    title: "All bookmarks",
                    depth: 0,
                    disclosure: .none,
                    count: nil,
                    folder: nil,
                    isSelected: currentFolderID == nil,
                    select: { currentFolderID = nil },
                    toggle: {}
                )
                ForEach(rows) { row in
                    BookmarkTreeRowView(
                        title: row.folder.title,
                        depth: row.depth,
                        disclosure: row.hasChildren ? (row.isExpanded ? .open : .closed) : .none,
                        count: row.directBookmarkCount,
                        folder: row.folder,
                        isSelected: currentFolderID == row.folder.id,
                        select: {
                            search = ""
                            currentFolderID = row.folder.id
                        },
                        toggle: {
                            if expandedFolderIDs.contains(row.folder.id) {
                                expandedFolderIDs.remove(row.folder.id)
                            } else {
                                expandedFolderIDs.insert(row.folder.id)
                            }
                        },
                        openAll: { openAll(in: row.folder, stats: stats) },
                        newSubfolder: {
                            editorRequest = BookmarkFolderEditorRequest(
                                folderID: nil,
                                parentID: row.folder.id,
                                title: "",
                                iconID: LimeghostIconCatalog.defaultIconID,
                                colorID: nil
                            )
                        },
                        edit: { presentRename(row.folder) },
                        delete: { requestDeletion(row.folder) },
                        fileDroppedURL: { fileDroppedURL($0, to: row.folder) }
                    )
                }
            }
            .padding(.horizontal, 6)
        }
        .frame(maxHeight: .infinity)
    }

    /// Opens the branch a folder lives in and selects it.
    ///
    /// What a search result has to do: selecting a folder buried three levels
    /// down would otherwise put the selection inside a collapsed parent, and
    /// the click would appear to do nothing at all.
    private func reveal(_ folderID: UUID) {
        expandedFolderIDs.formUnion(BookmarkTree.ancestors(of: folderID, in: store.bookmarkFolders))
        search = ""
        currentFolderID = folderID
    }

    private func sidebarActionRow(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 15)
                Text(title)
                    .font(.system(size: 12))
                Spacer(minLength: 6)
            }
            .foregroundStyle(LimeghostTheme.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .accessibilityLabel(title)
    }

    // MARK: - Main column

    private func content(stats: BookmarksHomeStats) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(stats: stats)
                HomeSearchField(placeholder: "Search saved pages and folders", text: $search)
                folderGrid(stats: stats)
                bookmarkSection(stats: stats)
            }
            .frame(maxWidth: 1_020, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $bookmarkEditorRequest) { request in
            BookmarkEditor(request: request) { title, url in
                store.updateBookmark(id: request.bookmarkID, title: title, url: url)
            }
        }
    }

    private func header(stats: BookmarksHomeStats) -> some View {
        let folder = currentFolderID.flatMap { stats.folder(id: $0) }
        return VStack(alignment: .leading, spacing: 8) {
            if let folder {
                breadcrumb(to: folder)
            }
            HStack(spacing: 10) {
                Text(headerTitle(folder: folder))
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(LimeghostTheme.textPrimary)
                Spacer(minLength: 8)
                if let dropConfirmation {
                    Label(dropConfirmation, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(LimeghostTheme.accent)
                        .lineLimit(1)
                        .transition(.opacity)
                        .accessibilityLabel(dropConfirmation)
                }
            }
            Text(headerDetail(folder: folder, stats: stats))
                .font(.system(size: 12))
                .foregroundStyle(LimeghostTheme.textTertiary)
        }
    }

    /// Root › … › this folder, every step of it a button.
    ///
    /// It replaces a single back arrow, which could only ever say "up one".
    /// The founder's collection runs four levels deep, so getting back to the
    /// top was three presses and a guess about where you would land.
    private func breadcrumb(to folder: BookmarkFolderRecord) -> some View {
        let path = BookmarkTree.path(to: folder.id, in: store.bookmarkFolders)
        return HStack(spacing: 4) {
            Button("All bookmarks") { currentFolderID = nil }
                .buttonStyle(.plain)
                .foregroundStyle(LimeghostTheme.textTertiary)
            ForEach(path.dropLast()) { step in
                Text("›").foregroundStyle(LimeghostTheme.textTertiary)
                Button(step.title) { reveal(step.id) }
                    .buttonStyle(.plain)
                    .foregroundStyle(LimeghostTheme.textTertiary)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 11))
        .accessibilityLabel("Path: " + path.map(\.title).joined(separator: ", "))
    }

    private func headerTitle(folder: BookmarkFolderRecord?) -> String {
        guard let folder else { return "Bookmarks" }
        return folder.title
    }

    private func headerDetail(folder: BookmarkFolderRecord?, stats: BookmarksHomeStats) -> String {
        if isSearching { return "Searching every folder by page title, web address, and folder name." }
        guard let folder else {
            return "Folders and saved pages in this Mac user profile. Drop a page link onto a folder to file it."
        }
        let pages = stats.directBookmarkCount(for: folder.id)
        let folders = stats.folders(in: folder.id).count
        let pageWord = pages == 1 ? "saved page" : "saved pages"
        let folderWord = folders == 1 ? "folder" : "folders"
        return "\(pages) \(pageWord) · \(folders) \(folderWord)"
    }

    // MARK: - Folder cards

    private func visibleFolders(stats: BookmarksHomeStats) -> [BookmarkFolderRecord] {
        guard isSearching else { return stats.folders(in: currentFolderID) }
        return BookmarksHomeSearch.folders(stats.allFolders, matching: trimmedSearch)
    }

    @ViewBuilder
    private func folderGrid(stats: BookmarksHomeStats) -> some View {
        let folders = visibleFolders(stats: stats)
        VStack(alignment: .leading, spacing: 12) {
            HomeSectionTitle(title: isSearching ? "MATCHING FOLDERS" : "FOLDERS", count: folders.count)
            LazyVStack(spacing: 5) {
                ForEach(folders) { folder in
                    BookmarksHomeFolderRow(
                        folder: folder,
                        // Only while searching. A result is useless without
                        // where it lives — the old page showed matches as
                        // cards, which carried no path at all, so finding
                        // "Etsy Best" told you nothing about which of the two
                        // folders by that name you had found.
                        pathLabel: isSearching ? stats.parentPathLabel(for: folder.id) : "",
                        bookmarkCount: stats.directBookmarkCount(for: folder.id),
                        subfolderCount: stats.folders(in: folder.id).count,
                        action: { isSearching ? reveal(folder.id) : select(folder.id) },
                        openAll: { openAll(in: folder, stats: stats) },
                        newSubfolder: {
                            editorRequest = BookmarkFolderEditorRequest(
                                folderID: nil,
                                parentID: folder.id,
                                title: "",
                                iconID: LimeghostIconCatalog.defaultIconID,
                                colorID: nil
                            )
                        },
                        rename: { presentRename(folder) },
                        delete: { requestDeletion(folder) },
                        fileDroppedURL: { fileDroppedURL($0, to: folder) }
                    )
                }
            }
            if folders.isEmpty {
                HomeEmptyNote(
                    isSearching
                        ? "No folder name matches \u{201C}\(trimmedSearch)\u{201D}."
                        : "This folder has no folders inside it."
                )
            }
            if !isSearching {
                Button {
                    editorRequest = BookmarkFolderEditorRequest(
                        folderID: nil,
                        parentID: currentFolderID,
                        title: "",
                        iconID: LimeghostIconCatalog.defaultIconID,
                        colorID: nil
                    )
                } label: {
                    Label("New folder", systemImage: "folder.badge.plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(LimeghostTheme.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Selects a folder and opens its branch in the tree, so the sidebar and
    /// the contents pane never disagree about where you are.
    private func select(_ folderID: UUID) {
        expandedFolderIDs.formUnion(BookmarkTree.ancestors(of: folderID, in: store.bookmarkFolders))
        currentFolderID = folderID
    }

    // MARK: - Bookmark rows

    private func visibleBookmarks(stats: BookmarksHomeStats) -> [BookmarkRecord] {
        guard isSearching else { return stats.bookmarks(in: currentFolderID) }
        return BookmarksHomeSearch.bookmarks(store.bookmarks, matching: trimmedSearch)
    }

    @ViewBuilder
    private func bookmarkSection(stats: BookmarksHomeStats) -> some View {
        let bookmarks = visibleBookmarks(stats: stats)
        let destinations = BookmarkFolderDestination.tree(in: store)
        VStack(alignment: .leading, spacing: 12) {
            HomeSectionTitle(title: bookmarkSectionTitle, count: bookmarks.count)
            if bookmarks.isEmpty {
                HomeEmptyNote(emptyBookmarksNote)
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(bookmarks) { bookmark in
                        BookmarkOrganizerRow(
                            bookmark: bookmark,
                            destinations: destinations,
                            open: { open(bookmark.url, false) },
                            openNewTab: { open(bookmark.url, true) },
                            edit: { bookmarkEditorRequest = BookmarkEditorRequest(bookmark: bookmark) },
                            move: { store.moveBookmark(bookmark, to: $0) },
                            remove: { store.removeBookmark(bookmark) }
                        )
                    }
                }
            }
        }
    }

    private var bookmarkSectionTitle: String {
        if isSearching { return "MATCHING BOOKMARKS" }
        return currentFolderID == nil ? "UNFILED BOOKMARKS" : "SAVED IN THIS FOLDER"
    }

    private var emptyBookmarksNote: String {
        if isSearching { return "No saved page matches “\(trimmedSearch)”." }
        if currentFolderID == nil {
            return "Nothing unfiled. Use the star in the toolbar to save a page, then drop it onto a folder to file it."
        }
        return "This folder has no saved pages yet. Drop a page link onto its card to file one here."
    }


    /// Opens the folder's own saved pages, each in its own tab.
    private func openAll(in folder: BookmarkFolderRecord, stats: BookmarksHomeStats) {
        for bookmark in stats.bookmarks(in: folder.id) {
            open(bookmark.url, true)
        }
    }

    private func presentRename(_ folder: BookmarkFolderRecord) {
        editorRequest = BookmarkFolderEditorRequest(
            folderID: folder.id,
            parentID: folder.parentID,
            title: folder.title,
            iconID: LimeghostIconGeometry.iconID(for: folder),
            colorID: folder.colorID
        )
    }

    private func requestDeletion(_ folder: BookmarkFolderRecord) {
        if store.bookmarkFolderContainsItems(folder) {
            pendingDeletion = folder
        } else {
            if currentFolderID == folder.id { currentFolderID = folder.parentID }
            store.deleteBookmarkFolderPreservingContents(folder)
        }
    }

    private func fileDroppedURL(_ url: URL, to folder: BookmarkFolderRecord) -> Bool {
        guard let result = store.fileBookmarkFromDrop(url, title: nil, to: folder.id) else { return false }
        let message: String
        switch result.disposition {
        case .created: message = "Saved to \(folder.title)"
        case .moved: message = "Moved to \(folder.title)"
        case .alreadyFiled: message = "Already in \(folder.title)"
        }
        withAnimation(.easeOut(duration: 0.16)) { dropConfirmation = message }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            guard dropConfirmation == message else { return }
            withAnimation(.easeIn(duration: 0.16)) { dropConfirmation = nil }
        }
        return true
    }
}

/// Pure filters behind the bookmarks-home search field, kept separate from the
/// view so their behavior is directly testable. Matching mirrors the organizer:
/// case-insensitive `contains` on the page title and web address, plus the
/// folder title.
enum BookmarksHomeSearch {
    static func folders(_ folders: [BookmarkFolderRecord], matching query: String) -> [BookmarkFolderRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return folders }
        return folders.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    static func bookmarks(_ bookmarks: [BookmarkRecord], matching query: String) -> [BookmarkRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return bookmarks }
        return bookmarks.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || $0.url.localizedCaseInsensitiveContains(trimmed)
        }
    }
}

/// One render pass' worth of derived bookmark data. Built once at the top of
/// `BookmarksHomePage.body`: the rolled-up descendant counts come from a single
/// `LimeghostCore` pass, and the per-parent groupings replace the store's
/// per-call collection rebuilds that would otherwise run once per card or row.
private struct BookmarksHomeStats {
    private let foldersByID: [UUID: BookmarkFolderRecord]
    private let foldersByParent: [UUID?: [BookmarkFolderRecord]]
    private let bookmarksByFolder: [UUID?: [BookmarkRecord]]
    private let descendantCounts: [UUID: BookmarkDescendantCounts]
    let allFolders: [BookmarkFolderRecord]

    @MainActor
    init(store: BrowserDataStore) {
        descendantCounts = store.bookmarkDescendantCounts()

        var byID: [UUID: BookmarkFolderRecord] = [:]
        var byParent: [UUID?: [BookmarkFolderRecord]] = [:]
        for folder in store.bookmarkFolders {
            byID[folder.id] = folder
            byParent[folder.parentID, default: []].append(folder)
        }
        for key in byParent.keys {
            byParent[key]?.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }

        var byFolder: [UUID?: [BookmarkRecord]] = [:]
        for bookmark in store.bookmarks {
            byFolder[bookmark.folderID, default: []].append(bookmark)
        }
        for key in byFolder.keys {
            byFolder[key]?.sort { $0.createdAt > $1.createdAt }
        }

        foldersByID = byID
        foldersByParent = byParent
        bookmarksByFolder = byFolder
        allFolders = store.bookmarkFolders
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func folder(id: UUID) -> BookmarkFolderRecord? { foldersByID[id] }

    func folders(in parentID: UUID?) -> [BookmarkFolderRecord] { foldersByParent[parentID] ?? [] }

    func bookmarks(in folderID: UUID?) -> [BookmarkRecord] { bookmarksByFolder[folderID] ?? [] }

    func counts(for folderID: UUID) -> BookmarkDescendantCounts {
        descendantCounts[folderID] ?? BookmarkDescendantCounts()
    }

    func directBookmarkCount(for folderID: UUID) -> Int { bookmarksByFolder[folderID]?.count ?? 0 }

    func directSubfolderCount(for folderID: UUID) -> Int { foldersByParent[folderID]?.count ?? 0 }

    /// Hosts of the folder's newest direct bookmarks, for the card's identity
    /// dots. Nested bookmarks are excluded: the dots stand for what is filed
    /// here, not for the whole subtree.
    func identityHosts(for folderID: UUID, limit: Int = 3) -> [String] {
        (bookmarksByFolder[folderID] ?? [])
            .prefix(limit)
            .map { URL(string: $0.url)?.host ?? "" }
    }

    /// "Web Design › Code" for the folder itself.
    func pathLabel(for folderID: UUID) -> String {
        ancestors(of: folderID, includingSelf: true)
            .map(\.title)
            .joined(separator: " › ")
    }

    /// The same path without the folder itself; empty for a root folder.
    func parentPathLabel(for folderID: UUID) -> String {
        ancestors(of: folderID, includingSelf: false)
            .map(\.title)
            .joined(separator: " › ")
    }

    private func ancestors(of folderID: UUID, includingSelf: Bool) -> [BookmarkFolderRecord] {
        var chain: [BookmarkFolderRecord] = []
        var visited: Set<UUID> = []
        var next: UUID? = includingSelf ? folderID : foldersByID[folderID]?.parentID
        while let id = next, visited.insert(id).inserted, let folder = foldersByID[id] {
            chain.insert(folder, at: 0)
            next = folder.parentID
        }
        return chain
    }
}



/// A row in the "ALL FOLDERS" list: the folder, where it sits, its own direct
/// counts, and a chevron into it.
private struct BookmarksHomeFolderRow: View {
    let folder: BookmarkFolderRecord
    let pathLabel: String
    let bookmarkCount: Int
    let subfolderCount: Int
    let action: () -> Void
    let openAll: () -> Void
    let newSubfolder: () -> Void
    let rename: () -> Void
    let delete: () -> Void
    let fileDroppedURL: (URL) -> Bool

    @State private var isHovered = false
    @State private var isDropTargeted = false

    /// Direct children only, and said in words rather than shouted in
    /// abbreviations. The card this replaced counted the whole branch under
    /// the same label, so one folder read "39 LINKS · 17 SUBFOLDERS" as a card
    /// and "0 LINKS · 9 SUBFOLDERS" as a row, on the same screen.
    private var countLabel: String {
        let pages = bookmarkCount == 1 ? "1 page" : "\(bookmarkCount) pages"
        guard subfolderCount > 0 else { return pages }
        return "\(pages) · \(subfolderCount == 1 ? "1 folder" : "\(subfolderCount) folders")"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                BookmarkFolderIcon(folder: folder, size: LimeghostTheme.siteIconSize).foregroundStyle(LimeghostTheme.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(LimeghostTheme.textPrimary)
                        .lineLimit(1)
                    if !pathLabel.isEmpty {
                        Text(pathLabel)
                            .font(.system(size: 10.5))
                            .foregroundStyle(LimeghostTheme.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 10)
                Text(countLabel)
                    .font(LimeghostTheme.metaFont)
                    .tracking(LimeghostTheme.metaTracking)
                    .foregroundStyle(LimeghostTheme.textTertiary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(LimeghostTheme.textTertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(
                isDropTargeted
                    ? LimeghostTheme.accentDim
                    : (isHovered ? LimeghostTheme.bg2 : LimeghostTheme.bg1),
                in: RoundedRectangle(cornerRadius: LimeghostTheme.radius10)
            )
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: LimeghostTheme.radius10)
                        .stroke(LimeghostTheme.accent, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        // Filing by drag survives the move from cards to rows: it was the one
        // thing the illustration was genuinely a target for.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            return fileDroppedURL(url)
        } isTargeted: { isDropTargeted = $0 }
        .contextMenu {
            BookmarkFolderMenuItems(
                folder: folder,
                bookmarkCount: bookmarkCount,
                currentPage: nil,
                openAll: openAll,
                addCurrentPage: {},
                newSubfolder: newSubfolder,
                rename: rename,
                delete: delete,
                organize: nil
            )
        }
        .help("Open \(folder.title), or drop a page link here to file it in this folder")
        .accessibilityLabel("\(folder.title) folder, \(countLabel)")
    }
}

/// One row of the sidebar tree.
///
/// The triangle and the row are separate targets on purpose: pressing the
/// triangle opens a branch without moving you, pressing the row moves you.
/// Chrome does the same, and conflating them is how you lose your place by
/// trying to look ahead.
private struct BookmarkTreeRowView: View {
    enum Disclosure { case none, closed, open }

    let title: String
    let depth: Int
    let disclosure: Disclosure
    let count: Int?
    /// The folder this row stands for, or nil for the "All bookmarks" row,
    /// which stands for no folder and therefore carries no folder menu.
    let folder: BookmarkFolderRecord?
    let isSelected: Bool
    let select: () -> Void
    let toggle: () -> Void
    var openAll: () -> Void = {}
    var newSubfolder: () -> Void = {}
    var edit: () -> Void = {}
    var delete: () -> Void = {}
    var fileDroppedURL: (URL) -> Bool = { _ in false }

    @State private var isDropTargeted = false

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 5) {
            Group {
                if disclosure == .none {
                    Color.clear
                } else {
                    Button(action: toggle) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(LimeghostTheme.textTertiary)
                            .rotationEffect(.degrees(disclosure == .open ? 90 : 0))
                            .frame(width: 14, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(disclosure == .open ? "Collapse \(title)" : "Expand \(title)")
                }
            }
            .frame(width: 14)

            Button(action: select) {
                HStack(spacing: 6) {
                    if let folder {
                        BookmarkFolderIcon(folder: folder, size: 15)
                            .foregroundStyle(isSelected ? LimeghostTheme.accent : LimeghostTheme.textTertiary)
                    }
                    Text(title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? LimeghostTheme.textPrimary : LimeghostTheme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    // Direct pages only. The whole-branch number is one
                    // triangle away, which is the point of a tree.
                    if let count, count > 0 {
                        Text("\(count)")
                            .font(LimeghostTheme.microFont)
                            .foregroundStyle(LimeghostTheme.textTertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, CGFloat(depth) * 13)
        .padding(.horizontal, 6)
        .frame(height: 26)
        .background(
            isDropTargeted
                ? LimeghostTheme.accentDim
                : (isSelected ? LimeghostTheme.accentDim : (isHovered ? LimeghostTheme.itemHover : Color.clear)),
            in: RoundedRectangle(cornerRadius: LimeghostTheme.radius6)
        )
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: LimeghostTheme.radius6)
                    .stroke(LimeghostTheme.accent, lineWidth: 1.5)
            }
        }
        .onHover { isHovered = $0 }
        // The tree is a drop target too. A row you can see but cannot drop on
        // is the more annoying half of a tree — the sidebar is exactly where
        // you can see the destination while dragging from the pane beside it.
        .dropDestination(for: URL.self) { urls, _ in
            guard folder != nil, let url = urls.first else { return false }
            return fileDroppedURL(url)
        } isTargeted: { isDropTargeted = folder == nil ? false : $0 }
        .contextMenu {
            if let folder {
                BookmarkFolderMenuItems(
                    folder: folder,
                    bookmarkCount: count ?? 0,
                    currentPage: nil,
                    openAll: openAll,
                    addCurrentPage: {},
                    newSubfolder: newSubfolder,
                    rename: edit,
                    delete: delete,
                    organize: nil
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
