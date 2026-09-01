import AppKit
import LimeghostCore
import SwiftUI

// The settings sections the category pages reuse. The window and the pages
// live in SettingsWindow.swift; this file held one 357-line Form until
// September 1, 2026.

struct SearchEngineSettingsSection: View {
    @ObservedObject var settings: SearchSettingsStore

    var body: some View {
        Section("Search engine") {
            Picker("Address-bar searches use", selection: $settings.selectedEngine) {
                ForEach(SearchEngine.allCases) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }

            Text("DuckDuckGo is Limeghost’s initial default, not its browser engine. You can change it here or from the search-engine menu inside the address bar.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Only text submitted as a search is sent to \(settings.selectedEngine.displayName). Website addresses open directly. Limeghost does not request suggestions while you type and has no claimed partnership with any listed provider.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Every site that currently holds data in the non-private WebKit store, with a
/// remove button each. It sits beside **Clear local browsing data** rather than
/// replacing it: that action still clears everything at once, this one names a
/// single site.
///
/// It shows kinds of data and never an amount. `WKWebsiteDataRecord` carries a
/// display name and a set of data types — no byte count, no cookie count — so
/// "4.9 MB · 34 cookies" is not something Limeghost could report without
/// inventing it.
struct SiteDataSettingsSection: View {
    @ObservedObject var inventory: SiteDataInventory
    @State private var pendingRemoval: SiteDataEntry?

    var body: some View {
        Section("Site data") {
            Text("Websites you visit can store cookies, cached files, and local storage on this Mac. Remove a single site here, or clear everything with Clear local browsing data above. Private tabs are not listed: their storage is discarded when the tab closes.")
                .font(.caption)
                .foregroundStyle(.secondary)

            switch inventory.state {
            case .idle, .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading stored site data…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .loaded:
                if inventory.sites.isEmpty {
                    Text("No site has stored data on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(inventory.sites) { site in
                        row(for: site)
                    }
                    Button("Refresh list") {
                        Task { await inventory.refresh() }
                    }
                    .font(.caption)
                }
            }

            Text("Limeghost shows which kinds of data a site stored, not how much: WebKit reports no size and no number of cookies, so no amount is shown anywhere. Removing a site's data usually signs you out of it. Bookmarks, history, and downloaded files are kept.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The confirmation is attached to the row it acts on, so the dialog it
    /// opens is anchored to the site it names.
    private func row(for site: SiteDataEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(site.displayName)
                Text(site.kindSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if inventory.removingSite == site.displayName {
                ProgressView().controlSize(.small)
            } else {
                Button("Remove") { pendingRemoval = site }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .disabled(inventory.removingSite != nil)
                    .accessibilityLabel("Remove data stored by \(site.displayName)")
                    .accessibilityHint("Asks for confirmation first. \(site.displayName) currently holds \(site.kindSummary.lowercased()).")
            }
        }
        .confirmationDialog(
            "Remove data stored by \(site.displayName)?",
            isPresented: Binding(
                get: { pendingRemoval == site },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove site data", role: .destructive) {
                pendingRemoval = nil
                Task { await inventory.remove(site) }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("This removes \(site.displayName)'s cookies, cached files, and other stored website data from this Mac. You will probably be signed out of it. Your bookmarks, history, and downloaded files are kept. This cannot be undone.")
        }
    }
}

struct ContentBlockingSettingsSection: View {
    @ObservedObject var provider: ContentRuleListProvider

    var body: some View {
        Section("Tracker blocking") {
            Toggle(
                "Block trackers on visited sites",
                isOn: Binding(
                    get: { provider.settings.isEnabled },
                    set: { newValue in
                        Task { @MainActor in
                            await provider.setEnabled(newValue)
                        }
                    }
                )
            )
            Text("Blocks third-party requests to a curated list of common advertising and tracking domains — not a complete ad blocker. It does not stop first-party analytics, cookie-based tracking, or browser fingerprinting, and Limeghost cannot see or report how many requests were blocked on any page. The list changes only when Limeghost itself updates.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if case .unavailable(let reason) = provider.status {
                Label("Filter unavailable: \(reason)", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 6) {
                Label("List \(provider.blockList.release.version)", systemImage: "checkmark.seal")
                Text("·")
                Text("Checked")
                Text(provider.blockList.release.lastChecked, format: .dateTime.month(.abbreviated).day().year())
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if provider.settings.disabledHosts.isEmpty {
                Text("No sites are excluded from tracker blocking.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(provider.settings.disabledHosts, id: \.self) { host in
                    HStack {
                        Text(host)
                        Spacer()
                        Button("Remove") {
                            Task { @MainActor in
                                await provider.setSiteDisabled(false, forHost: host)
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                    }
                }
                Text("Trackers stay blocked everywhere else. An exception for a site also covers its www. address, but not other subdomains.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
