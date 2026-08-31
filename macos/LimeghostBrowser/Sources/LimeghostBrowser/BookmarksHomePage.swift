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
            sidebar
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LIBRARY")
                .font(LimeghostTheme.metaFont)
                .tracking(LimeghostTheme.metaTracking)
                .foregroundStyle(LimeghostTheme.textTertiary)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

            Text("\(store.bookmarks.count) saved \(store.bookmarks.count == 1 ? "page" : "pages")")
                .font(.system(size: 12))
                .foregroundStyle(LimeghostTheme.textSecondary)
                .padding(.horizontal, 10)

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
        .frame(width: 210, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(LimeghostTheme.bg1)
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
                // The flat index belongs to the root page; a drill-down
                // stays about the one folder the reader opened.
                if currentFolderID == nil {
                    allFoldersSection(stats: stats)
                }
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
            HStack(spacing: 10) {
                if let folder {
                    Button {
                        currentFolderID = folder.parentID
                    } label: {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(GhostButtonStyle(size: 26))
                    .help("Back to the parent folder")
                    .accessibilityLabel("Back to the parent folder")
                }
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

    private func headerTitle(folder: BookmarkFolderRecord?) -> String {
        guard let folder else { return "Bookmarks" }
        return folder.title
    }

    private func headerDetail(folder: BookmarkFolderRecord?, stats: BookmarksHomeStats) -> String {
        if isSearching { return "Searching every folder by page title, web address, and folder name." }
        guard let folder else {
            return "Folders and saved pages in this Mac user profile. Drop a page link onto a folder to file it."
        }
        return stats.pathLabel(for: folder.id)
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
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 178, maximum: 236), spacing: 16, alignment: .top)],
                alignment: .leading,
                spacing: 16
            ) {
                ForEach(folders) { folder in
                    BookmarkFolderCard(
                        folder: folder,
                        counts: stats.counts(for: folder.id),
                        directBookmarkCount: stats.directBookmarkCount(for: folder.id),
                        hosts: stats.identityHosts(for: folder.id),
                        openFolder: {
                            search = ""
                            currentFolderID = folder.id
                        },
                        openAll: { openAll(in: folder, stats: stats) },
                        newSubfolder: {
                            editorRequest = BookmarkFolderEditorRequest(
                                folderID: nil,
                                parentID: folder.id,
                                title: "",
                                iconID: LimeghostIconCatalog.defaultIconID,
                            colorID: nil,
                            )
                        },
                        rename: { presentRename(folder) },
                        delete: { requestDeletion(folder) },
                        fileDroppedURL: { fileDroppedURL($0, to: folder) }
                    )
                }
                if !isSearching {
                    NewFolderCard {
                        editorRequest = BookmarkFolderEditorRequest(
                            folderID: nil,
                            parentID: currentFolderID,
                            title: "",
                            iconID: LimeghostIconCatalog.defaultIconID,
                            colorID: nil,
                        )
                    }
                }
            }
            if folders.isEmpty && isSearching {
                HomeEmptyNote("No folder name matches “\(trimmedSearch)”.")
            }
        }
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

    // MARK: - All folders list

    @ViewBuilder
    private func allFoldersSection(stats: BookmarksHomeStats) -> some View {
        if !isSearching && !stats.allFolders.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HomeSectionTitle(title: "ALL FOLDERS", count: stats.allFolders.count)
                LazyVStack(spacing: 5) {
                    ForEach(stats.allFolders) { folder in
                        BookmarksHomeFolderRow(
                            folder: folder,
                            pathLabel: stats.parentPathLabel(for: folder.id),
                            bookmarkCount: stats.directBookmarkCount(for: folder.id),
                            subfolderCount: stats.directSubfolderCount(for: folder.id),
                            action: { currentFolderID = folder.id }
                        )
                    }
                }
            }
        }
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

/// A folder as a stack of paper: two tilted sheets peeking out behind a
/// frosted band, the folder's own icon and title below, and the identity
/// colors of its newest saved pages in the lower-left corner.
private struct BookmarkFolderCard: View {
    let folder: BookmarkFolderRecord
    let counts: BookmarkDescendantCounts
    /// Saved pages filed directly in this folder — what "Open all" opens.
    let directBookmarkCount: Int
    let hosts: [String]
    let openFolder: () -> Void
    let openAll: () -> Void
    let newSubfolder: () -> Void
    let rename: () -> Void
    let delete: () -> Void
    let fileDroppedURL: (URL) -> Bool

    @State private var isHovered = false
    @State private var isDropTargeted = false

    private var metaLabel: String {
        let links = counts.bookmarkCount == 1 ? "1 LINK" : "\(counts.bookmarkCount) LINKS"
        let subfolders = counts.subfolderCount == 1 ? "1 SUBFOLDER" : "\(counts.subfolderCount) SUBFOLDERS"
        return "\(links) · \(subfolders)"
    }

    private var accessibilityDescription: String {
        "\(folder.title) folder, \(counts.bookmarkCount) bookmarks, \(counts.subfolderCount) subfolders"
    }

    var body: some View {
        Button(action: openFolder) {
            VStack(alignment: .leading, spacing: 11) {
                art
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        BookmarkFolderIcon(folder: folder, size: LimeghostTheme.siteIconSize).foregroundStyle(LimeghostTheme.textSecondary)
                        Text(folder.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(LimeghostTheme.textPrimary)
                            .lineLimit(1)
                    }
                    Text(metaLabel)
                        .font(LimeghostTheme.metaFont)
                        .tracking(LimeghostTheme.metaTracking)
                        .foregroundStyle(LimeghostTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
            .background(cardBackground)
            .overlay(cardBorder)
            .contentShape(RoundedRectangle(cornerRadius: LimeghostTheme.radius18))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            return fileDroppedURL(url)
        } isTargeted: { isDropTargeted = $0 }
        .contextMenu {
            BookmarkFolderMenuItems(
                folder: folder,
                bookmarkCount: directBookmarkCount,
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
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Opens the folder. Drop a page link onto it to file that page here.")
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: LimeghostTheme.radius18)
            .fill(isDropTargeted ? LimeghostTheme.accentDim : (isHovered ? LimeghostTheme.bg3 : LimeghostTheme.bg2))
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: LimeghostTheme.radius18)
            .stroke(
                isDropTargeted ? LimeghostTheme.accent : LimeghostTheme.hairline2,
                lineWidth: isDropTargeted ? 1.5 : 1
            )
    }

    private var art: some View {
        ZStack {
            paperSheet(tone: 0.07)
                .rotationEffect(.degrees(-5))
                .offset(x: -9, y: -7)
            paperSheet(tone: 0.13)
                .rotationEffect(.degrees(4))
                .offset(x: 8, y: -4)
            frostedBand
        }
        .frame(maxWidth: .infinity)
        .frame(height: 84)
        .clipShape(RoundedRectangle(cornerRadius: LimeghostTheme.radius14))
        .overlay(alignment: .bottomLeading) {
            identityDots
                .padding(.leading, 9)
                .padding(.bottom, 9)
        }
    }

    private func paperSheet(tone: Double) -> some View {
        RoundedRectangle(cornerRadius: LimeghostTheme.radius12)
            .fill(Color.white.opacity(tone))
            .frame(height: 56)
            .padding(.horizontal, 20)
    }

    private var frostedBand: some View {
        RoundedRectangle(cornerRadius: LimeghostTheme.radius12)
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.13), Color.white.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: LimeghostTheme.radius12)
                    .stroke(LimeghostTheme.hairline3)
            )
            .frame(height: 48)
            .padding(.horizontal, 7)
            .offset(y: 18)
    }

    private var identityDots: some View {
        HStack(spacing: -5) {
            ForEach(Array(hosts.enumerated()), id: \.offset) { entry in
                SiteIconView(host: entry.element)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(LimeghostTheme.bg2, lineWidth: 2)
                    )
            }
        }
        .accessibilityHidden(true)
    }
}

/// The dashed companion card that creates a folder in the level currently
/// shown, using the same editor sheet as the organizer.
private struct NewFolderCard: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 19, weight: .medium))
                Text("New folder")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isHovered ? LimeghostTheme.accent : LimeghostTheme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 156)
            .background(
                RoundedRectangle(cornerRadius: LimeghostTheme.radius18)
                    .fill(isHovered ? LimeghostTheme.bg2 : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LimeghostTheme.radius18)
                    .stroke(
                        isHovered ? LimeghostTheme.accent.opacity(0.7) : LimeghostTheme.hairline3,
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: LimeghostTheme.radius18))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Create a folder here")
        .accessibilityLabel("New folder")
        .accessibilityHint("Creates a folder inside the level currently shown.")
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
    @State private var isHovered = false

    private var countLabel: String {
        "\(bookmarkCount) LINKS · \(subfolderCount) SUBFOLDERS"
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
                isHovered ? LimeghostTheme.bg2 : LimeghostTheme.bg1,
                in: RoundedRectangle(cornerRadius: LimeghostTheme.radius10)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(folder.title) folder, \(bookmarkCount) bookmarks, \(subfolderCount) subfolders")
    }
}
