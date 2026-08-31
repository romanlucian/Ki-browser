import AppKit
import LimeghostCore
import SwiftUI

/// A web page as a row in a menu — a bookmark, or somewhere recently
/// visited: its own site icon where one has been captured during a visit, a
/// plain globe where it has not.
///
/// Deliberately not `SiteIconView`. A menu row takes an image, not a view, and
/// the icon has to be known the moment the menu is built rather than arriving
/// asynchronously afterwards — so this reads what `FaviconStore` already holds
/// and settles for the globe if that is nothing. The icon policy is unchanged:
/// nothing is fetched here, and a site with no captured icon simply has none.
struct PageMenuRow: View {
    let title: String
    let url: String
    /// Passed in from the menu bar, whose commands are built outside any view
    /// hierarchy and so never see the environment. Left unset inside the app's
    /// own windows, where the environment does carry it.
    var store: FaviconStore?
    @Environment(\.faviconStore) private var environmentStore

    var body: some View {
        if let icon = cachedIcon {
            Label { Text(title) } icon: { Image(nsImage: icon) }
        } else {
            Label(title, systemImage: "globe")
        }
    }

    /// The site's icon at the size a menu row wants.
    ///
    /// Sized on the image rather than with a frame around it: a menu row is an
    /// `NSMenuItem`, which takes the image's own size and pays no attention to
    /// SwiftUI layout. A stored favicon is often 64 or 128 points square, so
    /// without this the icons come out several times the height of the text.
    private var cachedIcon: NSImage? {
        guard let host = URL(string: url)?.host, !host.isEmpty,
              let stored = (store ?? environmentStore)?.icon(forHost: host),
              let sized = stored.copy() as? NSImage
        else { return nil }
        // A copy, because the original belongs to the cache and is drawn
        // elsewhere at its own size. Setting `size` re-describes the image
        // rather than redrawing it, so the full-resolution representation is
        // still what gets rendered.
        sized.size = NSSize(
            width: LimeghostTheme.siteIconSize,
            height: LimeghostTheme.siteIconSize
        )
        return sized
    }
}
