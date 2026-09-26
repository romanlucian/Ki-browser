import LimeghostCore
import LimeghostShared
import SwiftUI

/// Whether a drag down on the assistant's header closes it: far enough that
/// it was meant, or fast enough that it was flung.
enum AssistantDismissal {
    static let distance: CGFloat = 120
    static let flung: CGFloat = 300

    static func closes(translation: CGFloat, predictedEnd: CGFloat) -> Bool {
        translation >= distance || predictedEnd >= flung
    }
}

/// Your own assistant, over the page. It is always in the same place in the
/// view tree and draws nothing while hidden: one layer in one place, never a
/// sheet. A sheet hosts its content in a separate hierarchy, which moves the
/// provider's web view between hosts, the destroy-and-rebuild `CLAUDE.md`
/// records.
struct AssistantLayer: View {
    @ObservedObject var companion: AICompanion
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            if companion.isVisible {
                Color.black.opacity(0.45)
                    .transition(.opacity)
                // The page is drawn under the keyboard and the assistant is
                // not, so while somebody typed, the page showed through the
                // strip between them — a headline behind the keyboard's own
                // bar. This carries the assistant's surface down there. It
                // starts below the corner radius so the rounded top still
                // shows the page behind it.
                LimeghostTheme.bg1
                    .padding(.top, 10 + LimeghostTheme.radius14)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .transition(.opacity)
                panel
                    .padding(.top, 10)
                    .offset(y: dragOffset)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeOut(duration: 0.22), value: companion.isVisible)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            AssistantHeader(companion: companion)
                .gesture(dismissDrag)
            Rectangle()
                .fill(LimeghostTheme.hairline2)
                .frame(height: 1)
            if let session = companion.session(for: companion.tool) {
                AssistantPageView(session: session)
                    .id(session.instanceID)
            } else {
                LimeghostTheme.bg1
            }
        }
        .background(LimeghostTheme.bg1)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: LimeghostTheme.radius14,
                topTrailingRadius: LimeghostTheme.radius14,
                style: .continuous
            )
        )
        .overlay {
            if let popup = companion.popup {
                AssistantPopupLayer(session: popup) { companion.dismissPopup() }
                    .id(popup.instanceID)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeOut(duration: 0.22), value: companion.popup?.instanceID)
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                if AssistantDismissal.closes(
                    translation: value.translation.height,
                    predictedEnd: value.predictedEndTranslation.height
                ) {
                    companion.closeColumn(companion.tool)
                }
                withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
            }
    }
}

/// Which assistant, whose account, and a way to close, in Reader's touch
/// header's anatomy. Never a page action: a Copy button here would read as
/// "send this to ChatGPT" (`CLAUDE.md`).
struct AssistantHeader: View {
    @ObservedObject var companion: AICompanion

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.28))
                .frame(width: 36, height: 5)
                .padding(.top, 6)
                .accessibilityHidden(true)
            HStack(spacing: 10) {
                SiteIconView(urlString: companion.tool.officialURL.absoluteString)
                Menu {
                    ForEach(AICompanion.choices) { choice in
                        Button {
                            companion.select(choice)
                        } label: {
                            if choice.id == companion.tool.id {
                                Label(choice.name, systemImage: "checkmark")
                            } else {
                                Text(choice.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(companion.tool.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(LimeghostTheme.textPrimary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(LimeghostTheme.textTertiary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Choose your assistant")
                .accessibilityValue(companion.tool.name)
                Spacer(minLength: 12)
                Text("your own account")
                    .font(.system(size: 13))
                    .foregroundStyle(LimeghostTheme.textTertiary)
                    .lineLimit(1)
                Button {
                    companion.closeColumn(companion.tool)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LimeghostTheme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(LimeghostTheme.bg3, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close the assistant")
            }
            .padding(.leading, 16)
            .padding(.trailing, 4)
        }
        .padding(.bottom, 4)
        .background(LimeghostTheme.bg2)
    }
}

/// The provider's own website, with a failure drawn over it rather than in
/// its place, so the web view stays mounted and a reload keeps it.
struct AssistantPageView: View {
    @ObservedObject var session: BrowserSession

    var body: some View {
        WebViewHost(session: session)
            .overlay {
                if case .failed(let failure) = session.loadState {
                    AssistantFailure(failure: failure) { session.reload() }
                }
            }
    }
}

/// What the session says went wrong, in its own words, with Reload where a
/// retry can help.
private struct AssistantFailure: View {
    let failure: BrowserFailure
    let reload: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.bubble")
                .font(.system(size: 28))
                .foregroundStyle(LimeghostTheme.textTertiary)
            Text(failure.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LimeghostTheme.textPrimary)
                .multilineTextAlignment(.center)
            Text(failure.message)
                .font(.system(size: 15))
                .foregroundStyle(LimeghostTheme.textSecondary)
                .multilineTextAlignment(.center)
            if failure.retryable {
                Button(action: reload) {
                    Label {
                        Text("Reload").foregroundStyle(LimeghostTheme.textPrimary)
                    } icon: {
                        Image(systemName: "arrow.clockwise").foregroundStyle(LimeghostTheme.accent)
                    }
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(LimeghostTheme.bg3, in: Capsule())
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LimeghostTheme.bg1)
    }
}

/// A window the assistant's page opened (a sign-in, in practice) over the
/// assistant: its own page's title and host, and a way to close.
struct AssistantPopupLayer: View {
    @ObservedObject var session: BrowserSession
    let close: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.5)
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: 36, height: 5)
                        .padding(.top, 6)
                        .accessibilityHidden(true)
                    HStack(spacing: 10) {
                        SiteIconView(urlString: session.currentURLString)
                        Text(session.pageTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(LimeghostTheme.textPrimary)
                            .lineLimit(1)
                        Text(URL(string: session.currentURLString)?.host ?? "")
                            .font(.system(size: 13))
                            .foregroundStyle(LimeghostTheme.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 12)
                        Button(action: close) {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(LimeghostTheme.textSecondary)
                                .frame(width: 30, height: 30)
                                .background(LimeghostTheme.bg3, in: Circle())
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close this window")
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 4)
                }
                .padding(.bottom, 4)
                .background(LimeghostTheme.bg2)
                Rectangle()
                    .fill(LimeghostTheme.hairline2)
                    .frame(height: 1)
                WebViewHost(session: session)
            }
            .background(LimeghostTheme.bg1)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: LimeghostTheme.radius14,
                    topTrailingRadius: LimeghostTheme.radius14,
                    style: .continuous
                )
            )
            .padding(.top, 26)
        }
    }
}
