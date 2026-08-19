import AppKit
import ClearframeCore
import Foundation
import SwiftUI

enum LibrarySection: String, CaseIterable {
    case bookmarks = "Bookmarks"
    case history = "History"
}

/// One wording for the Clear History confirmation, shared by the library
/// popover and the full-page bookmarks home. Clearing history removes up to
/// 500 stored visits and cannot be undone, so both places ask first.
enum ClearHistoryConfirmation {
    static let title = "Clear all local history?"
    static let confirmLabel = "Clear history"

    static func message(visitCount: Int) -> String {
        let visits = visitCount == 1 ? "1 stored visit" : "\(visitCount) stored visits"
        return "This removes \(visits) from this Mac and cannot be undone. Your bookmarks, open tabs, and downloaded files are not affected."
    }
}

struct LibraryPopover: View {
    @ObservedObject var store: BrowserDataStore
    let open: (String, Bool) -> Void
    @State private var section: LibrarySection = .bookmarks
    @State private var search = ""
    @State private var showsClearHistoryConfirmation = false

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
                        Button("Clear History", role: .destructive) {
                            showsClearHistoryConfirmation = true
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 430, height: 450)
        .confirmationDialog(
            ClearHistoryConfirmation.title,
            isPresented: $showsClearHistoryConfirmation,
            titleVisibility: .visible
        ) {
            Button(ClearHistoryConfirmation.confirmLabel, role: .destructive) { store.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(ClearHistoryConfirmation.message(visitCount: store.history.count))
        }
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
    let colorID: String?
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
                        iconID: ClearframeIconCatalog.defaultIconID,
                        colorID: nil
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
                                    iconID: ClearframeIconCatalog.defaultIconID,
                            colorID: nil,
                                )
                            },
                            rename: {
                                editorRequest = BookmarkFolderEditorRequest(
                                    folderID: folder.id,
                                    parentID: folder.parentID,
                                    title: folder.title,
                                    iconID: ClearframeIconGeometry.iconID(for: folder),
                                    colorID: folder.colorID,
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
                Image(systemName: "ellipsis.circle")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .menuStyle(.button)
            .menuIndicator(.hidden)
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
                Image(systemName: "ellipsis.circle")
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .menuStyle(.button)
            .menuIndicator(.hidden)
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
    let save: (String, String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var iconID: String
    @State private var color: ClearframeIconColor
    @State private var search = ""
    @State private var style: ClearframeIconStyle

    init(request: BookmarkFolderEditorRequest, save: @escaping (String, String, String) -> Void) {
        self.request = request
        self.save = save
        _title = State(initialValue: request.title)
        _iconID = State(initialValue: request.iconID)
        _color = State(initialValue: ClearframeIconColor(id: request.colorID) ?? .mint)
        // Open on the set the folder is already using, so editing a folder does
        // not silently move it to another style's grid.
        _style = State(initialValue: ClearframeIconCatalog.icon(id: request.iconID)?.style ?? .clearframe)
    }

    /// Matches on the icon's own name and its category, so "work" finds the
    /// whole work set and "plane" finds the one icon. Scoped to the chosen
    /// style: the sets are different visual languages, and a grid that mixed
    /// them would invite a bar that mixes them too.
    private var matches: [ClearframeIconCategory: [ClearframeIcon]] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return ClearframeIconCatalog.byCategory(style: style) }
        var result: [ClearframeIconCategory: [ClearframeIcon]] = [:]
        for category in ClearframeIconCategory.allCases {
            let icons = ClearframeIconCatalog.icons(in: category, style: style).filter {
                $0.displayName.contains(query) || category.title.lowercased().contains(query)
            }
            if !icons.isEmpty { result[category] = icons }
        }
        return result
    }

    /// Whether the grid currently being browsed is tintable. Drives how its
    /// cells draw.
    private var isTintable: Bool { style.isTintable }

    /// Whether the icon the folder will actually be saved with is tintable.
    /// Distinct from `isTintable` on purpose: browsing the Stickies tab with a
    /// Clearframe icon still selected must not hide the tint that icon is
    /// really using, or the preview would misrepresent what Save does.
    private var selectedIsTintable: Bool {
        ClearframeIconCatalog.icon(id: iconID)?.style.isTintable ?? true
    }

    private var isSaveDisabled: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(request.folderID == nil ? "New bookmark folder" : "Edit bookmark folder")
                .font(.title2.bold())

            HStack(spacing: 12) {
                iconPreview
                TextField("Folder name", text: $title)
                    .textFieldStyle(.roundedBorder)
                if selectedIsTintable {
                    colorSwatches
                }
            }

            Divider()

            stylePicker

            TextField("Search icons", text: $search)
                .textFieldStyle(.roundedBorder)

            iconGrid

            if let attribution = style.attribution {
                Text(attribution)
                    .font(.system(size: 10.5))
                    .foregroundStyle(ClearframeTheme.textTertiary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    save(title, iconID, color.rawValue)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaveDisabled)
            }
        }
        .padding(22)
        .frame(width: 470)
    }

    /// The chosen icon at the size it will actually draw at in the bar, so the
    /// preview is a preview and not a flattering enlargement.
    @ViewBuilder
    private var iconPreview: some View {
        let icon = ClearframeIconView(iconID: iconID, size: 24)
        Group {
            if selectedIsTintable {
                icon.foregroundStyle(Color(color))
            } else {
                icon
            }
        }
        .frame(width: 40, height: 40)
        .background(ClearframeTheme.bg3, in: RoundedRectangle(cornerRadius: ClearframeTheme.radius9))
    }

    /// The sets are separate styles rather than one mixed grid. Switching here
    /// changes what the grid offers; it never rewrites the folder's icon, so
    /// looking around costs nothing until something is picked.
    private var stylePicker: some View {
        Picker("Icon set", selection: $style) {
            ForEach(ClearframeIconCatalog.availableStyles, id: \.self) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help(style.subtitle)
        .accessibilityLabel("Icon set")
        .accessibilityHint(style.subtitle)
    }

    /// Four tints, not a colour well: the set holds together because it is
    /// drawn in one of these. Shown only for artwork that named no colour of
    /// its own — offering it over a multicolour set would be a control that
    /// does nothing.
    private var colorSwatches: some View {
        HStack(spacing: 6) {
            ForEach(ClearframeIconColor.allCases, id: \.self) { swatch in
                Button { color = swatch } label: {
                    Circle()
                        .fill(Color(swatch))
                        .frame(width: 18, height: 18)
                        .overlay {
                            Circle()
                                .stroke(ClearframeTheme.textPrimary, lineWidth: swatch == color ? 2 : 0)
                        }
                }
                .buttonStyle(.plain)
                .help(swatch.title)
                .accessibilityLabel("\(swatch.title) icon colour")
                .accessibilityAddTraits(swatch == color ? [.isButton, .isSelected] : .isButton)
            }
        }
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
            cellArtwork(icon, isSelected: isSelected)
                .frame(width: 38, height: 38)
                .background(
                    // A tintable icon inverts into its tint when chosen. A
                    // multicolour one cannot — recolouring it would do nothing
                    // — so selection is a ring around artwork left alone.
                    isSelected && isTintable ? Color(color) : ClearframeTheme.bg3,
                    in: RoundedRectangle(cornerRadius: ClearframeTheme.radius6)
                )
                .overlay {
                    if isSelected && !isTintable {
                        RoundedRectangle(cornerRadius: ClearframeTheme.radius6)
                            .stroke(ClearframeTheme.accent, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(icon.displayName)
        .accessibilityLabel(icon.displayName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func cellArtwork(_ icon: ClearframeIcon, isSelected: Bool) -> some View {
        let artwork = ClearframeIconView(iconID: icon.id, size: 22)
        if isTintable {
            artwork.foregroundStyle(isSelected ? ClearframeTheme.bg0 : Color(color))
        } else {
            artwork
        }
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

