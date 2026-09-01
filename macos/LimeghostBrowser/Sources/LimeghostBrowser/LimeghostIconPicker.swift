import LimeghostCore
import SwiftUI

/// The set chooser, search field and grid that pick one drawing from the
/// catalogue.
///
/// Extracted from the bookmark folder editor on September 1, 2026 so profile
/// avatars could use it rather than grow a second grid beside it. Two surfaces
/// offering the same 1,465 drawings through two pieces of code is how they
/// drift — one gets a search fix, the other does not.
///
/// It owns no selection of its own: the caller holds the chosen id and the
/// tint, because the folder editor stores a colour id and a profile stores a
/// palette colour, and neither should have to translate for the other.
struct LimeghostIconPicker: View {
    @Binding var iconID: String
    @Binding var style: LimeghostIconStyle
    /// The colour a tintable icon takes. Nil draws the artwork untinted, which
    /// is what a licensed set wants — it brings its own colours.
    let tint: Color?
    var gridHeight: CGFloat = 240

    @State private var search = ""

    private var isTintable: Bool { style.isTintable }

    /// Matches on the icon's own name and its category, so "work" finds the
    /// whole work set and "plane" finds the one icon. Scoped to the chosen
    /// style: the sets are different visual languages, and a grid that mixed
    /// them would invite a bar that mixes them too.
    private var matches: [LimeghostIconCategory: [LimeghostIcon]] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return LimeghostIconCatalog.byCategory(style: style) }
        var result: [LimeghostIconCategory: [LimeghostIcon]] = [:]
        for category in LimeghostIconCategory.allCases {
            let icons = LimeghostIconCatalog.icons(in: category, style: style).filter {
                $0.displayName.contains(query) || category.title.lowercased().contains(query)
            }
            if !icons.isEmpty { result[category] = icons }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Icon set", selection: $style) {
                ForEach(LimeghostIconCatalog.availableStyles, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField("Search icons", text: $search)
                .textFieldStyle(.roundedBorder)

            grid

            // Attribution stays visible wherever the artwork is offered. The
            // licensed sets are CC BY and CC BY-SA; the credit is the licence.
            if let attribution = style.attribution {
                Text(attribution)
                    .font(.system(size: 10.5))
                    .foregroundStyle(LimeghostTheme.textTertiary)
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(LimeghostIconCategory.allCases, id: \.self) { category in
                    if let icons = matches[category], !icons.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(category.title.uppercased())
                                .font(LimeghostTheme.metaFont)
                                .tracking(LimeghostTheme.metaTracking)
                                .foregroundStyle(LimeghostTheme.textTertiary)
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 38, maximum: 38), spacing: 6)],
                                alignment: .leading,
                                spacing: 6
                            ) {
                                ForEach(icons) { icon in
                                    cell(icon)
                                }
                            }
                        }
                    }
                }
                if matches.isEmpty {
                    Text("No icon matches “\(search)”.")
                        .font(.callout)
                        .foregroundStyle(LimeghostTheme.textSecondary)
                        .padding(.vertical, 18)
                }
            }
            .padding(.vertical, 2)
        }
        .frame(height: gridHeight)
    }

    private func cell(_ icon: LimeghostIcon) -> some View {
        let isSelected = icon.id == iconID
        return Button { iconID = icon.id } label: {
            artwork(icon, isSelected: isSelected)
                .frame(width: 38, height: 38)
                .background(
                    // A tintable icon inverts into its tint when chosen. A
                    // multicolour one cannot — recolouring it would do nothing
                    // — so selection is a ring around artwork left alone.
                    isSelected && isTintable ? (tint ?? LimeghostTheme.accent) : LimeghostTheme.bg3,
                    in: RoundedRectangle(cornerRadius: LimeghostTheme.radius6)
                )
                .overlay {
                    if isSelected && !isTintable {
                        RoundedRectangle(cornerRadius: LimeghostTheme.radius6)
                            .stroke(LimeghostTheme.accent, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(icon.displayName)
        .accessibilityLabel(icon.displayName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func artwork(_ icon: LimeghostIcon, isSelected: Bool) -> some View {
        let drawing = LimeghostIconView(iconID: icon.id, size: 22)
        if isTintable {
            drawing.foregroundStyle(isSelected ? LimeghostTheme.bg0 : (tint ?? LimeghostTheme.accent))
        } else {
            drawing
        }
    }
}
