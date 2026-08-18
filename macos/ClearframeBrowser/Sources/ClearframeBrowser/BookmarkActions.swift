import AppKit
import ClearframeCore
import SwiftUI

/// One request to edit a saved bookmark's name and address. Carries a fresh
/// `id` per request so `.sheet(item:)` re-presents the editor even when the
/// same bookmark is edited twice in a row.
struct BookmarkEditorRequest: Identifiable {
    let id = UUID()
    let bookmarkID: UUID
    let title: String
    let url: String

    init(bookmark: BookmarkRecord) {
        bookmarkID = bookmark.id
        title = bookmark.title
        url = bookmark.url
    }
}

/// What a surface knows about the page in front of the reader. The bookmarks
/// organizer has no page of its own, so it passes `nil` and its folder menus
/// simply leave the current-page entries out.
struct CurrentPageBookmarkState {
    /// False for start pages and anything else that is not a web link.
    let canSave: Bool
    /// The folder the page is already saved in, when it is saved at all.
    let savedFolderID: UUID?
    let isSaved: Bool

    init(canSave: Bool, currentBookmark: BookmarkRecord?) {
        self.canSave = canSave
        savedFolderID = currentBookmark?.folderID
        isSaved = currentBookmark != nil
    }
}

/// Menu wording that depends on live numbers, kept out of the view so the
/// exact sentence a reader sees is directly testable.
enum BookmarkMenuCopy {
    /// "Open all (4)" — the count is the folder's own saved pages, the ones
    /// the folder's menu lists directly above this entry.
    static func openAll(count: Int) -> String {
        "Open all (\(count))"
    }

    /// Shown in place of "Add current page" when the page is already filed in
    /// this exact folder, so the menu never offers a move that does nothing.
    static let currentPageAlreadyHere = "Current page is in this folder"

    static func addCurrentPage(isSavedElsewhere: Bool) -> String {
        isSavedElsewhere ? "Move current page here" : "Add current page"
    }
}

/// The single place a bookmark address is checked before it is saved, and the
/// sentence the editor shows when it is refused. Pure so the boundary is
/// testable without presenting a sheet.
enum BookmarkAddressValidation {
    static let guidance = """
        Enter a full web address that starts with http:// or https:// and \
        carries no username or password.
        """

    /// `nil` when Clearframe can save this address; otherwise the explanation
    /// to show under the field.
    static func problem(with address: String) -> String? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Enter the web address you want this bookmark to open." }
        return BookmarkURLPolicy.validatedURL(trimmed) == nil ? guidance : nil
    }
}

enum BookmarkClipboard {
    /// Copies a bookmark's address as plain text — the same thing a reader
    /// would get by selecting it in the address field.
    static func copyAddress(_ address: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(address, forType: .string)
    }
}

/// Editing sheet for one saved bookmark, built on the same shape and controls
/// as `BookmarkFolderEditor` so both editors feel like one product. Saving is
/// refused — and explained in place, with the sheet left open — when the
/// address is not a credential-free web link.
struct BookmarkEditor: View {
    let request: BookmarkEditorRequest
    /// Applies the edit. Returns false when the store refused it, which keeps
    /// the sheet open rather than quietly dropping the reader's changes.
    let save: (String, String) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var address: String
    @State private var problem: String?

    init(request: BookmarkEditorRequest, save: @escaping (String, String) -> Bool) {
        self.request = request
        self.save = save
        _title = State(initialValue: request.title)
        _address = State(initialValue: request.url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit bookmark")
                .font(.title2.bold())
            VStack(alignment: .leading, spacing: 5) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Bookmark name", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Bookmark name")
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Address")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("https://example.com/page", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Bookmark address")
                    .onChange(of: address) { _, _ in problem = nil }
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(problem)
                } else {
                    Text("Opens in this browser. Nothing is sent anywhere when you save it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { attemptSave() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 470)
    }

    private func attemptSave() {
        if let addressProblem = BookmarkAddressValidation.problem(with: address) {
            problem = addressProblem
            return
        }
        guard save(title, address) else {
            problem = BookmarkAddressValidation.guidance
            return
        }
        dismiss()
    }
}

/// The one bookmark menu every surface shows: the bookmarks bar, the organizer
/// popover, and the full-page bookmarks home all build their link menu here so
/// the same six actions read the same way wherever a saved page appears.
struct BookmarkLinkMenuItems: View {
    let bookmark: BookmarkRecord
    let destinations: [BookmarkFolderDestination]
    let open: () -> Void
    let openInNewTab: () -> Void
    let edit: () -> Void
    let move: (UUID?) -> Void
    let delete: () -> Void

    var body: some View {
        Button("Open", action: open)
        Button("Open in new tab", action: openInNewTab)
        Divider()
        Button("Edit…", action: edit)
        Button("Copy address") { BookmarkClipboard.copyAddress(bookmark.url) }
        Menu("Move to") {
            ForEach(destinations) { destination in
                Button {
                    move(destination.folderID)
                } label: {
                    if destination.folderID == bookmark.folderID {
                        Label(destination.label, systemImage: "checkmark")
                    } else {
                        Text(destination.label)
                    }
                }
            }
        }
        Divider()
        Button("Delete bookmark", role: .destructive, action: delete)
    }
}

/// The matching folder menu, shared by the bar's folder chips and the
/// organizer's folder rows and cards. Deleting keeps the folder's contents:
/// callers route `delete` through the same confirmation the organizer has
/// always used for a folder that still holds something.
struct BookmarkFolderMenuItems: View {
    let folder: BookmarkFolderRecord
    /// Saved pages filed directly in this folder — the ones "Open all" opens.
    let bookmarkCount: Int
    let currentPage: CurrentPageBookmarkState?
    let openAll: () -> Void
    let addCurrentPage: () -> Void
    let newSubfolder: () -> Void
    let rename: () -> Void
    let delete: () -> Void
    /// Present where a surface can hand the reader the full bookmarks page.
    let organize: (() -> Void)?

    var body: some View {
        Button(BookmarkMenuCopy.openAll(count: bookmarkCount), action: openAll)
            .disabled(bookmarkCount == 0)
        Divider()
        if let currentPage, currentPage.canSave {
            if currentPage.isSaved && currentPage.savedFolderID == folder.id {
                Button(BookmarkMenuCopy.currentPageAlreadyHere) {}
                    .disabled(true)
            } else {
                Button(
                    BookmarkMenuCopy.addCurrentPage(isSavedElsewhere: currentPage.isSaved),
                    action: addCurrentPage
                )
            }
        }
        Button("New subfolder…", action: newSubfolder)
        Button("Rename…", action: rename)
        Divider()
        Button("Delete folder", role: .destructive, action: delete)
        if let organize {
            Divider()
            Button("All bookmarks…", action: organize)
        }
    }
}
