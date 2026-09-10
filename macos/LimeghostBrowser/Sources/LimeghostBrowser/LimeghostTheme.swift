import SwiftUI

/// Design tokens for the "Halo" chrome redesign — near-black surfaces, a
/// single mint accent, and hairline separators instead of system materials.
/// UI-only: `LimeghostCore` stays Foundation-only, so nothing here is
/// reachable from that layer, and nothing here should depend on it either.
enum LimeghostTheme {
    // MARK: - Surfaces (back to front)

    /// Window base, behind everything.
    static let bg0 = Color(hex: 0x0d0d0f)
    /// The trough the tab chips sit in.
    ///
    /// Its own token since September 2, 2026. It used to be `bg2`, which is
    /// also every popover and card — and in Chrome's arrangement, which this
    /// now follows, the tab well is *darker* than the toolbar while a card is
    /// *lighter*. One token could not be both.
    static let tabWell = Color(hex: 0x131316)
    /// The plane: the toolbar row, the bookmarks bar, and the active tab chip
    /// that joins them — one continuous surface the active tab rises into.
    ///
    /// Lighter than the well as of September 2, 2026. It was darker, which is
    /// the inverse of how Chrome builds the same three rows, and it is why the
    /// whole stack read as flat and black however the rows were sized.
    static let bg1 = Color(hex: 0x2a2a2e)
    /// One step above the plane: popovers, cards, the reader's header, the
    /// address suggestion list. Things that float.
    static let bg2 = Color(hex: 0x303035)
    /// Chips and pills — the address pill above all. The lightest chrome
    /// surface, because a raised control should read as raised.
    static let bg3 = Color(hex: 0x38383d)
    /// `bg3`, lightened one notch for hover states.
    static let bg3Hover = Color(hex: 0x42424a)
    /// Inactive tab chip: between the well it sits in and the plane its active
    /// neighbour rises into, so an unselected tab reads as on its way up.
    static let tabChip = Color(hex: 0x222226)

    // MARK: - Text

    static let textPrimary = Color(hex: 0xf4f4f2)
    /// Running prose — a card's own sentence, a paragraph somebody reads
    /// rather than glances at.
    ///
    /// Its own tone since September 2, 2026. The AI home was setting body copy
    /// at `0.76` and supporting text at `0.66`, `0.58`, `0.56` and `0.50`, five
    /// hand-mixed greys where the app has three; without a named tone for
    /// "text to actually read", the nearest token was always a little too dim
    /// and a literal always won.
    static let textBody = Color.white.opacity(0.78)
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

    /// The outline that binds a set of toolbar buttons into one group.
    ///
    /// Accent rather than a neutral hairline because the thing it groups is the
    /// AI workflow, and mint is what marks that everywhere else. Faint on
    /// purpose: it has to read as a boundary at a glance without competing with
    /// the lit state of a button inside it, which is the same accent at full
    /// strength.
    static let groupOutline = accent.opacity(0.26)

    // MARK: - Hairlines

    static let hairline1 = Color.white.opacity(0.06)
    static let hairline2 = Color.white.opacity(0.08)
    static let hairline3 = Color.white.opacity(0.10)

    // MARK: - Chrome metrics

    /// The tab strip, the toolbar and the bookmarks bar are one height.
    ///
    /// They ran 41 / 44 / 28 until September 2, 2026, and the short bookmarks
    /// bar was what made the stack read as uneven beside Chrome's, whose three
    /// rows are near enough equal. One number so they cannot drift again.
    static let chromeRowHeight: CGFloat = 40

    /// Everything that sits inside a chrome row: the ghost buttons and the
    /// address pill both.
    ///
    /// One number because the row read as lopsided when they differed. At 40
    /// tall with 28 inside, a control breathes 6 points top and bottom —
    /// Chrome's omnibox breathes about 7 in a 42-point row, which is the
    /// rhythm this is matching. Until September 2, 2026 the pill was 32 and
    /// the buttons beside it 28, so the pill had 4 points of air and its
    /// neighbours 6, and the whole row looked crowded without it being
    /// obvious which element was wrong.
    static let chromeControlHeight: CGFloat = 28

    /// The address pill. Drawn as a `Capsule`, so its radius is always half
    /// this — a full pill the way Chrome's omnibox is, rather than a rounded
    /// rectangle that has to be kept in sync with the height by hand.
    static let addressPillHeight: CGFloat = chromeControlHeight

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
    /// the two never drift apart.
    ///
    /// 18 to match the toolbar's own row of icons, which are SF Symbols at the
    /// 13pt body size and measure 15–19pt across (`books.vertical` 19x17,
    /// `sparkles.rectangle.stack` 17x18). At 16 the folder marks read as a
    /// second, smaller class of icon sitting under a larger one; at 18 the two
    /// rows line up. It is also above the 16 the artwork was drawn at, so the
    /// Limeghost set's 1.5 stroke is scaled up rather than down.
    static let siteIconSize: CGFloat = 18

    // MARK: - Type

    /// Monospace metadata capitals — tab counter, ⌘L hint, folder chip
    /// counts. Callers still apply `.tracking(metaTracking)` themselves
    /// since a `Font` value cannot carry tracking.
    static let metaFont = Font.system(size: 10, weight: .semibold, design: .monospaced)
    static let metaTracking: CGFloat = 0.8

    /// Tracked capitals *inside* a card — a recommendation badge, a "BEST FOR"
    /// label. One step below `metaFont`, because a card is not a page section
    /// and a label has to leave room for the thing it labels.
    ///
    /// These two are the whole set. The AI home had four tracked-caps
    /// treatments in one file (1.8, 1.1, 0.65, plus a bare 10pt bold) and used
    /// the app's own `metaFont` for none of them.
    static let microFont = Font.system(size: 9, weight: .bold, design: .monospaced)
    static let microTracking: CGFloat = 0.6
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
    var size: CGFloat = LimeghostTheme.chromeControlHeight
    var isActive: Bool = false
    var tint: Color = LimeghostTheme.textPrimary

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
            .foregroundStyle(isActive ? LimeghostTheme.onAccent : tint)
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .background(
                isActive
                    ? LimeghostTheme.accent
                    : Color.white.opacity(configuration.isPressed ? 0.14 : (isHovered ? 0.08 : 0)),
                in: RoundedRectangle(cornerRadius: LimeghostTheme.radius8)
            )
            .onHover { isHovered = $0 }
    }
}
