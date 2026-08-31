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
        .frame(maxWidth: 440)
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
