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

    /// Files a folder, with everything in it, at the end of another folder or
    /// of the top level — how the folders an import brought come out of the
    /// dated folder it made.
    @discardableResult
    func move(_ folder: BookmarkFolderRecord, to parentID: UUID?) -> Bool {
        store.moveBookmarkFolder(folder, to: parentID)
    }

    /// Files a bookmark at the end of another folder, or of the top level.
    func move(_ bookmark: BookmarkRecord, to folderID: UUID?) {
        store.moveBookmark(bookmark, to: folderID)
    }

}

/// A name being typed into an alert: a new name for a bookmark. One value, so
/// a test can read what the alert shows and does. A folder is named in Edit
/// Folder instead (`FolderEditorSheet`), with its icon and colour — New Folder
/// included, since September 29, 2026.
enum BookmarkNameEdit {
    case renameBookmark(BookmarkRecord)

    var title: String {
        switch self {
        case .renameBookmark: return "Rename Bookmark"
        }
    }

    var confirmLabel: String {
        switch self {
        case .renameBookmark: return "Save"
        }
    }

    /// What the field holds when the alert opens: the current name.
    var startingName: String {
        switch self {
        case .renameBookmark(let bookmark): return bookmark.title
        }
    }

    @MainActor
    func commit(_ name: String, with model: BookmarksModel) {
        switch self {
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
    @State private var folderEditor: FolderEditorRequest?
    @State private var folderToMove: BookmarkFolderRecord?
    @State private var isImporting = false
    /// Selecting several at once, to move or delete them together — the
    /// founder asked for it after an import left dozens of things in one
    /// folder. The rows keep their one-at-a-time actions when not selecting.
    @State private var isSelecting = false
    @State private var selection = Set<BookmarkItemID>()
    @State private var isMovingSelection = false
    @State private var isConfirmingSelectionDelete = false

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

        List(selection: $selection) {
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
        .environment(\.editMode, .constant(isSelecting ? .active : .inactive))
        .overlay {
            if folders.isEmpty && bookmarks.isEmpty {
                emptyState
            }
        }
        .navigationTitle(model.title(of: folderID))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isSelecting)
        .toolbar {
            if isSelecting {
                selectingToolbar(listed: listedItems(folders: folders, bookmarks: bookmarks))
            } else {
                browsingToolbar(hasItems: !(folders.isEmpty && bookmarks.isEmpty))
            }
        }
        .sheet(isPresented: $isMovingSelection) {
            BookmarkMovePicker(
                destinations: BookmarkDestinations.rows(folders: store.bookmarkFolders, excludingAll: selectedFolderIDs),
                currentFolderID: folderID
            ) { destination in
                model.move(listedItems(folders: folders, bookmarks: bookmarks).filter(selection.contains), to: destination)
                endSelecting()
            }
        }
        .alert(
            BookmarkSelectionWording.deleteTitle(folders: selectedFolderIDs.count, bookmarks: selection.count - selectedFolderIDs.count),
            isPresented: $isConfirmingSelectionDelete
        ) {
            Button("Delete", role: .destructive) {
                model.delete(listedItems(folders: folders, bookmarks: bookmarks).filter(selection.contains))
                endSelecting()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(BookmarkSelectionWording.deleteMessage(folders: selectedFolderIDs.count, bookmarks: selection.count - selectedFolderIDs.count))
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
        .sheet(item: $folderToMove) { folder in
            BookmarkMovePicker(
                destinations: BookmarkDestinations.rows(folders: store.bookmarkFolders, excluding: folder.id),
                currentFolderID: folder.parentID
            ) { destination in
                model.move(folder, to: destination)
            }
        }
        .sheet(isPresented: $isImporting) {
            BookmarkImportSheet(store: store)
        }
        .sheet(item: $folderEditor) { request in
            switch request {
            case .edit(let folder): FolderEditorSheet(folder: folder, store: store)
            case .create(let parentID): FolderEditorSheet(newIn: parentID, store: store)
            }
        }
    }

    /// Browsing: Done, Select when there is anything to select, and the
    /// bottom bar's New Folder with Edit Folder inside a folder or Import at
    /// the top. All in words, at the bottom where a thumb is: touch and hold
    /// alone was too hidden for anybody to learn that a folder can have its
    /// own icon. Words only, because iOS 26 draws a toolbar `Label` as its
    /// icon alone whatever its label style — measured on September 29, 2026,
    /// when these showed as a bare folder and a bare pencil.
    @ToolbarContentBuilder
    private func browsingToolbar(hasItems: Bool) -> some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done", action: close)
        }
        if hasItems {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Select") { isSelecting = true }
            }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Button("New Folder") {
                folderEditor = .create(parentID: folderID)
            }
            if let current = folderID.flatMap(store.bookmarkFolder(id:)) {
                Spacer()
                Button("Edit Folder") {
                    folderEditor = .edit(current)
                }
            } else {
                // Import belongs to the top: what it brings lands there or in
                // one new folder there, never inside the folder on screen.
                Spacer()
                Button("Import") {
                    isImporting = true
                }
            }
        }
    }

    /// Selecting, as Files does: Select All at the left, the count as the
    /// title, Cancel at the right, and what can be done with the ticked rows
    /// at the bottom, each saying how many it will act on.
    @ToolbarContentBuilder
    private func selectingToolbar(listed: [BookmarkItemID]) -> some ToolbarContent {
        let allTicked = !listed.isEmpty && Set(listed).isSubset(of: selection)
        ToolbarItem(placement: .topBarLeading) {
            Button(allTicked ? "Deselect All" : "Select All") {
                selection = allTicked ? [] : Set(listed)
            }
        }
        ToolbarItem(placement: .principal) {
            Text(BookmarkSelectionWording.selectedCount(selection.count))
                .font(.headline)
                .foregroundStyle(LimeghostTheme.textPrimary)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Cancel") { endSelecting() }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Button("Move to\u{2026} (\(selection.count))") { isMovingSelection = true }
                .disabled(selection.isEmpty)
            Spacer()
            // Red, as a delete is everywhere else: in the bottom bar the
            // destructive role alone drew it in the sheet's green.
            Button("Delete (\(selection.count))", role: .destructive) { isConfirmingSelectionDelete = true }
                .tint(.red)
                .disabled(selection.isEmpty)
        }
    }

    /// Everything listed, in the order it is shown: folders, then bookmarks.
    /// What is ticked is acted on in this order, so it arrives in it.
    private func listedItems(folders: [BookmarkFolderRecord], bookmarks: [BookmarkRecord]) -> [BookmarkItemID] {
        folders.map { .folder($0.id) } + bookmarks.map { .bookmark($0.id) }
    }

    private var selectedFolderIDs: Set<UUID> {
        Set(selection.compactMap { item in
            if case .folder(let id) = item { return id }
            return nil
        })
    }

    private func endSelecting() {
        isSelecting = false
        selection = []
    }

    /// While selecting, a row is only its tick, mark and name: a tap ticks
    /// it, and opening, swiping and touch and hold wait until Cancel.
    @ViewBuilder
    private func folderRow(_ folder: BookmarkFolderRecord) -> some View {
        if isSelecting {
            HStack(spacing: 12) {
                BookmarkFolderIcon(folder: folder)
                Text(folder.title)
                    .foregroundStyle(LimeghostTheme.textPrimary)
                    .lineLimit(1)
            }
            .listRowBackground(LimeghostTheme.bg2)
            .tag(BookmarkItemID.folder(folder.id))
        } else {
            browsingFolderRow(folder)
        }
    }

    @ViewBuilder
    private func bookmarkRow(_ bookmark: BookmarkRecord) -> some View {
        if isSelecting {
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
            .listRowBackground(LimeghostTheme.bg2)
            .tag(BookmarkItemID.bookmark(bookmark.id))
        } else {
            browsingBookmarkRow(bookmark)
        }
    }

    private func browsingFolderRow(_ folder: BookmarkFolderRecord) -> some View {
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
                folderEditor = .edit(folder)
            } label: {
                Label("Edit Folder…", systemImage: "pencil")
            }
            Button {
                folderToMove = folder
            } label: {
                Label("Move to…", systemImage: "folder")
            }
            Divider()
            Button(role: .destructive) {
                requestDeletion(folder)
            } label: {
                Label("Delete Folder", systemImage: "trash")
            }
        }
    }

    private func browsingBookmarkRow(_ bookmark: BookmarkRecord) -> some View {
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
            // The moment somebody wants their old bookmarks is the moment
            // the list is empty, so Import is offered here too.
            ContentUnavailableView {
                Label("No Bookmarks Yet", systemImage: "book")
            } description: {
                Text("Add Bookmark in the menu saves the page you're on.")
            } actions: {
                Button("Import Bookmarks\u{2026}") {
                    isImporting = true
                }
            }
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

    /// The field starts from the current name.
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
