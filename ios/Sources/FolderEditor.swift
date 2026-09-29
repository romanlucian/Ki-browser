import LimeghostCore
import LimeghostShared
import SwiftUI

/// A folder being edited — its name, icon and colour, and the icon set being
/// browsed — held apart from the store until Save, as the Mac's
/// `BookmarkFolderEditor` holds them. A value, so a test can make one, change
/// it and save it. On the main actor, as the icon lookups it asks are.
@MainActor
struct FolderEdit {
    let folder: BookmarkFolderRecord
    var title: String
    var iconID: String
    var color: LimeghostIconColor
    /// The set being browsed. It opens on the set the folder's icon belongs
    /// to, so editing a folder never silently moves it to another set's grid.
    var style: LimeghostIconStyle

    init(folder: BookmarkFolderRecord) {
        self.folder = folder
        title = folder.title
        // The icon the folder actually draws, which for one saved before
        // icons existed is the match for its old emoji: the Mac's rule.
        iconID = LimeghostIconGeometry.iconID(for: folder)
        color = LimeghostIconColor(id: folder.colorID) ?? .mint
        style = LimeghostIconCatalog.icon(id: iconID)?.style ?? .limeghost
    }

    /// Whether the icon Save would keep takes a tint. Asked of the chosen
    /// icon, not of the set being browsed: browsing Stickies with a Limeghost
    /// icon still chosen must not hide the colour that icon really uses.
    var selectedIsTintable: Bool { LimeghostIconGeometry.isTintable(iconID: iconID) }

    /// An empty name cannot be saved, as on the Mac.
    var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Name, icon and colour in one update, as the Mac's Save writes them.
    /// The colour is kept even for a multicolour icon, which ignores it, so
    /// going back to a tintable one finds the colour it had.
    func save(to store: BrowserDataStore) {
        guard canSave else { return }
        store.updateBookmarkFolder(id: folder.id, title: title, iconID: iconID, colorID: color.rawValue)
    }
}

/// Edit Folder, over Bookmarks: a folder's name, icon and colour on one
/// screen, as the Mac's folder editor has them, and the Mac's own picker —
/// compiled here by reference — so both apps offer the same drawings through
/// the same code. Reached by touching and holding a folder. It replaced
/// Rename… for folders on September 29, 2026, at the founder's choice, so a
/// folder has one place to change and its menu stays short.
struct FolderEditorSheet: View {
    private let store: BrowserDataStore
    @State private var edit: FolderEdit
    @Environment(\.dismiss) private var dismiss

    init(folder: BookmarkFolderRecord, store: BrowserDataStore) {
        self.store = store
        _edit = State(initialValue: FolderEdit(folder: folder))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    preview
                    TextField("Folder name", text: $edit.title)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
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
            .navigationTitle("Edit Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        edit.save(to: store)
                        dismiss()
                    }
                    .disabled(!edit.canSave)
                }
            }
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
