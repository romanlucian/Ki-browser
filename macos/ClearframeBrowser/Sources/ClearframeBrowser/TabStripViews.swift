import ClearframeCore
import SwiftUI

/// The tab strip: grouped and ungrouped tabs sharing one row of width, a
/// new-tab button, and the tab counter.
///
/// Width is distributed by `TabStripLayout`/`TabStripMetrics` rather than
/// fixed per chip, so narrowing the window compresses the tabs the way Chrome
/// and Safari do instead of pushing them out of reach.
struct TabStrip: View {
    @ObservedObject var workspace: BrowserWorkspace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tabCountLabel: String {
        workspace.tabs.count == 1 ? "1 TAB" : "\(workspace.tabs.count) TABS"
    }

    private var tabCountAccessibilityLabel: String {
        workspace.tabs.count == 1 ? "1 tab open" : "\(workspace.tabs.count) tabs open"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Sits behind everything below; SwiftUI routes clicks on the
            // chips/button/pill in front of it before this ever sees them.
            // Explicit fill: a representable with no intrinsic size should
            // not be left to guess the strip's bounds.
            WindowDragArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(alignment: .bottom, spacing: 8) {
                // The reader claims whatever the button and counter leave, and
                // hands that width to the layout as the real, visible width —
                // a horizontal scroll view's own proposal is not.
                GeometryReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        TabStripLayout(availableWidth: proxy.size.width) {
                            ForEach(items) { item in
                                itemView(item)
                            }
                        }
                        .animation(motion, value: animationSignature)
                    }
                    .frame(width: proxy.size.width, height: Self.stripItemBand, alignment: .leading)
                }
                // Explicitly greedy: the strip takes every point the new-tab
                // button and the counter leave, and that width is what the
                // tabs divide between them.
                .frame(maxWidth: .infinity, minHeight: Self.stripItemBand, maxHeight: Self.stripItemBand)

                Button {
                    workspace.addTab()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(GhostButtonStyle(size: 26))
                .frame(height: TabStripMetrics.chipHeight)
                .help("New tab (⌘T)")

                Text(tabCountLabel)
                    .font(ClearframeTheme.metaFont)
                    .tracking(ClearframeTheme.metaTracking)
                    .foregroundStyle(ClearframeTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(ClearframeTheme.bg3, in: Capsule())
                    .overlay(Capsule().stroke(ClearframeTheme.hairline2))
                    .frame(height: TabStripMetrics.chipHeight)
                    .accessibilityLabel(tabCountAccessibilityLabel)
            }
            // 78pt clears the inline traffic lights that hiddenTitleBar
            // leaves floating at the top-left of the window content.
            .padding(.leading, 78)
            .padding(.trailing, Self.horizontalInset)
            // The chips are bottom-aligned: their lower edge is the toolbar's
            // top edge, which is what lets the active chip merge into it.
            .padding(.top, Self.topInset - TabStripMetrics.groupEnclosureLift)
        }
        .frame(height: Self.topInset + TabStripMetrics.chipHeight)
        .background(ClearframeTheme.bg2)
    }

    private static let topInset: CGFloat = 7
    private static let horizontalInset: CGFloat = 12
    /// Chip height plus the clearance a group's tint needs above it.
    private static let stripItemBand = TabStripMetrics.chipHeight + TabStripMetrics.groupEnclosureLift

    /// Width changes are animated where they read as motion the user caused —
    /// opening, closing, grouping, collapsing — and not while a window resize
    /// is being dragged, where tabs should track the edge directly.
    private var motion: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.16)
    }

    private var animationSignature: String {
        let collapsedCount = workspace.tabGroups.filter(\.isCollapsed).count
        return "\(workspace.tabs.count)-\(workspace.visibleTabs.count)-\(collapsedCount)-\(workspace.selectedTabID?.uuidString ?? "")"
    }

    // MARK: - Items

    /// One drawn element of the strip. A group contributes its label chip and,
    /// unless it is collapsed, the tabs inside it.
    private enum StripItem: Identifiable {
        case tab(BrowserTab, group: TabGroupRecord?, isLastInGroup: Bool)
        case groupChip(TabGroupRecord, tabCount: Int, key: String)

        var id: String {
            switch self {
            case .tab(let tab, _, _): return "tab-\(tab.id.uuidString)"
            case .groupChip(_, _, let key): return key
            }
        }
    }

    private var items: [StripItem] {
        var result: [StripItem] = []
        let tabs = workspace.tabs
        var index = 0
        while index < tabs.count {
            let tab = tabs[index]
            guard let groupID = tab.groupID, let group = workspace.group(groupID) else {
                result.append(.tab(tab, group: nil, isLastInGroup: false))
                index += 1
                continue
            }
            var end = index
            while end + 1 < tabs.count, tabs[end + 1].groupID == groupID { end += 1 }
            let members = Array(tabs[index...end])
            // The run's start is part of the key: a group whose tabs somehow
            // ended up split still draws, instead of colliding on one id.
            result.append(.groupChip(group, tabCount: members.count, key: "group-\(groupID.uuidString)-\(index)"))
            if !group.isCollapsed {
                for (offset, member) in members.enumerated() {
                    result.append(.tab(member, group: group, isLastInGroup: offset == members.count - 1))
                }
            }
            index = end + 1
        }
        return result
    }

    @ViewBuilder
    private func itemView(_ item: StripItem) -> some View {
        switch item {
        case .groupChip(let group, let tabCount, _):
            TabGroupChip(
                group: group,
                tabCount: tabCount,
                editorPresented: editorBinding(for: group.id),
                toggleCollapse: { workspace.toggleCollapse(groupID: group.id) },
                newTabInGroup: { workspace.addTab(toGroup: group.id) },
                rename: { workspace.renameGroup(group.id, title: $0) },
                recolor: { workspace.recolorGroup(group.id, colorID: $0) },
                ungroup: { workspace.ungroup(groupID: group.id) },
                closeGroup: { workspace.closeGroup(groupID: group.id) }
            )
            .tabStripRole(.fixed)
            .modifier(
                GroupEnclosureBackground(
                    colorID: group.colorID,
                    roundsLeading: true,
                    roundsTrailing: group.isCollapsed,
                    bridgesTrailing: !group.isCollapsed
                )
            )
        case .tab(let tab, let group, let isLastInGroup):
            TabChip(
                tab: tab,
                isSelected: tab.id == workspace.selectedTabID,
                groups: workspace.tabGroups,
                select: { workspace.selectTab(tab.id) },
                close: { workspace.closeTab(tab.id) },
                menu: TabChipMenuActions(
                    newTabToRight: { workspace.addTab(after: tab.id) },
                    addToNewGroup: { workspace.createGroup(withTabs: [tab.id]) },
                    addToGroup: { workspace.addTab(tab.id, toGroup: $0) },
                    removeFromGroup: { workspace.removeTabFromGroup(tab.id) },
                    closeOthers: { workspace.closeOtherTabs(keeping: tab.id) }
                )
            )
            .tabStripRole(.tab(isSelected: tab.id == workspace.selectedTabID))
            .modifier(
                GroupEnclosureBackground(
                    colorID: group?.colorID,
                    roundsLeading: false,
                    roundsTrailing: isLastInGroup,
                    bridgesLeading: true,
                    bridgesTrailing: !isLastInGroup
                )
            )
        }
    }

    /// One editor at a time, owned by the workspace so creating a group from
    /// the Tabs menu can open the same popover the chip's Rename does.
    private func editorBinding(for groupID: UUID) -> Binding<Bool> {
        Binding(
            get: { workspace.pendingGroupEditorID == groupID },
            set: { workspace.pendingGroupEditorID = $0 ? groupID : nil }
        )
    }
}

// MARK: - Tab chip

struct TabChipMenuActions {
    let newTabToRight: () -> Void
    let addToNewGroup: () -> Void
    let addToGroup: (UUID) -> Void
    let removeFromGroup: () -> Void
    let closeOthers: () -> Void
}

struct TabChip: View {
    @ObservedObject var tab: BrowserTab
    @ObservedObject private var session: BrowserSession
    let isSelected: Bool
    let groups: [TabGroupRecord]
    let select: () -> Void
    let close: () -> Void
    let menu: TabChipMenuActions
    @State private var isHovered = false

    init(
        tab: BrowserTab,
        isSelected: Bool,
        groups: [TabGroupRecord],
        select: @escaping () -> Void,
        close: @escaping () -> Void,
        menu: TabChipMenuActions
    ) {
        self.tab = tab
        _session = ObservedObject(wrappedValue: tab.session)
        self.isSelected = isSelected
        self.groups = groups
        self.select = select
        self.close = close
        self.menu = menu
    }

    private var host: String {
        URL(string: session.currentURLString)?.host ?? ""
    }

    private var cornerRadius: CGFloat {
        isSelected ? ClearframeTheme.radius9 : ClearframeTheme.radius8
    }

    private var helpText: String {
        host.isEmpty ? tab.displayTitle : "\(tab.displayTitle) — \(host)"
    }

    var body: some View {
        // The chip is told its width by the strip's layout; reading it back
        // here is what drives progressive disclosure inside the chip.
        GeometryReader { proxy in
            chip(density: TabChipDensity.forWidth(proxy.size.width))
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
        .frame(height: TabStripMetrics.chipHeight)
        .contextMenu { menuContents }
    }

    private func chip(density: TabChipDensity) -> some View {
        // The close button is always a sibling of the select button, never
        // inside its label, so a click on it closes the tab instead of
        // selecting it.
        HStack(spacing: density.contentSpacing) {
            if swapsIconForClose(density: density) {
                closeButton
                    .frame(maxWidth: .infinity)
            } else {
                Button(action: select) {
                    HStack(spacing: density.contentSpacing) {
                        leadingMark
                        if density.showsTitle {
                            Text(tab.displayTitle)
                                .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                                .foregroundStyle(isSelected ? ClearframeTheme.textPrimary : ClearframeTheme.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: density.showsTitle ? .leading : .center)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.displayTitle)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])

                if showsCloseButton(density: density) {
                    closeButton
                }
            }
        }
        .padding(.horizontal, density.horizontalPadding)
        .frame(height: TabStripMetrics.chipHeight)
        .background(
            chipFill,
            in: UnevenRoundedRectangle(topLeadingRadius: cornerRadius, topTrailingRadius: cornerRadius)
        )
        // Top and sides only: the bottom edge is deliberately open so the
        // active chip's fill runs straight into the toolbar's.
        .overlay {
            if isSelected {
                TabChipTopBorder(cornerRadius: cornerRadius)
                    .stroke(ClearframeTheme.hairline2, lineWidth: 1)
            }
        }
        .onHover { isHovered = $0 }
        .help(helpText)
    }

    /// Full and compact chips always carry the close button. A tight chip
    /// shows it for the tab in play; an icon-only chip has no room for both,
    /// so the selected tab swaps its icon for it on hover.
    private func showsCloseButton(density: TabChipDensity) -> Bool {
        switch density {
        case .full, .compact: return true
        case .tight: return isSelected || isHovered
        case .iconOnly: return false
        }
    }

    private func swapsIconForClose(density: TabChipDensity) -> Bool {
        density == .iconOnly && isSelected && isHovered
    }

    @ViewBuilder
    private var leadingMark: some View {
        if session.isLoading {
            ProgressView().controlSize(.mini).frame(width: 13, height: 13)
        } else if tab.isPrivate {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.purple)
                .frame(width: 13, height: 13)
        } else {
            SiteIconView(host: host)
        }
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(ClearframeTheme.textTertiary)
        .help("Close tab")
        .accessibilityLabel("Close tab")
    }

    private var chipFill: Color {
        if isSelected { return ClearframeTheme.bg1 }
        return isHovered ? ClearframeTheme.bg3Hover : ClearframeTheme.tabChip
    }

    @ViewBuilder
    private var menuContents: some View {
        Button("New tab to the right", action: menu.newTabToRight)
        Divider()
        Button("Add tab to new group", action: menu.addToNewGroup)
        let otherGroups = groups.filter { $0.id != tab.groupID }
        if !otherGroups.isEmpty {
            Menu("Add tab to group") {
                ForEach(otherGroups) { group in
                    Button(group.displayName) { menu.addToGroup(group.id) }
                }
            }
        }
        if tab.groupID != nil {
            Button("Remove tab from group", action: menu.removeFromGroup)
        }
        Divider()
        Button("Close tab", action: close)
        Button("Close other tabs", action: menu.closeOthers)
    }
}

/// The active chip's hairline: up the leading side, around the two top
/// corners, down the trailing side — and nothing across the bottom, where the
/// chip meets the toolbar. Inset half a point so a 1pt stroke sits inside the
/// chip instead of straddling its edge.
struct TabChipTopBorder: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let inset = rect.insetBy(dx: 0.5, dy: 0.5)
        let radius = min(cornerRadius, min(inset.width, inset.height) / 2)
        var path = Path()
        path.move(to: CGPoint(x: inset.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: inset.minX, y: inset.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: inset.minX + radius, y: inset.minY),
            control: CGPoint(x: inset.minX, y: inset.minY)
        )
        path.addLine(to: CGPoint(x: inset.maxX - radius, y: inset.minY))
        path.addQuadCurve(
            to: CGPoint(x: inset.maxX, y: inset.minY + radius),
            control: CGPoint(x: inset.maxX, y: inset.minY)
        )
        path.addLine(to: CGPoint(x: inset.maxX, y: rect.maxY))
        return path
    }
}

// MARK: - Group chip

struct TabGroupChip: View {
    let group: TabGroupRecord
    let tabCount: Int
    @Binding var editorPresented: Bool
    let toggleCollapse: () -> Void
    let newTabInGroup: () -> Void
    let rename: (String) -> Void
    let recolor: (String) -> Void
    let ungroup: () -> Void
    let closeGroup: () -> Void
    @State private var isHovered = false

    private var color: Color { TabGroupPalette.color(for: group.colorID) }

    private var accessibilityLabel: String {
        let name = group.displayName
        let count = tabCount == 1 ? "1 tab" : "\(tabCount) tabs"
        return group.isCollapsed ? "\(name), collapsed, \(count)" : "\(name), \(count)"
    }

    var body: some View {
        Button(action: toggleCollapse) {
            HStack(spacing: 6) {
                if group.title.isEmpty {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                } else {
                    Text(group.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if group.isCollapsed {
                    Text("\(tabCount)")
                        .font(ClearframeTheme.metaFont)
                        .tracking(ClearframeTheme.metaTracking)
                        .foregroundStyle(color.opacity(0.8))
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 22)
            .frame(maxWidth: 130)
            .background(
                TabGroupPalette.chipFill(for: group.colorID, isHovered: isHovered),
                in: RoundedRectangle(cornerRadius: ClearframeTheme.radius6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ClearframeTheme.radius6)
                    .stroke(TabGroupPalette.chipHairline(for: group.colorID), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: TabStripMetrics.chipHeight)
        .onHover { isHovered = $0 }
        .help(group.isCollapsed ? "Show the tabs in this group" : "Hide the tabs in this group")
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Hides or shows the tabs in this group.")
        .contextMenu {
            Button("New tab in group", action: newTabInGroup)
            Button("Rename…") { editorPresented = true }
            Menu("Color") {
                ForEach(TabGroupPalette.entries) { entry in
                    Button(entry.name) { recolor(entry.id) }
                }
            }
            Divider()
            Button("Ungroup", action: ungroup)
            Button("Close group", action: closeGroup)
        }
        .popover(isPresented: $editorPresented, arrowEdge: .top) {
            TabGroupEditor(
                group: group,
                rename: rename,
                recolor: recolor,
                newTabInGroup: {
                    editorPresented = false
                    newTabInGroup()
                },
                ungroup: {
                    editorPresented = false
                    ungroup()
                },
                closeGroup: {
                    editorPresented = false
                    closeGroup()
                }
            )
        }
    }
}

/// Name and color a group, and reach its three whole-group actions. Chrome's
/// editor is the reference for what belongs here; the surface itself is Halo —
/// one dark panel, hairline edges, no window chrome of its own.
private struct TabGroupEditor: View {
    let group: TabGroupRecord
    let rename: (String) -> Void
    let recolor: (String) -> Void
    let newTabInGroup: () -> Void
    let ungroup: () -> Void
    let closeGroup: () -> Void
    @State private var title: String

    init(
        group: TabGroupRecord,
        rename: @escaping (String) -> Void,
        recolor: @escaping (String) -> Void,
        newTabInGroup: @escaping () -> Void,
        ungroup: @escaping () -> Void,
        closeGroup: @escaping () -> Void
    ) {
        self.group = group
        self.rename = rename
        self.recolor = recolor
        self.newTabInGroup = newTabInGroup
        self.ungroup = ungroup
        self.closeGroup = closeGroup
        _title = State(initialValue: group.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Name this group", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ClearframeTheme.textPrimary)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(ClearframeTheme.bg3, in: RoundedRectangle(cornerRadius: ClearframeTheme.radius8))
                .overlay(
                    RoundedRectangle(cornerRadius: ClearframeTheme.radius8)
                        .stroke(ClearframeTheme.hairline2, lineWidth: 1)
                )
                // Live, like Chrome's: the chip in the strip renames as you type.
                .onChange(of: title) { _, value in rename(value) }
                .accessibilityLabel("Group name")

            HStack(spacing: 7) {
                ForEach(TabGroupPalette.entries) { entry in
                    swatch(entry)
                }
            }

            Rectangle()
                .fill(ClearframeTheme.hairline1)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 1) {
                TabGroupEditorAction(title: "New tab in group", symbol: "plus", action: newTabInGroup)
                TabGroupEditorAction(title: "Ungroup", symbol: "rectangle.expand.vertical", action: ungroup)
                TabGroupEditorAction(title: "Close group", symbol: "xmark", action: closeGroup)
            }
        }
        .padding(14)
        .frame(width: 268)
        .background(ClearframeTheme.bg2)
    }

    private func swatch(_ entry: TabGroupPalette.Entry) -> some View {
        let isSelected = entry.id == group.colorID
        return Button {
            recolor(entry.id)
        } label: {
            Circle()
                .fill(entry.color)
                .frame(width: 18, height: 18)
                .overlay(
                    Circle()
                        .stroke(ClearframeTheme.textPrimary, lineWidth: isSelected ? 2 : 0)
                        .padding(-3)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(entry.name)
        .accessibilityLabel(entry.name)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct TabGroupEditorAction: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 15)
                    .foregroundStyle(ClearframeTheme.textTertiary)
                Text(title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(ClearframeTheme.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                isHovered ? ClearframeTheme.itemHover : Color.clear,
                in: RoundedRectangle(cornerRadius: ClearframeTheme.radius6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Group enclosure

/// The tinted run behind a group: one segment per strip item, each bridging
/// the gap to its neighbor inside the group so the segments read as a single
/// enclosure. `colorID` of `nil` leaves an ungrouped tab exactly as it was.
private struct GroupEnclosureBackground: ViewModifier {
    let colorID: String?
    let roundsLeading: Bool
    let roundsTrailing: Bool
    var bridgesLeading: Bool = false
    var bridgesTrailing: Bool = false

    func body(content: Content) -> some View {
        content.background(alignment: .bottom) {
            if let colorID {
                enclosure(colorID: colorID)
                    .frame(height: TabStripMetrics.chipHeight + TabStripMetrics.groupEnclosureLift)
                    .padding(.leading, bridgesLeading ? -TabStripMetrics.spacing : 0)
                    .padding(.trailing, bridgesTrailing ? -TabStripMetrics.spacing : 0)
            }
        }
    }

    private func enclosure(colorID: String) -> some View {
        let radius = ClearframeTheme.radius10
        return ZStack {
            UnevenRoundedRectangle(
                topLeadingRadius: roundsLeading ? radius : 0,
                topTrailingRadius: roundsTrailing ? radius : 0
            )
            .fill(TabGroupPalette.enclosureFill(for: colorID))
            GroupEnclosureBorder(
                roundsLeading: roundsLeading,
                roundsTrailing: roundsTrailing,
                cornerRadius: radius
            )
            .stroke(TabGroupPalette.enclosureHairline(for: colorID), lineWidth: 1)
        }
    }
}

/// The enclosure's hairline, drawn only along the edges that are really edges:
/// across the top, down whichever ends close the run, and never across the
/// bottom, where the strip meets the toolbar. A bridged edge runs straight
/// into the next segment so the top line stays unbroken.
private struct GroupEnclosureBorder: Shape {
    let roundsLeading: Bool
    let roundsTrailing: Bool
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let minX = roundsLeading ? rect.minX + 0.5 : rect.minX
        let maxX = roundsTrailing ? rect.maxX - 0.5 : rect.maxX
        let minY = rect.minY + 0.5
        let radius = min(cornerRadius, max(0, min(maxX - minX, rect.maxY - minY) / 2))

        var path = Path()
        if roundsLeading {
            path.move(to: CGPoint(x: minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: minX, y: minY + radius))
            path.addQuadCurve(
                to: CGPoint(x: minX + radius, y: minY),
                control: CGPoint(x: minX, y: minY)
            )
        } else {
            path.move(to: CGPoint(x: minX, y: minY))
        }
        if roundsTrailing {
            path.addLine(to: CGPoint(x: maxX - radius, y: minY))
            path.addQuadCurve(
                to: CGPoint(x: maxX, y: minY + radius),
                control: CGPoint(x: maxX, y: minY)
            )
            path.addLine(to: CGPoint(x: maxX, y: rect.maxY))
        } else {
            path.addLine(to: CGPoint(x: maxX, y: minY))
        }
        return path
    }
}
