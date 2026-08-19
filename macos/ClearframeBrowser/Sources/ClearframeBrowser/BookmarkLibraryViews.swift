import AppKit
import ClearframeCore
import Foundation
import SwiftUI

enum LibrarySection: String, CaseIterable {
    case bookmarks = "Bookmarks"
    case history = "History"
}

struct LibraryPopover: View {
    @ObservedObject var store: BrowserDataStore
    let open: (String, Bool) -> Void
    @State private var section: LibrarySection = .bookmarks
    @State private var search = ""

    private var filteredHistory: [HistoryRecord] {
        guard !search.isEmpty else { return store.history }
        return store.history.filter { $0.title.localizedCaseInsensitiveContains(search) || $0.url.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker("Library", selection: $section) {
                ForEach(LibrarySection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            TextField("Search saved pages", text: $search)
                .textFieldStyle(.roundedBorder)

            if section == .bookmarks {
                BookmarkOrganizerView(store: store, search: search, open: open)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        if filteredHistory.isEmpty { libraryEmpty("No local history", "Completed page visits appear here.") }
                        ForEach(filteredHistory) { item in
                            LibraryRow(
                                title: item.title,
                                url: item.url,
                                detail: item.visitedAt.formatted(date: .abbreviated, time: .shortened),
                                open: { open(item.url, false) },
                                openNewTab: { open(item.url, true) },
                                remove: { store.removeHistory(item) }
                            )
                        }
                    }
                }
                if !store.history.isEmpty {
                    HStack {
                        Text("Stored only in this Mac user profile.").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear History", role: .destructive) { store.clearHistory() }.font(.caption)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 430, height: 450)
    }

    private func libraryEmpty(_ title: String, _ detail: String) -> some View {
        ContentUnavailableView(title, systemImage: "books.vertical", description: Text(detail))
            .frame(height: 270)
    }
}

struct BookmarkFolderEditorRequest: Identifiable {
    let id = UUID()
    let folderID: UUID?
    let parentID: UUID?
    let title: String
    let iconID: String
}

struct BookmarkFolderDestination: Identifiable {
    let folderID: UUID?
    let label: String
    var id: String { folderID?.uuidString ?? "unfiled" }

    /// "Unfiled" plus every folder as a "Parent › Child" path. One shared
    /// builder so every accessible Move menu — organizer popover and the
    /// full-page bookmarks home — offers exactly the same destinations in the
    /// same order.
    @MainActor
    static func tree(in store: BrowserDataStore) -> [BookmarkFolderDestination] {
        var childrenByParent: [UUID?: [BookmarkFolderRecord]] = [:]
        for folder in store.bookmarkFolders {
            childrenByParent[folder.parentID, default: []].append(folder)
        }
        for key in childrenByParent.keys {
            childrenByParent[key]?.sort {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }

        var result = [BookmarkFolderDestination(folderID: nil, label: "Unfiled")]
        func appendChildren(of parentID: UUID?, prefix: String) {
            for folder in childrenByParent[parentID] ?? [] {
                let path = prefix.isEmpty
                    ? folder.title
                    : "\(prefix) › \(folder.title)"
                result.append(BookmarkFolderDestination(folderID: folder.id, label: path))
                appendChildren(of: folder.id, prefix: path)
            }
        }
        appendChildren(of: nil, prefix: "")
        return result
    }
}

struct BookmarkOrganizerView: View {
    @ObservedObject var store: BrowserDataStore
    let search: String
    let open: (String, Bool) -> Void
    @State private var currentFolderID: UUID?
    @State private var editorRequest: BookmarkFolderEditorRequest?
    @State private var bookmarkEditorRequest: BookmarkEditorRequest?
    @State private var pendingDeletion: BookmarkFolderRecord?
    @State private var dropConfirmation: String?

    private var currentFolder: BookmarkFolderRecord? {
        currentFolderID.flatMap(store.bookmarkFolder(id:))
    }

    private var visibleFolders: [BookmarkFolderRecord] {
        search.isEmpty ? store.bookmarkFolders(in: currentFolderID) : []
    }

    private var visibleBookmarks: [BookmarkRecord] {
        if search.isEmpty { return store.bookmarks(in: currentFolderID) }
        return store.bookmarks.filter {
            $0.title.localizedCaseInsensitiveContains(search) || $0.url.localizedCaseInsensitiveContains(search)
        }
    }

    private var destinations: [BookmarkFolderDestination] {
        BookmarkFolderDestination.tree(in: store)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if let currentFolder {
                    Button {
                        currentFolderID = currentFolder.parentID
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .help("Back to parent folder")
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(currentFolder?.title ?? "Bookmarks")
                        .font(.callout.bold())
                    Text(search.isEmpty ? (currentFolder == nil ? "Folders and unfiled bookmarks" : "Local bookmark folder") : "Search all bookmarks")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    editorRequest = BookmarkFolderEditorRequest(
                        folderID: nil,
                        parentID: currentFolderID,
                        title: "",
                        iconID: ClearframeIconCatalog.defaultIconID
                    )
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityHint("Creates a subfolder inside the folder currently shown.")
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(visibleFolders) { folder in
                        BookmarkFolderRow(
                            folder: folder,
                            bookmarkCount: store.bookmarks(in: folder.id).count,
                            subfolderCount: store.bookmarkFolders(in: folder.id).count,
                            open: { currentFolderID = folder.id },
                            openAll: { openAll(in: folder) },
                            newSubfolder: {
                                editorRequest = BookmarkFolderEditorRequest(
                                    folderID: nil,
                                    parentID: folder.id,
                                    title: "",
                                    iconID: ClearframeIconCatalog.defaultIconID
                                )
                            },
                            rename: {
                                editorRequest = BookmarkFolderEditorRequest(
                                    folderID: folder.id,
                                    parentID: folder.parentID,
                                    title: folder.title,
                                    iconID: ClearframeIconGeometry.iconID(for: folder)
                                )
                            },
                            fileDroppedURL: { fileDroppedURL($0, to: folder) },
                            delete: { requestDeletion(folder) }
                        )
                    }

                    ForEach(visibleBookmarks) { bookmark in
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

                    if visibleFolders.isEmpty && visibleBookmarks.isEmpty {
                        ContentUnavailableView(
                            search.isEmpty ? "Nothing saved here" : "No matching bookmarks",
                            systemImage: "bookmark",
                            description: Text(search.isEmpty
                                              ? "Use the star to save a page, or create folders such as Web Design, Programming, and Shopping."
                                              : "Try a different title or website address.")
                        )
                        .frame(height: 255)
                    }
                }
            }
            .sheet(item: $bookmarkEditorRequest) { request in
                BookmarkEditor(request: request) { title, url in
                    store.updateBookmark(id: request.bookmarkID, title: title, url: url)
                }
            }

            HStack {
                Image(systemName: "lock")
                Text(dropConfirmation ?? "Folders and bookmarks stay in this Mac user profile.")
            }
            .font(.caption2)
            .foregroundStyle(dropConfirmation == nil ? Color.secondary : ClearframeTheme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $editorRequest) { request in
            BookmarkFolderEditor(request: request) { title, iconID in
                if let folderID = request.folderID {
                    store.updateBookmarkFolder(id: folderID, title: title, iconID: iconID)
                } else {
                    _ = store.createBookmarkFolder(title: title, iconID: iconID, parentID: request.parentID)
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
    }

    private func requestDeletion(_ folder: BookmarkFolderRecord) {
        if store.bookmarkFolderContainsItems(folder) {
            pendingDeletion = folder
        } else {
            store.deleteBookmarkFolderPreservingContents(folder)
        }
    }

    /// Opens the folder's own saved pages, each in its own tab — the count in
    /// the menu entry is exactly what this loop opens.
    private func openAll(in folder: BookmarkFolderRecord) {
        for bookmark in store.bookmarks(in: folder.id) {
            open(bookmark.url, true)
        }
    }

    private func fileDroppedURL(_ url: URL, to folder: BookmarkFolderRecord) -> Bool {
        guard let result = store.fileBookmarkFromDrop(url, title: nil, to: folder.id) else { return false }
        let message: String
        switch result.disposition {
        case .created:
            message = "Saved to \(folder.title)"
        case .moved:
            message = "Moved to \(folder.title)"
        case .alreadyFiled:
            message = "Already in \(folder.title)"
        }
        dropConfirmation = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            if dropConfirmation == message { dropConfirmation = nil }
        }
        return true
    }
}

struct BookmarkFolderRow: View {
    let folder: BookmarkFolderRecord
    let bookmarkCount: Int
    let subfolderCount: Int
    let open: () -> Void
    let openAll: () -> Void
    let newSubfolder: () -> Void
    let rename: () -> Void
    let fileDroppedURL: (URL) -> Bool
    let delete: () -> Void
    @State private var isDropTargeted = false

    /// The organizer has no page of its own in front of the reader, so the
    /// shared folder menu leaves its current-page entries out here, and this
    /// view *is* the organizer, so it offers no "All bookmarks…" jump either.
    private var menuItems: some View {
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

    var body: some View {
        HStack(spacing: 9) {
            Button(action: open) {
                HStack(spacing: 9) {
                    BookmarkFolderIcon(folder: folder, size: 17).foregroundStyle(ClearframeTheme.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(folder.title).font(.callout.weight(.semibold)).lineLimit(1)
                        Text("\(bookmarkCount) bookmarks · \(subfolderCount) folders")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(folder.title) folder, \(bookmarkCount) bookmarks, \(subfolderCount) subfolders")

            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis.circle").frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Folder actions")
            .accessibilityLabel("\(folder.title) folder actions")
        }
        .padding(9)
        .background(
            isDropTargeted ? ClearframeTheme.accentDim : Color.primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 9)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(isDropTargeted ? ClearframeTheme.accent : Color.clear, lineWidth: 1.5)
        }
        .contextMenu { menuItems }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            return fileDroppedURL(url)
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
        .help("Open \(folder.title), or drop a saved bookmark here to move it")
    }
}

struct BookmarkOrganizerRow: View {
    let bookmark: BookmarkRecord
    let destinations: [BookmarkFolderDestination]
    let open: () -> Void
    let openNewTab: () -> Void
    let edit: () -> Void
    let move: (UUID?) -> Void
    let remove: () -> Void

    /// The same six actions the bookmarks bar offers, so a saved page behaves
    /// identically wherever the reader meets it.
    private var menuItems: some View {
        BookmarkLinkMenuItems(
            bookmark: bookmark,
            destinations: destinations,
            open: open,
            openInNewTab: openNewTab,
            edit: edit,
            move: move,
            delete: remove
        )
    }

    @ViewBuilder
    var body: some View {
        if let url = BookmarkURLPolicy.validatedURL(bookmark.url) {
            row.draggable(url)
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: 8) {
            Button(action: open) {
                HStack(spacing: 9) {
                    SiteIconView(urlString: bookmark.url)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(bookmark.title).font(.callout.weight(.medium)).lineLimit(1)
                        Text(bookmark.url).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis.circle").frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Bookmark actions")
            .accessibilityLabel("\(bookmark.title) actions")

            Button(action: edit) { Image(systemName: "pencil").frame(width: 22, height: 22) }
                .buttonStyle(.plain).help("Edit name and address")
                .accessibilityLabel("Edit \(bookmark.title)")
            Button(action: openNewTab) { Image(systemName: "plus.square.on.square").frame(width: 22, height: 22) }
                .buttonStyle(.plain).help("Open in new tab")
            Button(action: remove) { Image(systemName: "trash").frame(width: 22, height: 22) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Delete bookmark")
        }
        .padding(8)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        .contextMenu { menuItems }
        .accessibilityHint("Drag this bookmark onto a visible folder to move it. Secondary-click, or use the actions menu, to open, edit, copy, move, or delete it.")
    }
}

struct BookmarkFolderEditor: View {
    let request: BookmarkFolderEditorRequest
    let save: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var iconID: String
    @State private var search = ""

    init(request: BookmarkFolderEditorRequest, save: @escaping (String, String) -> Void) {
        self.request = request
        self.save = save
        _title = State(initialValue: request.title)
        _iconID = State(initialValue: request.iconID)
    }

    /// Matches on the icon's own name and its category, so "work" finds the
    /// whole work set and "plane" finds the one icon.
    private var matches: [ClearframeIconCategory: [ClearframeIcon]] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return ClearframeIconCatalog.byCategory }
        var result: [ClearframeIconCategory: [ClearframeIcon]] = [:]
        for category in ClearframeIconCategory.allCases {
            let icons = ClearframeIconCatalog.icons(in: category).filter {
                $0.id.contains(query) || category.title.lowercased().contains(query)
            }
            if !icons.isEmpty { result[category] = icons }
        }
        return result
    }

    private var isSaveDisabled: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(request.folderID == nil ? "New bookmark folder" : "Edit bookmark folder")
                .font(.title2.bold())

            HStack(spacing: 12) {
                ClearframeIconView(iconID: iconID, size: 24)
                    .foregroundStyle(ClearframeTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(ClearframeTheme.bg3, in: RoundedRectangle(cornerRadius: ClearframeTheme.radius9))
                TextField("Folder name", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            TextField("Search icons", text: $search)
                .textFieldStyle(.roundedBorder)

            iconGrid

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    save(title, iconID)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaveDisabled)
            }
        }
        .padding(22)
        .frame(width: 470)
    }

    private var iconGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14, pinnedViews: []) {
                ForEach(ClearframeIconCategory.allCases, id: \.self) { category in
                    if let icons = matches[category], !icons.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(category.title.uppercased())
                                .font(ClearframeTheme.metaFont)
                                .tracking(ClearframeTheme.metaTracking)
                                .foregroundStyle(ClearframeTheme.textTertiary)
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 38, maximum: 38), spacing: 6)],
                                alignment: .leading,
                                spacing: 6
                            ) {
                                ForEach(icons) { icon in
                                    iconCell(icon)
                                }
                            }
                        }
                    }
                }
                if matches.isEmpty {
                    Text("No icon matches “\(search)”.")
                        .font(.callout)
                        .foregroundStyle(ClearframeTheme.textSecondary)
                        .padding(.vertical, 18)
                }
            }
            .padding(.vertical, 2)
        }
        .frame(height: 240)
    }

    private func iconCell(_ icon: ClearframeIcon) -> some View {
        let isSelected = icon.id == iconID
        return Button { iconID = icon.id } label: {
            ClearframeIconView(iconID: icon.id, size: 22)
                .foregroundStyle(isSelected ? ClearframeTheme.onAccent : ClearframeTheme.textSecondary)
                .frame(width: 38, height: 38)
                .background(
                    isSelected ? ClearframeTheme.accent : ClearframeTheme.bg3,
                    in: RoundedRectangle(cornerRadius: ClearframeTheme.radius6)
                )
        }
        .buttonStyle(.plain)
        .help(icon.id)
        .accessibilityLabel(icon.id)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

struct LibraryRow: View {
    let title: String
    let url: String
    let detail: String?
    let open: () -> Void
    let openNewTab: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.callout.weight(.medium)).lineLimit(1)
                    Text(detail ?? url).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: openNewTab) { Image(systemName: "plus.square.on.square").frame(width: 22, height: 22) }
                .buttonStyle(.plain).help("Open in new tab")
            Button(action: remove) { Image(systemName: "trash").frame(width: 22, height: 22) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove")
        }
        .padding(8)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }
}

