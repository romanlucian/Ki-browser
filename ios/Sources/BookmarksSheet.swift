import LimeghostCore
import LimeghostShared
import SwiftUI

/// What the Bookmarks sheet shows and does, apart from how it draws, so a
/// test can call it: the shape `TabSwitcherModel` has. It holds only the
/// workspace and reads the store fresh on every call, because the sheet
/// observes the store and rebuilds this whenever the store changes.
///
/// Everything here is the store's or the workspace's own: the order, the
/// search filters, the filing calls and the two doors. The phone adds a list,
/// not a second set of rules.
@MainActor
struct BookmarksModel {
    let workspace: BrowserWorkspace

    private var store: BrowserDataStore { workspace.dataStore }

    // MARK: - Listing

    /// "Bookmarks" at the top level, and a folder's own name inside it.
    func title(of folderID: UUID?) -> String {
        guard let folderID, let folder = store.bookmarkFolder(id: folderID) else { return "Bookmarks" }
        return folder.title
    }

    /// A folder's subfolders, in the store's order: the order the Mac shows.
    func folders(in folderID: UUID?) -> [BookmarkFolderRecord] {
        store.bookmarkFolders(in: folderID)
    }

    /// A folder's bookmarks, in the store's order.
    func bookmarks(in folderID: UUID?) -> [BookmarkRecord] {
        store.bookmarks(in: folderID)
    }

    // MARK: - Search

    /// Folders from every level whose names match, through the filter the
    /// Mac's bookmarks home uses.
    func folders(matching query: String) -> [BookmarkFolderRecord] {
        BookmarksHomeSearch.folders(store.bookmarkFolders, matching: query)
    }

    /// Bookmarks from every folder whose names or addresses match.
    func bookmarks(matching query: String) -> [BookmarkRecord] {
        BookmarksHomeSearch.bookmarks(store.bookmarks, matching: query)
    }

    // MARK: - Doors

    /// Through `open(_:inNewTab:)`, the door table's "an address or a
    /// bookmark" and "a bookmark in a new tab". It makes room for the page
    /// before loading it; a session load directly would skip that.
    func open(_ bookmark: BookmarkRecord, inNewTab: Bool = false) {
        workspace.open(bookmark.url, inNewTab: inNewTab)
    }

    // MARK: - Filing

    func delete(_ bookmark: BookmarkRecord) {
        store.removeBookmark(bookmark)
    }

    /// Whether deleting this folder asks first: only when it holds something,
    /// which is the Mac's rule. An empty folder has nothing to lose.
    func deletingAsksFirst(_ folder: BookmarkFolderRecord) -> Bool {
        store.bookmarkFolderContainsItems(folder)
    }

    /// Deletes the folder itself. What it held moves up to its parent, so
    /// deleting a folder never deletes a saved page.
    func delete(_ folder: BookmarkFolderRecord) {
        store.deleteBookmarkFolderPreservingContents(folder)
    }

    /// Changes the name and nothing else: the address and the folder stay.
    /// An empty name becomes the site's host, which is the store's rule.
    func rename(_ bookmark: BookmarkRecord, to name: String) {
        store.updateBookmark(id: bookmark.id, title: name, url: bookmark.url)
    }

    /// Changes the name and nothing else. The store's update takes an icon and
    /// a tint too; handed the folder's own, it leaves both as they are. An
    /// empty icon ID leaves a folder that never chose one still resolving its
    /// old emoji. An empty name keeps the old one, which is the store's rule.
    func rename(_ folder: BookmarkFolderRecord, to name: String) {
        store.updateBookmarkFolder(id: folder.id, title: name, iconID: folder.iconID ?? "", colorID: folder.colorID)
    }

    /// Files a bookmark at the end of another folder, or of the top level.
    func move(_ bookmark: BookmarkRecord, to folderID: UUID?) {
        store.moveBookmark(bookmark, to: folderID)
    }

    /// A new folder at the end of the one on screen, drawn with the plain
    /// folder. The store refuses an empty name, but the person pressed Create
    /// and asked for a folder, so an empty name makes one called "New Folder".
    @discardableResult
    func createFolder(named name: String, in parentID: UUID?) -> BookmarkFolderRecord? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.createBookmarkFolder(
            title: trimmed.isEmpty ? "New Folder" : trimmed,
            iconID: LimeghostIconCatalog.defaultIconID,
            parentID: parentID
        )
    }
}

/// A name being typed into an alert: a new folder, or a new name for a folder
/// or a bookmark. One value, so each screen has one alert and a test can read
/// what each case shows and does.
enum BookmarkNameEdit {
    case newFolder(parentID: UUID?)
    case renameFolder(BookmarkFolderRecord)
    case renameBookmark(BookmarkRecord)

    var title: String {
        switch self {
        case .newFolder: return "New Folder"
        case .renameFolder: return "Rename Folder"
        case .renameBookmark: return "Rename Bookmark"
        }
    }

    var confirmLabel: String {
        switch self {
        case .newFolder: return "Create"
        case .renameFolder, .renameBookmark: return "Save"
        }
    }

    /// What the field holds when the alert opens: nothing for a new folder,
    /// the current name for a rename.
    var startingName: String {
        switch self {
        case .newFolder: return ""
        case .renameFolder(let folder): return folder.title
        case .renameBookmark(let bookmark): return bookmark.title
        }
    }

    @MainActor
    func commit(_ name: String, with model: BookmarksModel) {
        switch self {
        case .newFolder(let parentID): model.createFolder(named: name, in: parentID)
        case .renameFolder(let folder): model.rename(folder, to: name)
        case .renameBookmark(let bookmark): model.rename(bookmark, to: name)
        }
    }
}

/// Bookmarks, over the page: the top level, the folders beneath it, and a
/// search across all of them. Opened from the page menu. A bookmark opens and
/// the sheet closes; a folder opens on a screen of its own.
struct BookmarksSheet: View {
    let workspace: BrowserWorkspace
    let dismiss: () -> Void

    @State private var query = ""

    var body: some View {
        NavigationStack {
            BookmarkFolderScreen(workspace: workspace, folderID: nil, query: query, close: dismiss)
                .searchable(
                    text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search bookmarks"
                )
                .navigationDestination(for: UUID.self) { folderID in
                    BookmarkFolderScreen(workspace: workspace, folderID: folderID, query: "", close: dismiss)
                }
        }
        .limeghostListSheet()
    }
}

/// One folder's list, or, at the top while something is typed, the matches
/// from every folder, with everything a row can do.
struct BookmarkFolderScreen: View {
    @ObservedObject private var store: BrowserDataStore
    private let workspace: BrowserWorkspace
    /// Nil is the top level.
    private let folderID: UUID?
    /// What the search field holds. Only the top screen has one.
    private let query: String
    private let close: () -> Void

    @State private var nameEdit: BookmarkNameEdit?
    @State private var typedName = ""
    @State private var folderToConfirm: BookmarkFolderRecord?
    @State private var bookmarkToMove: BookmarkRecord?

    init(workspace: BrowserWorkspace, folderID: UUID?, query: String, close: @escaping () -> Void) {
        self.store = workspace.dataStore
        self.workspace = workspace
        self.folderID = folderID
        self.query = query
        self.close = close
    }

    private var model: BookmarksModel { BookmarksModel(workspace: workspace) }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        let folders = isSearching ? model.folders(matching: query) : model.folders(in: folderID)
        let bookmarks = isSearching ? model.bookmarks(matching: query) : model.bookmarks(in: folderID)

        List {
            if isSearching {
                if !folders.isEmpty {
                    Section("Folders") {
                        ForEach(folders) { folderRow($0) }
                    }
                }
                if !bookmarks.isEmpty {
                    Section("Bookmarks") {
                        ForEach(bookmarks) { bookmarkRow($0) }
                    }
                }
            } else {
                ForEach(folders) { folderRow($0) }
                ForEach(bookmarks) { bookmarkRow($0) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .overlay {
            if folders.isEmpty && bookmarks.isEmpty {
                emptyState
            }
        }
        .navigationTitle(model.title(of: folderID))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: close)
            }
            ToolbarItem(placement: .bottomBar) {
                Button {
                    beginNaming(.newFolder(parentID: folderID))
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        .alert(nameEdit?.title ?? "", isPresented: isNaming, presenting: nameEdit) { edit in
            TextField("Name", text: $typedName)
            Button("Cancel", role: .cancel) {}
            Button(edit.confirmLabel) { edit.commit(typedName, with: model) }
        }
        .alert("Delete folder?", isPresented: isConfirmingDeletion, presenting: folderToConfirm) { folder in
            Button("Delete Folder", role: .destructive) { model.delete(folder) }
            Button("Cancel", role: .cancel) {}
        } message: { folder in
            Text(Self.deletionMessage(for: folder))
        }
        .sheet(item: $bookmarkToMove) { bookmark in
            BookmarkMovePicker(
                destinations: BookmarkDestinations.rows(folders: store.bookmarkFolders),
                currentFolderID: bookmark.folderID
            ) { destination in
                model.move(bookmark, to: destination)
            }
        }
    }

    private func folderRow(_ folder: BookmarkFolderRecord) -> some View {
        NavigationLink(value: folder.id) {
            HStack(spacing: 12) {
                BookmarkFolderIcon(folder: folder)
                Text(folder.title)
                    .foregroundStyle(LimeghostTheme.textPrimary)
                    .lineLimit(1)
            }
        }
        .listRowBackground(LimeghostTheme.bg2)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Not `role: .destructive`: a destructive swipe button animates its
            // row away at once, before a folder that asks first has its answer.
            Button {
                requestDeletion(folder)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
        .contextMenu {
            Button {
                beginNaming(.renameFolder(folder))
            } label: {
                Label("Rename…", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                requestDeletion(folder)
            } label: {
                Label("Delete Folder", systemImage: "trash")
            }
        }
    }

    private func bookmarkRow(_ bookmark: BookmarkRecord) -> some View {
        Button {
            model.open(bookmark)
            close()
        } label: {
            HStack(spacing: 12) {
                SiteIconView(urlString: bookmark.url)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bookmark.title)
                        .foregroundStyle(LimeghostTheme.textPrimary)
                        .lineLimit(1)
                    Text(URL(string: bookmark.url)?.host ?? bookmark.url)
                        .font(.caption)
                        .foregroundStyle(LimeghostTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .listRowBackground(LimeghostTheme.bg2)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                model.delete(bookmark)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                model.open(bookmark, inNewTab: true)
                close()
            } label: {
                Label("Open in New Tab", systemImage: "plus.square.on.square")
            }
            Button {
                beginNaming(.renameBookmark(bookmark))
            } label: {
                Label("Rename…", systemImage: "pencil")
            }
            Button {
                bookmarkToMove = bookmark
            } label: {
                Label("Move to…", systemImage: "folder")
            }
            Divider()
            Button(role: .destructive) {
                model.delete(bookmark)
            } label: {
                Label("Delete Bookmark", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if isSearching {
            ContentUnavailableView.search(text: query)
        } else if folderID == nil {
            ContentUnavailableView(
                "No Bookmarks Yet",
                systemImage: "book",
                description: Text("Add Bookmark in the menu saves the page you're on.")
            )
        } else {
            ContentUnavailableView(
                "This Folder Is Empty",
                systemImage: "folder",
                description: Text("To file a bookmark here, touch and hold it, then choose Move to…")
            )
        }
    }

    private var isNaming: Binding<Bool> {
        Binding(get: { nameEdit != nil }, set: { if !$0 { nameEdit = nil } })
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding(get: { folderToConfirm != nil }, set: { if !$0 { folderToConfirm = nil } })
    }

    /// The field starts from the current name for a rename, and empty for a
    /// new folder.
    private func beginNaming(_ edit: BookmarkNameEdit) {
        typedName = edit.startingName
        nameEdit = edit
    }

    /// An empty folder goes at once. One holding anything asks first.
    private func requestDeletion(_ folder: BookmarkFolderRecord) {
        if model.deletingAsksFirst(folder) {
            folderToConfirm = folder
        } else {
            model.delete(folder)
        }
    }

    /// The Mac's words for the same question, in `BookmarksHomePage`. Built
    /// as a `String`, so a folder name is never read as Markdown.
    private static func deletionMessage(for folder: BookmarkFolderRecord) -> String {
        "\(folder.title) contains saved items. Its bookmarks and subfolders will move to the parent folder; nothing will be deleted."
    }
}
