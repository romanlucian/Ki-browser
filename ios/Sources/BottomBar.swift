import SwiftUI

/// What the bar shows, separate from how it draws, so a test can assert it
/// without standing up SwiftUI.
struct BottomBarModel {
    let urlString: String
    let tabCount: Int
    let canGoBack: Bool
    /// Lit while the assistant is open, as the Mac's toolbar button is.
    var isAssistantOpen: Bool = false

    /// What the button does next, for VoiceOver, as the menu's labels say.
    var assistantLabel: String { isAssistantOpen ? "Hide Assistant" : "Show Assistant" }

    /// The host, or an invitation.
    var addressLabel: String {
        guard let host = URL(string: urlString)?.host else {
            return urlString.isEmpty ? "Search or enter a website" : urlString
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// Back, the address, your assistant, the tabs and the page menu — within a thumb's reach,
/// along the bottom so the page's own top is left alone.
struct BottomBar: View {
    let model: BottomBarModel
    let goBack: () -> Void
    let openAddress: () -> Void
    let toggleAssistant: () -> Void
    let openTabs: () -> Void
    let openMenu: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: goBack) { Image(systemName: "chevron.backward") }
                .disabled(!model.canGoBack)
                .accessibilityLabel("Back")

            Button(action: openAddress) {
                Text(model.addressLabel)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.quaternary))
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel("Address")

            // Your own assistant, lit while it is open, as the Mac's toolbar
            // button is. Unlit it takes the bar's tint, like its neighbours,
            // until the phone's look is designed.
            Button(action: toggleAssistant) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 17))
                    .foregroundStyle(
                        model.isAssistantOpen ? AnyShapeStyle(LimeghostTheme.onAccent) : AnyShapeStyle(TintShapeStyle())
                    )
                    .frame(width: 38, height: 38)
                    .background(
                        model.isAssistantOpen ? LimeghostTheme.accent : Color.clear,
                        in: RoundedRectangle(cornerRadius: LimeghostTheme.radius8)
                    )
                    .frame(width: 44, height: 38)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(model.assistantLabel)

            Button(action: openTabs) {
                Text("\(model.tabCount)")
                    .font(.footnote.weight(.semibold))
                    .frame(minWidth: 24, minHeight: 24)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(lineWidth: 1.5))
            }
            .accessibilityLabel("Tabs, \(model.tabCount) open")

            // The page menu. Its touch area is 44 points wide and as tall as
            // the address pill: the glyph alone is a target a finger misses.
            Button(action: openMenu) {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 38)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Menu")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
