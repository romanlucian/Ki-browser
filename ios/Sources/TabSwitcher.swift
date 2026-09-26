import CoreGraphics
import LimeghostShared
import SwiftUI

/// One tab as the switcher draws it. Nothing here reaches back into
/// `BrowserTab` or its session, so the grid can be laid out — and the split
/// between ordinary and private tabs asserted — without a live `WKWebView`.
struct TabRow: Identifiable, Equatable {
    let id: UUID
    let title: String
    let host: String
    let isPrivate: Bool
}

/// What the switcher shows and does, apart from how it draws it, so a test
/// can assert the private split without standing up SwiftUI. A struct, not a
/// class: it holds only the workspace reference and reads it fresh on every
/// access, the same shape as `AddressSheetModel`.
@MainActor
struct TabSwitcherModel {
    private let workspace: BrowserWorkspace

    init(workspace: BrowserWorkspace) {
        self.workspace = workspace
    }

    /// The ordinary tabs. Never includes a private one — see `privateRows`.
    var rows: [TabRow] { rows(isPrivate: false) }

    /// Private tabs, kept apart on purpose. They are ephemeral and excluded
    /// from history, and folding them into `rows` would blur a line the
    /// product draws deliberately.
    var privateRows: [TabRow] { rows(isPrivate: true) }

    var canReopenClosed: Bool { workspace.canReopenClosedTab }

    /// Which card to ring. Without this the grid says nothing about where you
    /// already are, which is survivable in a list of titles and not in a wall
    /// of page pictures that all look like pages.
    var selectedID: UUID? { workspace.selectedTabID }

    /// What a tab last looked like, or `nil` until it has been looked at once.
    /// Reading the preview store keeps this type's promise: a store is a
    /// cache, not a session, so the grid still lays out without a live
    /// `WKWebView` and the three tests above still run without one.
    func preview(for id: UUID) -> CGImage? { workspace.tabPreviews.preview(for: id) }

    /// Selecting a tab that already exists is not a request for a *different*
    /// page, so this reaches `selectTab` directly and never
    /// `makeRoomForPage()` — the same distinction the Mac's strip draws.
    func select(_ id: UUID) { workspace.selectTab(id) }

    func close(_ id: UUID) { workspace.closeTab(id) }

    /// The only way this screen can start a private tab is the `+` in the
    /// private section, which calls this with `isPrivate: true`. Without it
    /// `privateRows` could never hold anything in real use.
    func addTab(isPrivate: Bool) { workspace.addTab(isPrivate: isPrivate) }

    func reopenClosedTab() { workspace.reopenClosedTab() }

    private func rows(isPrivate: Bool) -> [TabRow] {
        workspace.visibleTabs
            .filter { $0.isPrivate == isPrivate }
            .map { TabRow(id: $0.id, title: $0.displayTitle, host: $0.iconHost, isPrivate: $0.isPrivate) }
    }
}

/// Every open tab, in a grid because a phone has no room for the Mac's strip
/// — this is the only way to see or manage tabs here. Presented as a sheet
/// from `BottomBar`'s tab button, the way `AddressSheet` is presented from
/// its address pill.
struct TabSwitcher: View {
    @ObservedObject private var workspace: BrowserWorkspace
    /// Observed separately from the workspace: a picture landing changes the
    /// store, and nothing about that reaches the workspace's own publisher.
    /// `StoredSiteIcon` subscribes to `FaviconStore` for the same reason.
    @ObservedObject private var previews: TabPreviewStore
    private let dismiss: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    init(workspace: BrowserWorkspace, dismiss: @escaping () -> Void) {
        self.workspace = workspace
        self.previews = workspace.tabPreviews
        self.dismiss = dismiss
    }

    // Recomputed on every access rather than stored: `workspace` is
    // `@ObservedObject`, so a tab opening or closing invalidates this view,
    // and the model must re-read the workspace's current tabs when it does.
    private var model: TabSwitcherModel { TabSwitcherModel(workspace: workspace) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tabs")
                    .font(.headline)
                Spacer()
                Button("Done", action: dismiss)
            }
            .padding()
            .background(LimeghostTheme.bg1)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if model.canReopenClosed {
                        Button("Reopen closed tab") {
                            model.reopenClosedTab()
                            // A door, the same as adding a tab and selecting
                            // one: it produces a specific page to look at, so
                            // the switcher steps aside for it rather than
                            // leaving somebody staring at the list they just
                            // acted on. `reopenClosedTab()` already calls
                            // `makeRoomForPage()` in the shared layer — this
                            // is only the sheet following that lead.
                            dismiss()
                        }
                        .padding(.horizontal)
                    }

                    section(rows: model.rows, isPrivate: false)

                    // Always shown, even with zero private tabs: its `+` is
                    // the only way this screen can ever start one. Hiding
                    // the section until it holds something — tried first —
                    // hides the one door into it, so it can never hold
                    // anything in real use.
                    section(rows: model.privateRows, isPrivate: true)
                }
                .padding(.vertical)
            }
        }
        .background(LimeghostTheme.bg1)
        .limeghostListSheet()
    }

    @ViewBuilder
    private func section(rows: [TabRow], isPrivate: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if isPrivate {
                    Label("Private", systemImage: "eye.slash.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.purple)
                }
                Spacer()
                Button {
                    model.addTab(isPrivate: isPrivate)
                    dismiss()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(isPrivate ? "New private tab" : "New tab")
            }
            .padding(.horizontal)

            // Omitted rather than left to render empty: an empty `LazyVGrid`
            // still claims its own spacing from the `VStack` above, which
            // would leave a dangling gap under a section with nothing in it
            // yet — the private section's ordinary state before its first tab.
            if !rows.isEmpty {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(rows) { row in
                        TabCard(
                            row: row,
                            preview: previews.preview(for: row.id),
                            isSelected: row.id == model.selectedID,
                            select: { select(row.id) },
                            close: { model.close(row.id) }
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func select(_ id: UUID) {
        model.select(id)
        dismiss()
    }
}

/// One card: the page as it last looked, under a strip carrying the site's
/// mark, its title and a close control.
///
/// The height is **not a number**. It comes from the preview's 3:4 aspect
/// ratio, so one rule covers an iPhone SE, a Pro Max and landscape rather than
/// three constants kept in step by hand — the same reasoning that made the
/// Mac's address pill a `Capsule`. It replaced a fixed height of 110, which
/// left a card too short to say anything about the page inside it.
///
/// Internal rather than private only so `testACardIsTallerThanItIsWide` can
/// render one: a height the layout system alone knows is a height no
/// arithmetic in a test can check.
struct TabCard: View {
    let row: TabRow
    /// `nil` until this tab has been looked at once. Not an error state: it is
    /// what every tab shows after a relaunch, because previews are never
    /// written to disk.
    let preview: CGImage?
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void

    private var cornerRadius: CGFloat { LimeghostTheme.radius12 }

    var body: some View {
        VStack(spacing: 0) {
            header
            page
        }
        .background(LimeghostTheme.bg2)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay {
            // Limeghost's accent, not Chrome's blue. A ring rather than a
            // tint, because a tinted card would fight the page inside it.
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    isSelected ? LimeghostTheme.accent : Color.white.opacity(0.08),
                    lineWidth: isSelected ? 2 : 1
                )
        }
        // A plain tap surface, not an outer `Button`: the close control above
        // is a real `Button` of its own, and a `Button` nested inside another
        // `Button`'s label is exactly the ambiguous hit-testing this avoids.
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var header: some View {
        HStack(spacing: 6) {
            SiteIconView(host: row.host, size: LimeghostTheme.siteIconSize)
            Text(row.title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 2)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close tab")
        }
        .padding(.leading, 8)
        .frame(height: 34)
    }

    private var page: some View {
        LimeghostTheme.bg1
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay(alignment: .top) {
                if let preview {
                    // Cropped from the top, not centred: a page reads from its
                    // first line, and a centre crop of a long article shows
                    // the middle of a paragraph.
                    Image(decorative: preview, scale: 1)
                        .resizable()
                        .scaledToFill()
                }
            }
            .overlay {
                if preview == nil {
                    // What an unvisited site already shows everywhere else in
                    // the product — never a grey rectangle, which reads as a
                    // page that failed rather than one not yet seen.
                    SiteIconView(host: row.host, size: 40)
                }
            }
            .clipped()
    }
}
