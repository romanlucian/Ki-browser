import LimeghostShared
import SwiftUI

/// A page notice, floating just above the bottom bar: what Copy for AI
/// copied, a bookmark added or removed, or why something could not be done.
///
/// The session writes the words and clears them after eight seconds; this only
/// draws them. A tap dismisses it sooner. A rounded rectangle rather than a
/// capsule, because the longest notices run to three lines.
struct NoticeBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        Button(action: dismiss) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(LimeghostTheme.textPrimary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    LimeghostTheme.bg3,
                    in: RoundedRectangle(cornerRadius: LimeghostTheme.radius14, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LimeghostTheme.radius14, style: .continuous)
                        .stroke(LimeghostTheme.hairline3)
                )
                .shadow(color: .black.opacity(0.28), radius: 12, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Dismisses this notice")
        .padding(.horizontal, 16)
    }
}

/// The selected session's notice, if it has one. Its own view so it can
/// observe the session, whose notices the workspace never hears about.
struct NoticeLayer: View {
    @ObservedObject var session: BrowserSession

    var body: some View {
        VStack {
            if let notice = session.pageNotice {
                NoticeBanner(message: notice) { session.dismissPageNotice() }
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: session.pageNotice)
    }
}
