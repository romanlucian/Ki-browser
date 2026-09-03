import CoreGraphics
import LimeghostCore
import LimeghostShared
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
            Label { Text(title) } icon: { Image(decorative: icon, scale: Self.menuIconScale(for: icon)) }
        } else {
            Label(title, systemImage: "globe")
        }
    }

    /// The site's icon, still owned by the store's own cache.
    private var cachedIcon: CGImage? {
        guard let host = URL(string: url)?.host, !host.isEmpty else { return nil }
        return (store ?? environmentStore)?.icon(forHost: host)
    }

    /// The scale that reports `icon`'s size to SwiftUI as
    /// `LimeghostTheme.siteIconSize` points on its longer edge.
    ///
    /// Sized this way rather than with a frame around it: a menu row is an
    /// `NSMenuItem`, which takes the image's own reported size and pays no
    /// attention to SwiftUI layout. A stored favicon is often 64 or 128
    /// pixels square, so without this the icons come out several times the
    /// height of the text. `Image(decorative:scale:)` reports `pixelSize /
    /// scale` points, so dividing the longer pixel edge by the target point
    /// size reproduces that: the previous `NSImage.size` override forced an
    /// exact square and so stretched the rare non-square favicon
    /// `normalizedPNG` produces; this fits it within the square instead,
    /// which is the same trade `SiteIconView` already makes with
    /// `.aspectRatio(contentMode: .fit)`.
    private static func menuIconScale(for icon: CGImage) -> CGFloat {
        CGFloat(max(icon.width, icon.height)) / LimeghostTheme.siteIconSize
    }
}
