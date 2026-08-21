import AppKit
import ClearframeCore
import SwiftUI

/// A saved page as a row in a menu: its own site icon where one has been
/// captured during a visit, a plain globe where it has not.
///
/// Deliberately not `SiteIconView`. A menu row takes an image, not a view, and
/// the icon has to be known the moment the menu is built rather than arriving
/// asynchronously afterwards — so this reads what `FaviconStore` already holds
/// and settles for the globe if that is nothing. The icon policy is unchanged:
/// nothing is fetched here, and a site with no captured icon simply has none.
struct BookmarkMenuRow: View {
    let title: String
    let url: String
    /// Passed in from the menu bar, whose commands are built outside any view
    /// hierarchy and so never see the environment. Left unset inside the app's
    /// own windows, where the environment does carry it.
    var store: FaviconStore?
    @Environment(\.faviconStore) private var environmentStore

    var body: some View {
        if let icon = cachedIcon {
            Label {
                Text(title)
            } icon: {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: ClearframeTheme.siteIconSize, height: ClearframeTheme.siteIconSize)
            }
        } else {
            Label(title, systemImage: "globe")
        }
    }

    private var cachedIcon: NSImage? {
        guard let host = URL(string: url)?.host, !host.isEmpty else { return nil }
        return (store ?? environmentStore)?.icon(forHost: host)
    }
}
