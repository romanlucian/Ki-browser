import LimeghostCore
import LimeghostShared
import SwiftUI

/// What the History sheet shows and does, apart from how it draws, so a test
/// can call it. Reads the store fresh on every call, like `BookmarksModel`.
@MainActor
struct HistoryModel {
    let workspace: BrowserWorkspace

    private var store: BrowserDataStore { workspace.dataStore }

    /// The visits matching what was typed, as days, newest first: the Mac's
    /// search filter, then Core's day grouping. The calendar and "now" are for
    /// tests, as they are in the grouping itself.
    func days(matching query: String, calendar: Calendar = .current, now: Date = Date()) -> [HistoryDayGroup] {
        HistoryDayGrouping.groups(HistoryHomeSearch.visits(store.history, matching: query), calendar: calendar, now: now)
    }

    /// Clear History is offered only while there is something to clear, as
    /// on the Mac.
    var canClear: Bool { !store.history.isEmpty }

    /// The same two doors as a bookmark's.
    func open(_ visit: HistoryRecord, inNewTab: Bool = false) {
        workspace.open(visit.url, inNewTab: inNewTab)
    }

    func delete(_ visit: HistoryRecord) {
        store.removeHistory(visit)
    }

    func clear() {
        store.clearHistory()
    }
}

/// The History sheet's words.
///
/// The confirmation follows the Mac's `ClearHistoryConfirmation` with two
/// differences. It names this device rather than the Mac, because the target
/// builds for iPad as well as iPhone. It does not mention downloaded files,
/// because the phone has none.
enum HistoryWording {
    static let clearTitle = "Clear all local history?"
    static let clearLabel = "Clear History"

    static func clearMessage(visitCount: Int) -> String {
        let visits = visitCount == 1 ? "1 stored visit" : "\(visitCount) stored visits"
        return "This removes \(visits) from this device and cannot be undone. Your bookmarks and open tabs are not affected."
    }

    /// Both already true. The workspace records a visit only when its tab is
    /// not private, and history never syncs.
    static let footnote = "Stored only on this device. Private tabs are never recorded."

    /// A visit with no title shows its address, so no row is blank.
    static func title(of visit: HistoryRecord) -> String {
        visit.title.isEmpty ? visit.url : visit.title
    }

    /// When, then where: "14:05 · example.com".
    static func detail(of visit: HistoryRecord) -> String {
        let time = visit.visitedAt.formatted(date: .omitted, time: .shortened)
        let host = URL(string: visit.url)?.host ?? visit.url
        return "\(time) · \(host)"
    }
}

/// History, over the page: visits by day, a search, and a way to clear them.
/// Opened from the page menu. A visit opens and the sheet closes.
struct HistorySheet: View {
    @ObservedObject private var store: BrowserDataStore
    private let workspace: BrowserWorkspace
    private let dismiss: () -> Void

    @State private var query = ""
    @State private var isConfirmingClear = false

    init(workspace: BrowserWorkspace, dismiss: @escaping () -> Void) {
        self.store = workspace.dataStore
        self.workspace = workspace
        self.dismiss = dismiss
    }

    private var model: HistoryModel { HistoryModel(workspace: workspace) }

    var body: some View {
        let days = model.days(matching: query)

        NavigationStack {
            List {
                ForEach(days) { day in
                    Section(day.title) {
                        ForEach(day.visits) { visit in
                            row(visit)
                        }
                    }
                }
                if !days.isEmpty {
                    Section {
                    } footer: {
                        Text(HistoryWording.footnote)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .overlay {
                if days.isEmpty {
                    emptyState
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search history"
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss)
                }
                if model.canClear {
                    ToolbarItem(placement: .bottomBar) {
                        Button(HistoryWording.clearLabel, role: .destructive) {
                            isConfirmingClear = true
                        }
                    }
                }
            }
            .confirmationDialog(
                HistoryWording.clearTitle,
                isPresented: $isConfirmingClear,
                titleVisibility: .visible
            ) {
                Button(HistoryWording.clearLabel, role: .destructive) { model.clear() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(HistoryWording.clearMessage(visitCount: store.history.count))
            }
        }
        .limeghostListSheet()
    }

    private func row(_ visit: HistoryRecord) -> some View {
        Button {
            model.open(visit)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                SiteIconView(urlString: visit.url)
                VStack(alignment: .leading, spacing: 2) {
                    Text(HistoryWording.title(of: visit))
                        .foregroundStyle(LimeghostTheme.textPrimary)
                        .lineLimit(1)
                    Text(HistoryWording.detail(of: visit))
                        .font(.caption)
                        .foregroundStyle(LimeghostTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .listRowBackground(LimeghostTheme.bg2)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                model.delete(visit)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                model.open(visit, inNewTab: true)
                dismiss()
            } label: {
                Label("Open in New Tab", systemImage: "plus.square.on.square")
            }
            Divider()
            Button(role: .destructive) {
                model.delete(visit)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView(
                "No History Yet",
                systemImage: "clock",
                description: Text("Pages you visit appear here. Private tabs are never recorded.")
            )
        } else {
            ContentUnavailableView.search(text: query)
        }
    }
}
