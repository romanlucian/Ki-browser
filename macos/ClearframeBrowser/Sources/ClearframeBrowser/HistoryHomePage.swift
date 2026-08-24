import ClearframeCore
import SwiftUI

/// One wording for the Clear History confirmation, used wherever history can
/// be cleared. Clearing removes every stored visit and cannot be undone, so
/// it always asks first, and always says how many.
enum ClearHistoryConfirmation {
    static let title = "Clear all local history?"
    static let confirmLabel = "Clear history"

    static func message(visitCount: Int) -> String {
        let visits = visitCount == 1 ? "1 stored visit" : "\(visitCount) stored visits"
        return "This removes \(visits) from this Mac and cannot be undone. Your bookmarks, open tabs, and downloaded files are not affected."
    }
}

/// The full-page history surface (⌘Y, and History ▸ Show Full History).
///
/// A separate destination from the bookmarks home on purpose. Bookmarks are a
/// collection somebody arranges — folders, names, an order they chose.
/// History is a log they search and occasionally want gone. Putting both
/// behind one toggle made every way in land on the wrong half: until this
/// existed, the History menu's own "Show Full History" opened the bookmarks
/// page.
///
/// Reads the same records the address bar completes from. It is a second view
/// of one store, never a second copy.
struct HistoryHomePage: View {
    @ObservedObject var store: BrowserDataStore
    let open: (String, Bool) -> Void

    @State private var search = ""
    @State private var showsClearHistoryConfirmation = false

    private var trimmedSearch: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool { !trimmedSearch.isEmpty }

    private var visibleVisits: [HistoryRecord] {
        HistoryHomeSearch.visits(store.history, matching: trimmedSearch)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    HomeSearchField(placeholder: "Search history", text: $search)
                    visitGroups
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 26)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(ClearframeTheme.bg0)
        .confirmationDialog(
            ClearHistoryConfirmation.title,
            isPresented: $showsClearHistoryConfirmation,
            titleVisibility: .visible
        ) {
            Button(ClearHistoryConfirmation.confirmLabel, role: .destructive) { store.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(ClearHistoryConfirmation.message(visitCount: store.history.count))
        }
        .accessibilityLabel("History")
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("HISTORY")
                .font(ClearframeTheme.metaFont)
                .tracking(ClearframeTheme.metaTracking)
                .foregroundStyle(ClearframeTheme.textTertiary)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

            Text("\(store.history.count) stored \(store.history.count == 1 ? "visit" : "visits")")
                .font(.system(size: 12))
                .foregroundStyle(ClearframeTheme.textSecondary)
                .padding(.horizontal, 10)

            Spacer(minLength: 12)

            if !store.history.isEmpty {
                Button(role: .destructive) { showsClearHistoryConfirmation = true } label: {
                    Label("Clear History…", systemImage: "trash")
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 4)
            }

            // Both of these are already true, and both are the sort of thing
            // a person checks precisely when they have come here to clear
            // something.
            VStack(alignment: .leading, spacing: 6) {
                Label("Stored only in this Mac user profile.", systemImage: "lock")
                Text("Private windows are never recorded. Turning off Save browsing history stops new visits without deleting stored ones.")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(ClearframeTheme.textTertiary)
            .padding(.horizontal, 10)
        }
        .padding(.vertical, 22)
        .frame(width: 210, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ClearframeTheme.bg1)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("History")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(ClearframeTheme.textPrimary)
            Text("Recent page visits saved on this Mac. Clearing history removes them from this device.")
                .font(.system(size: 12))
                .foregroundStyle(ClearframeTheme.textTertiary)
        }
    }

    // MARK: - Visits

    @ViewBuilder
    private var visitGroups: some View {
        let visits = visibleVisits
        if visits.isEmpty {
            HomeEmptyNote(
                isSearching
                    ? "No stored visit matches “\(trimmedSearch)”."
                    : "No local history yet. Completed page visits appear here."
            )
        } else {
            // One pass over a few hundred records, computed here rather than
            // per row.
            let groups = HistoryDayGrouping.groups(visits)
            VStack(alignment: .leading, spacing: 20) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 9) {
                        HomeSectionTitle(title: group.title.uppercased(), count: group.visits.count)
                        LazyVStack(spacing: 5) {
                            ForEach(group.visits) { visit in
                                HistoryEntryRow(
                                    title: visit.title.isEmpty ? visit.url : visit.title,
                                    url: visit.url,
                                    detail: visit.visitedAt.formatted(date: .omitted, time: .shortened),
                                    open: { open(visit.url, false) },
                                    openNewTab: { open(visit.url, true) },
                                    remove: { store.removeHistory(visit) }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Filtering history by what was typed. Pure and static so it can be tested
/// without a view.
enum HistoryHomeSearch {
    static func visits(_ visits: [HistoryRecord], matching search: String) -> [HistoryRecord] {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return visits }
        return visits.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) || $0.url.localizedCaseInsensitiveContains(trimmed)
        }
    }
}

/// One stored visit. Opening it is the whole row, so the target is the width
/// of the list rather than the length of the title.
struct HistoryEntryRow: View {
    let title: String
    let url: String
    let detail: String?
    let open: () -> Void
    let openNewTab: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) {
                HStack(spacing: 10) {
                    if let detail {
                        Text(detail)
                            .font(ClearframeTheme.metaFont)
                            .foregroundStyle(ClearframeTheme.textTertiary)
                            .frame(width: 58, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13))
                            .foregroundStyle(ClearframeTheme.textPrimary)
                            .lineLimit(1)
                        Text(url)
                            .font(.system(size: 11))
                            .foregroundStyle(ClearframeTheme.textTertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: openNewTab) {
                Image(systemName: "plus.square.on.square").frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(ClearframeTheme.textTertiary)
            .help("Open in new tab")
            Button(action: remove) {
                Image(systemName: "trash").frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(ClearframeTheme.textTertiary)
            .help("Remove from history")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(ClearframeTheme.bg1, in: RoundedRectangle(cornerRadius: ClearframeTheme.radius10))
    }
}
