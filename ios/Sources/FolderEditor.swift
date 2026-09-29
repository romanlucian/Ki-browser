import LimeghostCore
import LimeghostShared
import SwiftUI

/// A folder being edited or made — its name, icon and colour, and the icon
/// set being browsed — held apart from the store until Save or Create, as the
/// Mac's `BookmarkFolderEditor` holds them. A value, so a test can make one,
/// change it and save it. On the main actor, as the icon lookups it asks are.
@MainActor
struct FolderEdit {
    /// The folder being changed, or nil for a new one.
    let folderID: UUID?
    /// Where a new folder goes: the folder on screen, or the top level.
    let parentID: UUID?
    var title: String
    var iconID: String
    var color: LimeghostIconColor
    /// The set being browsed. It opens on the set the folder's icon belongs
    /// to, so editing a folder never silently moves it to another set's grid.
    var style: LimeghostIconStyle

    init(folder: BookmarkFolderRecord) {
        folderID = folder.id
        parentID = folder.parentID
        title = folder.title
        // The icon the folder actually draws, which for one saved before
        // icons existed is the match for its old emoji: the Mac's rule.
        iconID = LimeghostIconGeometry.iconID(for: folder)
        color = LimeghostIconColor(id: folder.colorID) ?? .mint
        style = LimeghostIconCatalog.icon(id: iconID)?.style ?? .limeghost
    }

    /// A new folder inside `parentID`: no name yet, the plain folder, and
    /// mint, which is what the Mac's New Folder opens with. New Folder opens
    /// this screen rather than an alert asking only for a name, so everybody
    /// who makes a folder sees that it can have an icon — the founder found
    /// touch and hold too hidden to be the only way to learn it.
    init(newIn parentID: UUID?) {
        folderID = nil
        self.parentID = parentID
        title = ""
        iconID = LimeghostIconCatalog.defaultIconID
        color = .mint
        style = .limeghost
    }

    var isNew: Bool { folderID == nil }

    /// Whether the icon Save would keep takes a tint. Asked of the chosen
    /// icon, not of the set being browsed: browsing Stickies with a Limeghost
    /// icon still chosen must not hide the colour that icon really uses.
    var selectedIsTintable: Bool { LimeghostIconGeometry.isTintable(iconID: iconID) }

    /// An empty name cannot be saved, as on the Mac.
    var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Name, icon and colour in one update — or, for a new folder, one
    /// creation where it was asked for — as the Mac's Save writes them.
    /// The colour is kept even for a multicolour icon, which ignores it, so
    /// going back to a tintable one finds the colour it had.
    func save(to store: BrowserDataStore) {
        guard canSave else { return }
        guard let folderID else {
            _ = store.createBookmarkFolder(title: title, iconID: iconID, colorID: color.rawValue, parentID: parentID)
            return
        }
        store.updateBookmarkFolder(id: folderID, title: title, iconID: iconID, colorID: color.rawValue)
    }
}

/// Which folder the editor opens on: one to change, or a new one inside a
/// parent. One value, so one sheet serves New Folder, Edit Folder in the
/// bottom bar, and Edit Folder… on touch and hold.
enum FolderEditorRequest: Identifiable {
    case edit(BookmarkFolderRecord)
    case create(parentID: UUID?)

    var id: String {
        switch self {
        case .edit(let folder): return "edit-\(folder.id.uuidString)"
        case .create(let parentID): return "create-\(parentID?.uuidString ?? "top")"
        }
    }
}

/// Edit Folder, over Bookmarks: a folder's name, icon and colour on one
/// screen, as the Mac's folder editor has them, and the Mac's own picker —
/// compiled here by reference — so both apps offer the same drawings through
/// the same code. Three ways in, two of them in words: New Folder, Edit
/// Folder in a folder's bottom bar, and Edit Folder… on touch and hold. It
/// replaced Rename… for folders and the New Folder alert on September 29,
/// 2026, at the founder's choice, so a folder has one place to change.
struct FolderEditorSheet: View {
    private let store: BrowserDataStore
    @State private var edit: FolderEdit
    @FocusState private var isNaming: Bool
    @Environment(\.dismiss) private var dismiss

    init(folder: BookmarkFolderRecord, store: BrowserDataStore) {
        self.store = store
        _edit = State(initialValue: FolderEdit(folder: folder))
    }

    /// New Folder: the same screen, making one inside `parentID`.
    init(newIn parentID: UUID?, store: BrowserDataStore) {
        self.store = store
        _edit = State(initialValue: FolderEdit(newIn: parentID))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    preview
                    TextField("Folder name", text: $edit.title)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                        .focused($isNaming)
                }
                if edit.selectedIsTintable {
                    colours
                }
                LimeghostIconPicker(
                    iconID: $edit.iconID,
                    style: $edit.style,
                    tint: edit.selectedIsTintable ? Color(edit.color) : nil,
                    gridHeight: nil,
                    cellSize: 44
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .navigationTitle(edit.isNew ? "New Folder" : "Edit Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(edit.isNew ? "Create" : "Save") {
                        edit.save(to: store)
                        dismiss()
                    }
                    .disabled(!edit.canSave)
                }
            }
            // A new folder starts with its name, as the alert it replaced
            // did; an existing one opens on its icons.
            .onAppear { if edit.isNew { isNaming = true } }
        }
        .limeghostListSheet()
    }

    /// The chosen icon at the size a folder row draws it, so the preview is a
    /// preview and not a flattering enlargement.
    @ViewBuilder
    private var preview: some View {
        let icon = LimeghostIconView(iconID: edit.iconID, size: LimeghostTheme.siteIconSize)
        Group {
            if edit.selectedIsTintable {
                icon.foregroundStyle(Color(edit.color))
            } else {
                icon
            }
        }
        .frame(width: 44, height: 44)
        .background(LimeghostTheme.bg3, in: RoundedRectangle(cornerRadius: LimeghostTheme.radius9))
        .accessibilityHidden(true)
    }

    /// The Mac's four tints, as dots a finger can hit: 28 points drawn inside
    /// 44 of touch. Shown only for an icon that takes a tint — over a
    /// multicolour one it would be a control that does nothing.
    private var colours: some View {
        HStack(spacing: 4) {
            ForEach(LimeghostIconColor.allCases, id: \.self) { swatch in
                Button { edit.color = swatch } label: {
                    Circle()
                        .fill(Color(swatch))
                        .frame(width: 28, height: 28)
                        .overlay {
                            Circle()
                                .stroke(LimeghostTheme.textPrimary, lineWidth: swatch == edit.color ? 2.5 : 0)
                                .padding(-4)
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(swatch.title) icon colour")
                .accessibilityAddTraits(swatch == edit.color ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}
