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
    private let dismiss: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    init(workspace: BrowserWorkspace, dismiss: @escaping () -> Void) {
        self.workspace = workspace
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

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if model.canReopenClosed {
                        Button("Reopen closed tab") {
                            model.reopenClosedTab()
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

/// One card: title, host, and a close control — the least a tab can show and
/// still be told apart from its neighbors in a grid with no room for more.
private struct TabCard: View {
    let row: TabRow
    let select: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Close tab")
            }

            Spacer(minLength: 24)

            Text(row.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(row.host)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(height: 110, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary))
        // A plain tap surface, not an outer `Button`: the close control above
        // is a real `Button` of its own, and a `Button` nested inside another
        // `Button`'s label is exactly the ambiguous hit-testing this avoids.
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
    }
}
