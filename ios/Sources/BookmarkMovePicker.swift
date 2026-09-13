import LimeghostCore
import SwiftUI

/// One place a bookmark can be moved to: the top level, or a folder, with how
/// far to indent it.
struct BookmarkDestination: Identifiable, Equatable {
    /// Nil is the top level.
    let folder: BookmarkFolderRecord?
    let depth: Int

    var folderID: UUID? { folder?.id }
    var id: String { folder?.id.uuidString ?? "top-level" }
    var title: String { folder?.title ?? "Bookmarks" }
}

enum BookmarkDestinations {
    /// The top level first, then every folder with its children beneath it,
    /// alphabetical within a parent: Core's tree with every branch open, the
    /// order the Mac's own tree and Move menu use. The Mac labels each folder
    /// with its whole path instead, which is too wide to read on a phone.
    static func rows(folders: [BookmarkFolderRecord]) -> [BookmarkDestination] {
        let tree = BookmarkTree.rows(folders: folders, bookmarks: [], expanded: Set(folders.map(\.id)))
        return [BookmarkDestination(folder: nil, depth: 0)]
            + tree.map { BookmarkDestination(folder: $0.folder, depth: $0.depth + 1) }
    }
}

/// Move to…: every place a bookmark can go, with a checkmark where it is now.
/// A tap files it there and closes; Cancel closes without moving anything.
struct BookmarkMovePicker: View {
    let destinations: [BookmarkDestination]
    let currentFolderID: UUID?
    let choose: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(destinations) { destination in
                Button {
                    choose(destination.folderID)
                    dismiss()
                } label: {
                    row(destination)
                }
                .listRowBackground(LimeghostTheme.bg2)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Move to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .limeghostListSheet()
    }

    private func row(_ destination: BookmarkDestination) -> some View {
        HStack(spacing: 12) {
            if let folder = destination.folder {
                BookmarkFolderIcon(folder: folder)
            } else {
                Image(systemName: "book")
                    .font(.system(size: 15))
                    .foregroundStyle(LimeghostTheme.accent)
                    .frame(width: LimeghostTheme.siteIconSize, height: LimeghostTheme.siteIconSize)
            }
            Text(destination.title)
                .foregroundStyle(LimeghostTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 12)
            if destination.folderID == currentFolderID {
                Image(systemName: "checkmark")
                    .foregroundStyle(LimeghostTheme.accent)
                    .accessibilityLabel("Current place")
            }
        }
        .padding(.leading, CGFloat(destination.depth) * 16)
        .contentShape(Rectangle())
    }
}
