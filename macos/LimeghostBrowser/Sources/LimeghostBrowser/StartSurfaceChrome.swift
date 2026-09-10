import SwiftUI

/// The furniture the full-page start surfaces share.
///
/// Bookmarks and history are separate destinations on purpose — one is a
/// collection somebody arranges, the other a log they search — but they are
/// two views of one app and should not drift apart by a point of padding or
/// a shade of grey. Anything both pages draw the same way lives here so it
/// can only be changed for both at once.
enum StartSurfaceChrome {}

/// The search field at the top of a start surface.
struct HomeSearchField: View {
    let placeholder: String
    @Binding var text: String
    /// How wide the field is allowed to grow. Bookmarks and history keep it
    /// beside their own content at 440; the AI home lets it run the width of
    /// the page, where finding a tool is the page's whole purpose.
    var maximumWidth: CGFloat = 440

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LimeghostTheme.textTertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(LimeghostTheme.textPrimary)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(LimeghostTheme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 34)
        .frame(maxWidth: maximumWidth)
        .background(LimeghostTheme.bg1, in: RoundedRectangle(cornerRadius: LimeghostTheme.radius10))
        .overlay(
            RoundedRectangle(cornerRadius: LimeghostTheme.radius10)
                .stroke(LimeghostTheme.hairline2)
        )
    }
}

/// A small-caps heading with the number of things under it and a rule to the
/// edge.
struct HomeSectionTitle: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(LimeghostTheme.metaFont)
                .tracking(LimeghostTheme.metaTracking)
                .foregroundStyle(LimeghostTheme.textSecondary)
            Text("\(count)")
                .font(LimeghostTheme.metaFont)
                .tracking(LimeghostTheme.metaTracking)
                .foregroundStyle(LimeghostTheme.textTertiary)
            Rectangle()
                .fill(LimeghostTheme.hairline1)
                .frame(height: 1)
        }
    }
}

/// What a section says when it has nothing in it. Always a sentence about
/// what would appear here, never a bare "Nothing found".
struct HomeEmptyNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(LimeghostTheme.textTertiary)
            .padding(.vertical, 14)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LimeghostTheme.bg1, in: RoundedRectangle(cornerRadius: LimeghostTheme.radius12))
    }
}

extension StartSurfaceChrome {
    /// The fill every card on a start surface takes.
    ///
    /// Opaque on purpose, and a test enforces it. The AI home drew its tool
    /// cards as `Color.white.opacity(0.07)` over a background gradient running
    /// `bg0` → `bg1`, which is alpha arithmetic against a moving surface:
    /// composited over `bg0` the card landed at 30 — *darker* than the `bg1`
    /// plane it was supposed to float above — and over `bg1` at 57, level with
    /// `bg3`, the address pill and the most raised surface in the app. One
    /// literal, two contradictory results, and no opacity value could ever
    /// land it on `bg2` where a card belongs.
    ///
    /// The same page already had this right in three other places, which is
    /// what made it hard to see: the tool row, the start card and the boundary
    /// block all used the flat token.
    static let cardFill = LimeghostTheme.bg2

    /// The hairline around a card. One value, so the page's three cards stop
    /// disagreeing about their own edge.
    static let cardStroke = LimeghostTheme.hairline2

    /// One radius for a start-surface card. The AI home used 16, 16 and 13 for
    /// the same role on one screen.
    static let cardRadius = LimeghostTheme.radius14
}

extension View {
    /// A card on a start surface: one fill, one hairline, one radius.
    func startSurfaceCard() -> some View {
        self
            .background(
                StartSurfaceChrome.cardFill,
                in: RoundedRectangle(cornerRadius: StartSurfaceChrome.cardRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StartSurfaceChrome.cardRadius, style: .continuous)
                    .stroke(StartSurfaceChrome.cardStroke)
            )
    }
}
