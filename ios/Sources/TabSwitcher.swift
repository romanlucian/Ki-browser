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

/// Filtering open tabs by what was typed.
///
/// Beside the switcher rather than in `LimeghostCore` next to
/// `BookmarksHomeSearch` and `HistoryHomeSearch`: those are shared because both
/// platforms search the same saved records and must not come to disagree about
/// what a search finds. The Mac's tab strip has no search and `TabRow` is the
/// phone's own type, so a shared helper would be a generic written for one
/// caller. Matching follows theirs — trimmed, case-insensitive `contains`,
/// over the title and the host.
enum TabSearch {
    static func rows(_ rows: [TabRow], matching query: String) -> [TabRow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rows }
        return rows.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || $0.host.localizedCaseInsensitiveContains(trimmed)
        }
    }
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

    /// The tabs one side of the segment is showing, filtered by what was
    /// typed. **Takes `isPrivate` rather than searching everything and sorting
    /// the results**, so a search of the ordinary tabs cannot surface a private
    /// one — the line the address sheet draws when it completes nothing at all
    /// in a private tab. It holds by construction here, and a test says so,
    /// because the next refactor is exactly where it would stop holding.
    func rows(isPrivate: Bool, matching query: String) -> [TabRow] {
        TabSearch.rows(rows(isPrivate: isPrivate), matching: query)
    }

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
///
/// Ordinary and private tabs were two stacked sections once, each with its own
/// `+`. The private one had to stay on screen holding nothing, because its `+`
/// was the only door into private browsing and hiding the empty section hid
/// the door. A segment is that door in one control instead of a permanently
/// empty section, and it says how many tabs are on the side you are not
/// looking at.
struct TabSwitcher: View {
    @ObservedObject private var workspace: BrowserWorkspace
    /// Observed separately from the workspace: a picture landing changes the
    /// store, and nothing about that reaches the workspace's own publisher.
    /// `StoredSiteIcon` subscribes to `FaviconStore` for the same reason.
    @ObservedObject private var previews: TabPreviewStore
    private let dismiss: () -> Void

    @State private var query = ""
    @State private var showingPrivate = false
    @Environment(\.scenePhase) private var scenePhase

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

    private var visibleRows: [TabRow] {
        model.rows(isPrivate: showingPrivate, matching: query)
    }

    var body: some View {
        NavigationStack {
            grid
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) { segment }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: dismiss)
                    }
                }
                .searchable(
                    text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search tabs"
                )
                // Switching sides is a change of subject, and a query typed
                // for one side quietly hiding tabs on the other is the kind of
                // empty screen nobody can explain.
                .onChange(of: showingPrivate) { _, _ in query = "" }
                .safeAreaInset(edge: .bottom) { bottomRow }
        }
        // The private side shows pictures of private pages, so it is hidden
        // the same way the page is when the app leaves — see `PrivacyCover`.
        .privacyCover(scenePhase != .active && showingPrivate)
        .limeghostListSheet()
    }

    private var segment: some View {
        Picker("Which tabs", selection: $showingPrivate) {
            Text("Tabs \(model.rows.count)").tag(false)
            // The private side drops its count when it is zero, which is most
            // of the time: "Private 0" is a number nobody needs, and seeing it
            // on a 375-point screen is what decided this rather than taste.
            // The ordinary side keeps its count always, because the workspace
            // never lets it reach zero.
            Text(model.privateRows.isEmpty ? "Private" : "Private \(model.privateRows.count)").tag(true)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 240)
    }

    private var grid: some View {
        ScrollView {
            if visibleRows.isEmpty {
                empty
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(visibleRows) { row in
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
                .padding(.vertical, 12)
            }
        }
        .background(LimeghostTheme.bg1)
    }

    @ViewBuilder
    private var empty: some View {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView.search(text: query)
        } else if showingPrivate {
            // The one empty state worth words: somebody who has never opened a
            // private tab is looking at this to find out what one is.
            ContentUnavailableView {
                Label("No private tabs", systemImage: "eye.slash.fill")
            } description: {
                Text("A private tab keeps no history, and nothing it loads is saved.")
            }
        }
    }

    private var bottomRow: some View {
        HStack(spacing: 16) {
            Button {
                model.addTab(isPrivate: showingPrivate)
                dismiss()
            } label: {
                Label(
                    showingPrivate ? "New Private Tab" : "New Tab",
                    systemImage: showingPrivate ? "plus.square.fill.on.square.fill" : "plus"
                )
            }
            Spacer(minLength: 0)
            if model.canReopenClosed {
                Button("Reopen closed tab") {
                    model.reopenClosedTab()
                    // A door, the same as adding a tab and selecting one: it
                    // produces a specific page to look at, so the switcher
                    // steps aside rather than leaving somebody staring at the
                    // list they just acted on. `reopenClosedTab()` already
                    // calls `makeRoomForPage()` in the shared layer — this is
                    // only the sheet following that lead.
                    dismiss()
                }
            }
        }
        .font(.subheadline)
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(LimeghostTheme.bg2)
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
