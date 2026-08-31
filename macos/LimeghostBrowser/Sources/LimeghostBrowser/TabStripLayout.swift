import SwiftUI

/// How the tab strip divides its width, Chrome/Safari style: tabs share the
/// room that is actually there instead of each claiming a fixed slot and
/// pushing the rest off the end.
///
/// The whole distribution is this one pure function, so the behavior the
/// window resize depends on is unit-testable without a window:
///
/// - every tab is at most `maximumTabWidth`, so a nearly empty strip does not
///   stretch two tabs across the screen;
/// - the selected tab takes up to `selectedTabPriority` times an unselected
///   tab's share, so the tab being read stays readable while its neighbors
///   compress;
/// - below `comfortableMinimumTabWidth` — the point where an icon and a close
///   button stop fitting — the strip stops compressing and scrolls instead, so
///   tabs never shrink into unusable slivers.
enum TabStripMetrics {
    /// One band for both chip states so every chip's bottom edge lands exactly
    /// on the toolbar below.
    static let chipHeight: CGFloat = 34
    static let spacing: CGFloat = 4
    static let maximumTabWidth: CGFloat = 200
    /// Icon plus close button plus padding: the narrowest a tab can be and
    /// still be operable.
    static let comfortableMinimumTabWidth: CGFloat = 54
    /// A pinned tab's fixed width: room for the site icon alone, since a
    /// pinned chip never shows a title or close button.
    static let pinnedTabWidth: CGFloat = 44
    /// Chrome gives the active tab a larger share of the strip. 1.4 is enough
    /// to keep a title on the active tab when its neighbors are down to an
    /// icon, without making it look like a different control.
    static let selectedTabPriority: CGFloat = 1.4
    /// How far a group's tint rises above the chips it encloses.
    static let groupEnclosureLift: CGFloat = 4

    struct Resolution: Equatable {
        var selectedTabWidth: CGFloat
        var unselectedTabWidth: CGFloat
        /// What the strip's content actually occupies. Larger than the space
        /// available only in the scrolling fallback.
        var contentWidth: CGFloat
        var scrolls: Bool
    }

    /// - Parameter reservedWidth: width the tabs cannot use — group chips and
    ///   the gaps around them — measured before the tabs are laid out.
    static func resolve(
        availableWidth: CGFloat,
        tabCount: Int,
        hasSelectedTab: Bool,
        reservedWidth: CGFloat = 0,
        spacing: CGFloat = TabStripMetrics.spacing
    ) -> Resolution {
        guard tabCount > 0 else {
            return Resolution(
                selectedTabWidth: 0,
                unselectedTabWidth: 0,
                contentWidth: max(0, reservedWidth),
                scrolls: reservedWidth > availableWidth
            )
        }

        let gaps = spacing * CGFloat(tabCount - 1)
        let flexibleWidth = availableWidth - reservedWidth - gaps
        let selectedWeight = hasSelectedTab ? selectedTabPriority : 1
        let shares = CGFloat(tabCount - (hasSelectedTab ? 1 : 0)) + selectedWeight

        var unselected = flexibleWidth / shares
        var selected = unselected * selectedWeight
        if selected > maximumTabWidth {
            // The active tab has all the room it can use; the rest of the
            // strip splits what is left rather than leaving a hole.
            selected = maximumTabWidth
            unselected = tabCount > 1 ? (flexibleWidth - selected) / CGFloat(tabCount - 1) : selected
        }
        if unselected > maximumTabWidth {
            unselected = maximumTabWidth
            selected = maximumTabWidth
        }

        let scrolls = unselected < comfortableMinimumTabWidth
        if scrolls {
            unselected = comfortableMinimumTabWidth
            selected = hasSelectedTab
                ? min(maximumTabWidth, comfortableMinimumTabWidth * selectedTabPriority)
                : comfortableMinimumTabWidth
        }

        // Whole points keep chip text crisp; the few points of slack land at
        // the trailing end of the strip, where the new-tab button already is.
        let selectedWidth = selected.rounded(.down)
        let unselectedWidth = unselected.rounded(.down)
        let tabsWidth = hasSelectedTab
            ? selectedWidth + unselectedWidth * CGFloat(tabCount - 1)
            : unselectedWidth * CGFloat(tabCount)

        return Resolution(
            selectedTabWidth: selectedWidth,
            unselectedTabWidth: unselectedWidth,
            contentWidth: tabsWidth + gaps + reservedWidth,
            scrolls: scrolls
        )
    }

    /// The same distribution as one width per tab, in strip order.
    static func widths(
        availableWidth: CGFloat,
        tabCount: Int,
        selectedIndex: Int?,
        reservedWidth: CGFloat = 0,
        spacing: CGFloat = TabStripMetrics.spacing
    ) -> [CGFloat] {
        guard tabCount > 0 else { return [] }
        let selection = selectedIndex.flatMap { (0..<tabCount).contains($0) ? $0 : nil }
        let resolution = resolve(
            availableWidth: availableWidth,
            tabCount: tabCount,
            hasSelectedTab: selection != nil,
            reservedWidth: reservedWidth,
            spacing: spacing
        )
        return (0..<tabCount).map {
            $0 == selection ? resolution.selectedTabWidth : resolution.unselectedTabWidth
        }
    }
}

/// What a tab chip can show at the width it was actually given. Progressive
/// disclosure, so a compressed strip loses detail in a predictable order
/// instead of clipping everything at once.
enum TabChipDensity: Equatable {
    /// Icon, full title, close button.
    case full
    /// Icon, truncated title, close button.
    case compact
    /// Icon and title; the close button appears on the selected or hovered tab.
    case tight
    /// Icon only; the selected tab swaps it for a close button on hover.
    case iconOnly

    static func forWidth(_ width: CGFloat) -> TabChipDensity {
        switch width {
        case 140...: return .full
        case 100..<140: return .compact
        case 70..<100: return .tight
        default: return .iconOnly
        }
    }

    var showsTitle: Bool { self != .iconOnly }
    /// Whether the close button is always in the chip, rather than only while
    /// the tab is selected or hovered.
    var pinsCloseButton: Bool { self == .full || self == .compact }

    var horizontalPadding: CGFloat {
        switch self {
        case .full: return 11
        case .compact: return 9
        case .tight: return 8
        case .iconOnly: return 6
        }
    }

    var contentSpacing: CGFloat {
        switch self {
        case .full: return 9
        case .compact: return 7
        case .tight: return 6
        case .iconOnly: return 0
        }
    }
}

/// What one item in the strip is, from the layout's point of view.
enum TabStripItemRole: Equatable {
    /// A tab chip, which takes a share of the strip's width.
    case tab(isSelected: Bool)
    /// A pinned tab chip: always `TabStripMetrics.pinnedTabWidth`, subtracted
    /// from the available width before the unpinned tabs share what is left
    /// — the same treatment `.fixed` group chips get, just at one shared
    /// width instead of each chip's own natural size.
    case pinnedTab
    /// A group chip, which keeps its natural width and is subtracted from what
    /// the tabs have to share.
    case fixed
}

private struct TabStripItemRoleKey: LayoutValueKey {
    static let defaultValue: TabStripItemRole = .tab(isSelected: false)
}

extension View {
    func tabStripRole(_ role: TabStripItemRole) -> some View {
        layoutValue(key: TabStripItemRoleKey.self, value: role)
    }
}

/// Places the strip's items across the width it was given, using
/// `TabStripMetrics` for the tab share and each fixed item's own natural size
/// for the rest.
///
/// `availableWidth` is passed in from the surrounding `GeometryReader` rather
/// than read from the proposal: the layout sits inside a horizontal
/// `ScrollView`, whose proposal along the scroll axis is not the width the
/// user can actually see.
struct TabStripLayout: Layout {
    let availableWidth: CGFloat
    var spacing: CGFloat = TabStripMetrics.spacing
    var itemHeight: CGFloat = TabStripMetrics.chipHeight
    /// Clearance above the chips, reserved so a group's tint can rise behind
    /// them without being clipped by the surrounding scroll view.
    var topLift: CGFloat = TabStripMetrics.groupEnclosureLift

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        CGSize(width: max(resolve(subviews).contentWidth, 0), height: itemHeight + topLift)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let plan = resolve(subviews)
        var x = bounds.minX
        // Every item sits on the strip's bottom edge — the toolbar's top edge —
        // which is what lets the active chip merge into the toolbar below.
        let y = bounds.maxY - itemHeight
        for (index, subview) in subviews.enumerated() {
            let width = plan.widths[index]
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: itemHeight)
            )
            x += width + spacing
        }
    }

    private func resolve(_ subviews: Subviews) -> (widths: [CGFloat], contentWidth: CGFloat) {
        guard !subviews.isEmpty else { return ([], 0) }
        let roles = subviews.map { $0[TabStripItemRoleKey.self] }
        // Group chips ask for their own natural width; pinned tabs all share
        // the one fixed width; only a plain `.tab` has none of its own and
        // waits for a share of what the other two leave behind.
        let fixedWidths = zip(subviews, roles).map { subview, role -> CGFloat in
            switch role {
            case .fixed: return subview.sizeThatFits(.unspecified).width.rounded(.up)
            case .pinnedTab: return TabStripMetrics.pinnedTabWidth
            case .tab: return 0
            }
        }
        let tabCount = roles.filter {
            if case .tab = $0 { return true }
            return false
        }.count
        let reserved = fixedWidths.reduce(0, +) + spacing * CGFloat(fixedWidths.filter { $0 > 0 }.count)
        let resolution = TabStripMetrics.resolve(
            availableWidth: availableWidth,
            tabCount: tabCount,
            hasSelectedTab: roles.contains(.tab(isSelected: true)),
            reservedWidth: reserved,
            spacing: spacing
        )

        var widths: [CGFloat] = []
        widths.reserveCapacity(roles.count)
        for (index, role) in roles.enumerated() {
            switch role {
            case .fixed, .pinnedTab:
                widths.append(fixedWidths[index])
            case .tab(let isSelected):
                widths.append(isSelected ? resolution.selectedTabWidth : resolution.unselectedTabWidth)
            }
        }
        // The reserved figure already counts one gap per fixed/pinned item,
        // so the content width only needs the gaps between the remaining
        // items — `tabCount` here is unpinned tabs only, and a strip that is
        // entirely pinned tabs and group chips resolves with `tabCount == 0`,
        // which `TabStripMetrics.resolve` already handles without dividing
        // by anything.
        let total = widths.reduce(0, +) + spacing * CGFloat(max(0, widths.count - 1))
        return (widths, total)
    }
}
