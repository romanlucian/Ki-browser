import ClearframeCore
import SwiftUI

/// The assistant panel: a header naming who you are talking to, and that
/// assistant's own website underneath. One column normally; two when you ask to
/// compare answers.
///
/// Deliberately thin. Everything below a header is that provider's page,
/// rendered as any other page is. Clearframe does not reach into it, does not
/// read what it says, and does not type into it — the person pastes, asks and
/// sends, exactly as they would in a tab. That holds in Compare too: two columns
/// means asking twice, by hand. Filling both from one box would be automated
/// access to services Clearframe has no agreement with.
struct AICompanionPanel: View {
    @ObservedObject var companion: AICompanion
    /// Whether the window is wide enough for two readable columns. Decided by
    /// the window and passed down, because the panel does not know its own size.
    var allowsComparison: Bool

    var body: some View {
        HStack(spacing: 0) {
            column(for: companion.tool, isComparison: false)
            if showsComparison, let second = companion.comparisonTool {
                Divider()
                column(for: second, isComparison: true)
            }
        }
        .background(ClearframeTheme.bg1)
    }

    /// Comparing is a request, not a state the window is obliged to honour: a
    /// window narrowed below two readable columns shows one and remembers the
    /// other, rather than squeezing both into a shape neither provider designed
    /// their page for.
    private var showsComparison: Bool { companion.isComparing && allowsComparison }

    private func column(for tool: AIToolListing, isComparison: Bool) -> some View {
        VStack(spacing: 0) {
            header(for: tool, isComparison: isComparison)
            Divider()
            if let session = companion.session(for: tool) {
                // Keyed on the session, because `WebView` hands SwiftUI an
                // existing `WKWebView` from `makeNSView` and has nothing to do in
                // `updateNSView` — there is no way to swap the returned view
                // afterwards. Without this the header changed to the new
                // assistant while the old one's page stayed underneath it.
                WebView(session: session)
                    .id(session.instanceID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func header(for tool: AIToolListing, isComparison: Bool) -> some View {
        HStack(spacing: 8) {
            // The icon sits outside the menu deliberately. A `resizable()` image
            // inside a `Menu` label is not constrained by its own frame on macOS —
            // it rendered several times its 18-point size, with the favicon's white
            // background behind it.
            SiteIconView(urlString: tool.officialURL.absoluteString)

            Menu {
                ForEach(AICompanion.choices) { choice in
                    Button {
                        if isComparison {
                            companion.selectComparison(choice)
                        } else {
                            companion.select(choice)
                        }
                    } label: {
                        if choice.id == tool.id {
                            Label(choice.name, systemImage: "checkmark")
                        } else {
                            Text(choice.name)
                        }
                    }
                    // The other column already has it. Two columns showing the
                    // same assistant would compare it against itself.
                    .disabled(showsComparison && choice.id == otherTool(isComparison: isComparison)?.id)
                }
            } label: {
                HStack(spacing: 5) {
                    Text(tool.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ClearframeTheme.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(ClearframeTheme.textTertiary)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Choose which assistant sits here")

            Spacer(minLength: 6)

            // The one line worth carrying in the interface: this is their site,
            // their account, and their terms — not something Clearframe provides.
            Text("your own account")
                .font(.system(size: 10))
                .foregroundStyle(ClearframeTheme.textTertiary)

            if isComparison {
                Button { companion.stopComparing() } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(GhostButtonStyle())
                .help("Close this second assistant")
                .accessibilityLabel("Close the second assistant")
            } else {
                compareButton
                // No expand control while comparing. Two columns need the whole
                // window, so the button could only ever be shown lit and doing
                // nothing — which reads as broken rather than as unavailable.
                // The compare button beside it is the way back.
                if !companion.isComparing {
                    Button { companion.toggleExpanded() } label: {
                        Image(systemName: companion.isExpanded
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(GhostButtonStyle(isActive: companion.isExpanded))
                    .help(companion.isExpanded ? "Share the window with the page" : "Fill the window")
                    .accessibilityLabel(companion.isExpanded ? "Shrink the assistant" : "Expand the assistant")
                }

                Button { companion.hide() } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(GhostButtonStyle())
                .help("Close the assistant")
                .accessibilityLabel("Close the assistant")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
    }

    private var compareButton: some View {
        Button {
            companion.isComparing ? companion.stopComparing() : companion.startComparing()
        } label: {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(GhostButtonStyle(isActive: companion.isComparing))
        .disabled(!allowsComparison && !companion.isComparing)
        // Narrowing the window while comparing must still leave a way out, so
        // the wording follows what pressing it does rather than the width.
        .help(companion.isComparing
              ? "Back to one assistant"
              : (allowsComparison
                 ? "Compare answers — ask two assistants the same thing"
                 : "The window is too narrow for two assistants side by side"))
        .accessibilityLabel(companion.isComparing ? "Back to one assistant" : "Compare answers")
    }

    private func otherTool(isComparison: Bool) -> AIToolListing? {
        isComparison ? companion.tool : companion.comparisonTool
    }
}
