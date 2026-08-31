import LimeghostCore
import SwiftUI

/// The list under the address bar, showing where what has been typed could go.
///
/// Every row is somewhere this profile has already been or saved, plus one row
/// that searches for the typed text. Nothing here was fetched: no keystroke
/// leaves the Mac to build this list, which is the one place a browser's
/// address bar most commonly does send what you are typing to a server.
struct AddressSuggestionsView: View {
    let suggestions: [AddressSuggestion]
    /// Which row Return would take, moved with the arrow keys.
    let selection: Int
    let typed: String
    let engineName: String
    let open: (AddressSuggestion) -> Void
    /// Which row the pointer is over. Kept here rather than reported upwards on
    /// purpose: the pointer moving across the list must not change where Return
    /// goes. The list appears directly under the field, so the pointer is very
    /// often resting on a row nobody chose.
    @State private var hoveredIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                row(suggestion, index: index)
            }
        }
        .padding(.vertical, 4)
        .background(LimeghostTheme.bg2)
        .clipShape(RoundedRectangle(cornerRadius: LimeghostTheme.radius10))
        .overlay(
            RoundedRectangle(cornerRadius: LimeghostTheme.radius10)
                .stroke(LimeghostTheme.hairline2, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.42), radius: 18, y: 10)
    }

    private func row(_ suggestion: AddressSuggestion, index: Int) -> some View {
        let isSelected = index == selection || index == hoveredIndex
        return Button {
            open(suggestion)
        } label: {
            HStack(spacing: 9) {
                mark(for: suggestion)
                    .frame(width: LimeghostTheme.siteIconSize, height: LimeghostTheme.siteIconSize)

                Text(label(for: suggestion))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(LimeghostTheme.textPrimary)

                if case .place = suggestion.kind, !suggestion.url.isEmpty {
                    Text("—")
                        .font(.system(size: 12))
                        .foregroundStyle(LimeghostTheme.textTertiary)
                    Text(suggestion.url)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .font(.system(size: 12))
                        .foregroundStyle(LimeghostTheme.accent)
                        .layoutPriority(-1)
                }

                Spacer(minLength: 6)
            }
            .padding(.horizontal, 11)
            .frame(height: 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? LimeghostTheme.itemHover : Color.clear,
                in: RoundedRectangle(cornerRadius: LimeghostTheme.radius6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .onHover { hoveredIndex = $0 ? index : (hoveredIndex == index ? nil : hoveredIndex) }
        .accessibilityLabel(accessibilityLabel(for: suggestion))
        .accessibilityAddTraits(index == selection ? [.isButton, .isSelected] : .isButton)
    }

    /// A visited site shows its own icon, captured on a real visit; a search
    /// row shows a magnifier so the two are never confused for each other.
    @ViewBuilder
    private func mark(for suggestion: AddressSuggestion) -> some View {
        switch suggestion.kind {
        case .search:
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LimeghostTheme.textTertiary)
        case .place(let isBookmarked):
            ZStack(alignment: .bottomTrailing) {
                SiteIconView(urlString: "https://\(suggestion.url)")
                if isBookmarked {
                    Image(systemName: "star.fill")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(Color.orange)
                        .padding(1)
                        .background(LimeghostTheme.bg2, in: Circle())
                        .offset(x: 2, y: 2)
                }
            }
        }
    }

    private func label(for suggestion: AddressSuggestion) -> String {
        switch suggestion.kind {
        case .search: return "\(suggestion.title) — Search \(engineName)"
        case .place: return suggestion.title
        }
    }

    private func accessibilityLabel(for suggestion: AddressSuggestion) -> String {
        switch suggestion.kind {
        case .search: return "Search \(engineName) for \(suggestion.title)"
        case .place(let isBookmarked):
            let kind = isBookmarked ? "bookmark" : "from history"
            return "\(suggestion.title), \(suggestion.url), \(kind)"
        }
    }
}
