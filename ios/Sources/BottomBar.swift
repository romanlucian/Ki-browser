import SwiftUI

/// What the bar shows, separate from how it draws, so a test can assert it
/// without standing up SwiftUI.
struct BottomBarModel {
    let urlString: String
    let tabCount: Int
    let canGoBack: Bool

    /// The host, or an invitation.
    var addressLabel: String {
        guard let host = URL(string: urlString)?.host else {
            return urlString.isEmpty ? "Search or enter a website" : urlString
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// Back, the address, the tabs and a menu — within a thumb's reach, along the
/// bottom so the page's own top is left alone.
struct BottomBar: View {
    let model: BottomBarModel
    let goBack: () -> Void
    let openAddress: () -> Void
    let openTabs: () -> Void

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

            // The assistant toggle belongs here, immediately left of the tab
            // button, and arrives with the assistant in Plan 3. A button that
            // did nothing would teach the wrong thing about where it lives.

            // The page menu belongs after the tab button — Reader, Copy for
            // AI, bookmark this page, find in page, site information and
            // settings, almost entirely Plan 3's too. Reserved for the same
            // reason as the toggle above: a menu that opened onto nothing
            // would teach the wrong thing about where it lives.

            Button(action: openTabs) {
                Text("\(model.tabCount)")
                    .font(.footnote.weight(.semibold))
                    .frame(minWidth: 24, minHeight: 24)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(lineWidth: 1.5))
            }
            .accessibilityLabel("Tabs, \(model.tabCount) open")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
