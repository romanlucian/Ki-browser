import AppKit
import LimeghostCore
import SwiftUI

/// A profile's face, wherever one is shown.
///
/// Three ways of having one, in order: a picture the person chose, a drawing
/// from the catalogue, or the coloured initials every profile has always had.
/// The order matters — a picture is the most deliberate choice somebody can
/// make here, so it wins.
struct ProfileAvatar: View {
    let profile: BrowserProfileRecord
    @ObservedObject var profiles: ProfileStore
    var size: CGFloat = 26

    private var tint: Color {
        Color(TabGroupPalette.color(for: profile.colorID))
    }

    var body: some View {
        Group {
            if let url = profiles.pictureURL(for: profile), let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else if let iconID = profile.iconID, LimeghostIconCatalog.icon(id: iconID) != nil {
                LimeghostIconView(iconID: iconID, size: size * 0.58)
                    .foregroundStyle(tint)
                    .frame(width: size, height: size)
                    .background(tint.opacity(0.16))
            } else {
                Text(profile.initials)
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(LimeghostTheme.bg0)
                    .frame(width: size, height: size)
                    .background(tint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// The toolbar chip and the switcher behind it.
///
/// Chrome puts a coloured blob here and Vivaldi a stock photograph. Limeghost
/// already ships 1,465 drawings for bookmark folders, so a profile can be a red
/// panda without a single new asset.
struct ProfileSwitcherChip: View {
    @ObservedObject var profiles: ProfileStore
    let currentProfileID: UUID
    let openWindow: (UUID) -> Void
    let edit: (UUID) -> Void
    let addProfile: () -> Void

    @State private var showsPopover = false

    private var current: BrowserProfileRecord? {
        profiles.profile(currentProfileID)
    }

    var body: some View {
        if let current {
            Button { showsPopover = true } label: {
                HStack(spacing: 4) {
                    ProfileAvatar(profile: current, profiles: profiles, size: 20)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(LimeghostTheme.textTertiary)
                }
                .padding(.horizontal, 5)
                .frame(height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Profile: \(current.name). Click to switch or edit.")
            .accessibilityLabel("Profile: \(current.name)")
            .popover(isPresented: $showsPopover, arrowEdge: .bottom) {
                switcher(current: current)
            }
        }
    }

    private func switcher(current: BrowserProfileRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(profiles.profiles) { profile in
                Button {
                    showsPopover = false
                    // Switching means a window in that profile: a profile owns
                    // its cookies and its logins, so one window cannot be half
                    // in each.
                    if profile.id != currentProfileID { openWindow(profile.id) }
                } label: {
                    HStack(spacing: 9) {
                        ProfileAvatar(profile: profile, profiles: profiles, size: 22)
                        Text(profile.name)
                            .font(.system(size: 13))
                            .lineLimit(1)
                        Spacer(minLength: 10)
                        if profile.id == currentProfileID {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(LimeghostTheme.accent)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Divider().padding(.vertical, 5)

            switcherAction("Edit this profile…", symbol: "pencil") {
                showsPopover = false
                edit(currentProfileID)
            }
            switcherAction("New profile…", symbol: "plus") {
                showsPopover = false
                addProfile()
            }
        }
        .padding(7)
        .frame(width: 236)
        .background(LimeghostTheme.bg2)
    }

    private func switcherAction(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LimeghostTheme.textSecondary)
                    .frame(width: 22)
                Text(title).font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Name, face and colour, in one sheet.
///
/// It replaces two `NSAlert`-shaped prompts that could set a name and nothing
/// else. One place to edit a profile rather than two, which is the same
/// argument that removed the second Copy button from the toolbar.
struct ProfileEditor: View {
    @ObservedObject var profiles: ProfileStore
    let profileID: UUID
    let dismiss: () -> Void

    @State private var name: String = ""
    @State private var colorID: String = TabGroupRecord.colorIDs[1]
    @State private var iconID: String = ""
    @State private var style: LimeghostIconStyle = .limeghost
    @State private var pictureFailed = false
    @State private var loaded = false

    private var profile: BrowserProfileRecord? { profiles.profile(profileID) }

    private var tint: Color { Color(TabGroupPalette.color(for: colorID)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            TextField("Name", text: $name, prompt: Text("Work, Personal, a project…"))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))

            colourRow

            Divider()

            LimeghostIconPicker(
                iconID: $iconID,
                style: $style,
                tint: tint,
                gridHeight: 210
            )

            if pictureFailed {
                Label("That file could not be read as an image.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Choose a picture…") { choosePicture() }
                if profile?.pictureFileName != nil {
                    Button("Remove picture") {
                        profiles.removePicture(for: profileID)
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(LimeghostTheme.accent)
                    .foregroundStyle(LimeghostTheme.onAccent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .background(LimeghostTheme.bg1)
        .onAppear(perform: load)
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let profile {
                ProfileAvatar(profile: profile, profiles: profiles, size: 52)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? "This profile" : name)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                Text("Its own bookmarks, history, logins and cookies.")
                    .font(.caption)
                    .foregroundStyle(LimeghostTheme.textSecondary)
            }
            Spacer()
        }
    }

    private var colourRow: some View {
        HStack(spacing: 7) {
            ForEach(TabGroupRecord.colorIDs, id: \.self) { id in
                Button { colorID = id } label: {
                    Circle()
                        .fill(Color(TabGroupPalette.color(for: id)))
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle().stroke(
                                colorID == id ? Color.white : Color.white.opacity(0.14),
                                lineWidth: colorID == id ? 2 : 1
                            )
                        )
                }
                .buttonStyle(.plain)
                .help(id.capitalized)
                .accessibilityLabel(id)
            }
            Spacer()
        }
    }

    private func load() {
        guard !loaded, let profile else { return }
        loaded = true
        name = profile.name
        colorID = profile.colorID
        iconID = profile.iconID ?? ""
        style = profile.iconID.flatMap { LimeghostIconCatalog.icon(id: $0)?.style } ?? .limeghost
    }

    private func choosePicture() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "Use picture"
        panel.title = "Choose a profile picture"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pictureFailed = !profiles.setPicture(from: url, for: profileID)
        if !pictureFailed { iconID = "" }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        profiles.rename(profileID, to: trimmed)
        profiles.recolor(profileID, to: colorID)
        // Only touch the icon when one is chosen: setIcon clears any picture,
        // and saving a name should not silently delete a photograph.
        if !iconID.isEmpty, iconID != profile?.iconID {
            profiles.setIcon(iconID, for: profileID)
        }
        dismiss()
    }
}

/// A profile id that `.sheet(item:)` will accept. `UUID` is not `Identifiable`,
/// and giving it that conformance here would put it on every UUID in the app.
struct EditedProfile: Identifiable {
    let id: UUID
}
