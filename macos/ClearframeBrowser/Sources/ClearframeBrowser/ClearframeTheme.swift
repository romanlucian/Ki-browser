import SwiftUI

/// Design tokens for the "Halo" chrome redesign — near-black surfaces, a
/// single mint accent, and hairline separators instead of system materials.
/// UI-only: `ClearframeCore` stays Foundation-only, so nothing here is
/// reachable from that layer, and nothing here should depend on it either.
enum ClearframeTheme {
    // MARK: - Surfaces (back to front)

    /// Window base, visible behind the tab strip/toolbar stack.
    static let bg0 = Color(hex: 0x07070a)
    /// Toolbar row, bookmarks bar, and the active tab chip that joins them —
    /// one continuous darker plane under the tab strip.
    static let bg1 = Color(hex: 0x0b0b0e)
    /// The tab strip the chips sit in, plus roomier page surfaces (bookmark
    /// cards) that want one step of lift off `bg0`.
    static let bg2 = Color(hex: 0x101013)
    /// Chips, pills, and popover-adjacent surfaces.
    static let bg3 = Color(hex: 0x15151a)
    /// `bg3`, lightened one notch for hover states.
    static let bg3Hover = Color(hex: 0x1b1b21)
    /// Inactive tab chip: a touch lighter than `bg3` so an unselected tab
    /// reads as raised out of the strip rather than cut into it.
    static let tabChip = Color(hex: 0x1a1a1f)

    // MARK: - Text

    static let textPrimary = Color(hex: 0xf4f4f2)
    static let textSecondary = Color.white.opacity(0.66)
    static let textTertiary = Color.white.opacity(0.45)

    // MARK: - Accent

    static let accent = Color(red: 0.40, green: 0.86, blue: 0.49)
    /// Foreground color for content drawn on top of an `accent` fill.
    static let onAccent = bg0
    /// Subtle wash for a larger targeted area (e.g. the bookmarks bar while
    /// a drag hovers over it).
    static let accentDim = accent.opacity(0.16)
    /// A touch stronger, for a smaller target that needs more contrast to
    /// register at a glance (e.g. a single folder chip while drag-targeted).
    static let accentDimStrong = accent.opacity(0.28)

    /// Borderless items (the bookmarks bar) carry no fill at rest and take
    /// this wash while hovered, open, or otherwise active.
    static let itemHover = Color.white.opacity(0.06)

    // MARK: - Hairlines

    static let hairline1 = Color.white.opacity(0.06)
    static let hairline2 = Color.white.opacity(0.08)
    static let hairline3 = Color.white.opacity(0.10)

    // MARK: - Radii

    static let radius6: CGFloat = 6
    static let radius8: CGFloat = 8
    /// Address pill and the active tab chip's top corners.
    static let radius9: CGFloat = 9
    static let radius10: CGFloat = 10
    static let radius12: CGFloat = 12
    static let radius14: CGFloat = 14
    static let radius18: CGFloat = 18

    /// The size of a site's icon and a bookmark folder's mark, wherever either
    /// appears: tab chips, the bookmarks bar, the bookmarks home. One number so
    /// the two never drift apart, and 16 because that is both what the folder
    /// icons were drawn at — below it their 1.5 stroke is scaled down — and
    /// what other browsers use for a favicon.
    static let siteIconSize: CGFloat = 16

    // MARK: - Type

    /// Monospace metadata capitals — tab counter, ⌘L hint, folder chip
    /// counts. Callers still apply `.tracking(metaTracking)` themselves
    /// since a `Font` value cannot carry tracking.
    static let metaFont = Font.system(size: 10, weight: .semibold, design: .monospaced)
    static let metaTracking: CGFloat = 0.8
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255
        )
    }
}

/// Ghost icon button: invisible until hovered, pressed, or marked active.
/// Used throughout the toolbar and tab strip so controls read as icons
/// floating on the surface rather than a button bar.
///
/// `tint` lets a caller give a button its own semantic color (the listening
/// mic, a filled star) without fighting the style's own foreground
/// application; it only applies while `isActive` is false, since active
/// state always uses `onAccent` over an `accent` fill.
struct GhostButtonStyle: ButtonStyle {
    var size: CGFloat = 28
    var isActive: Bool = false
    var tint: Color = ClearframeTheme.textPrimary

    func makeBody(configuration: Configuration) -> some View {
        GhostButtonBody(configuration: configuration, size: size, isActive: isActive, tint: tint)
    }
}

/// Split out from `GhostButtonStyle` so hover tracking has an unambiguous
/// `View` to own its `@State` — button styles themselves are handed a
/// configuration, not a persistent view identity.
private struct GhostButtonBody: View {
    let configuration: GhostButtonStyle.Configuration
    let size: CGFloat
    let isActive: Bool
    let tint: Color
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .foregroundStyle(isActive ? ClearframeTheme.onAccent : tint)
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .background(
                isActive
                    ? ClearframeTheme.accent
                    : Color.white.opacity(configuration.isPressed ? 0.14 : (isHovered ? 0.08 : 0)),
                in: RoundedRectangle(cornerRadius: ClearframeTheme.radius8)
            )
            .onHover { isHovered = $0 }
    }
}
