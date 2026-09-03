import LimeghostShared
import SwiftUI

// MARK: - Site icon view

private struct FaviconStoreKey: EnvironmentKey {
    static let defaultValue: FaviconStore? = nil
}

extension EnvironmentValues {
    /// Injected once, by `BrowserView`. Optional on purpose: a view rendered
    /// without a store (a preview, a test host) still draws its fallback
    /// square instead of crashing.
    var faviconStore: FaviconStore? {
        get { self[FaviconStoreKey.self] }
        set { self[FaviconStoreKey.self] = newValue }
    }
}

/// A site's mark at chip scale: the real icon when Limeghost captured one
/// during a visit, otherwise the deterministic `IdentityColor` square. A
/// square rather than a dot because at 13pt it reads as an icon slot, so a
/// site with an icon and one without sit on the same grid.
///
/// Rendering never triggers a fetch — only `FaviconStore.captureIfNeeded`
/// does, and only for the page being visited.
struct SiteIconView: View {
    let host: String
    var size: CGFloat = LimeghostTheme.siteIconSize
    /// Decorative by default: the icon sits beside a title that already says
    /// which site this is, so announcing it again is noise. A caller that
    /// shows the icon *instead* of a title — a pinned tab — passes the name
    /// here, so the icon is not hidden outright. Note that the name does not
    /// currently survive as the element's label from a pinned chip; see
    /// `TabChip.pinnedChip`.
    var accessibilityName: String?
    @Environment(\.faviconStore) private var store

    init(host: String, size: CGFloat = LimeghostTheme.siteIconSize, accessibilityName: String? = nil) {
        self.host = host
        self.size = size
        self.accessibilityName = accessibilityName
    }

    init(urlString: String, size: CGFloat = LimeghostTheme.siteIconSize, accessibilityName: String? = nil) {
        self.init(
            host: URL(string: urlString)?.host ?? "",
            size: size,
            accessibilityName: accessibilityName
        )
    }

    var body: some View {
        Group {
            if let store {
                StoredSiteIcon(store: store, host: host, size: size)
            } else {
                SiteIconFallback(host: host, size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(accessibilityName == nil)
        .accessibilityLabel(accessibilityName ?? "")
    }
}

/// Split out so the icon redraws when a capture completes: `@ObservedObject`
/// needs a concrete view identity to subscribe from.
private struct StoredSiteIcon: View {
    @ObservedObject var store: FaviconStore
    let host: String
    let size: CGFloat

    var body: some View {
        if let icon = store.icon(forHost: host) {
            // `.resizable()` plus the explicit `.frame()` below own the final
            // on-screen size entirely, so the scale here never reaches the
            // display — only the aspect ratio (pixel width : height, which
            // scale cannot change) survives into `.aspectRatio(contentMode:)`.
            Image(decorative: icon, scale: 2)
                .resizable()
                .interpolation(.high)
                // `fit`, not `fill`: a site's icon is not always square —
                // Google Flow's is 653x524 — and filling a square slot with
                // one crops its sides away and upscales what is left into a
                // blur. Fitting shows all of it. For the square icons that
                // are the norm the two are identical.
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: SiteIconFallback.cornerRadius, style: .continuous))
        } else {
            SiteIconFallback(host: host, size: size)
        }
    }
}

private struct SiteIconFallback: View {
    static let cornerRadius: CGFloat = 4

    let host: String
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            .fill(IdentityColor.color(forHost: host))
            .frame(width: size, height: size)
    }
}
