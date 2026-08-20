import AppKit
import ClearframeCore
import SwiftUI

struct AISettingsView: View {
    @EnvironmentObject private var configuration: AIConfigurationStore
    @EnvironmentObject private var workspace: BrowserWorkspace
    @EnvironmentObject private var onboarding: OnboardingController
    @AppStorage("clearframe.restoreTabs") private var restoresTabs = true
    @AppStorage("clearframe.reloadRestoredTabs") private var reloadsRestoredTabs = false
    @AppStorage("clearframe.saveHistory") private var savesHistory = true
    @State private var showsResetConfirmation = false
    @State private var isResettingBrowserData = false
    @State private var browserDataStatus = ""
    @StateObject private var siteData = SiteDataInventory()

    var body: some View {
        Form {
            DefaultBrowserSettingsSection()

            SearchEngineSettingsSection(settings: workspace.searchSettings)

            Section("Clearframe introduction") {
                Button("Show welcome tour") {
                    onboarding.revisit()
                    NSApp.keyWindow?.close()
                    Task { @MainActor in
                        await Task.yield()
                        BrowserApplicationActivation.bringBrowserToFront()
                    }
                }
                Text("Reopens the three-step introduction in the browser window. It does not clear tabs, history, bookmarks, or settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Enable Optional AI", isOn: $configuration.isEnabled)
                Text("Local summaries and visible risk signals work without an account or API key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Connection") {
                Toggle(
                    "Use HTTPS when a site is known to support it",
                    isOn: Binding(
                        get: { workspace.webFeatures.upgradesToHTTPS },
                        set: { workspace.webFeatures.setUpgradesToHTTPS($0) }
                    )
                )
                Text("Upgrades the address you are opening when WebKit already knows that host serves HTTPS. It applies to tabs you open from now on, and it upgrades the page request itself — it does not promise that everything the page then loads is encrypted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Advanced") {
                Toggle(
                    "Show features for web developers",
                    isOn: Binding(
                        get: { workspace.webFeatures.showsDeveloperFeatures },
                        set: {
                            workspace.webFeatures.setShowsDeveloperFeatures($0)
                            workspace.applyDeveloperFeatureSetting()
                        }
                    )
                )
                Text("Lets Safari's Develop menu attach the Web Inspector to pages open in Clearframe, so you can examine a page the way you would in Safari. Off by default. Changing it applies to tabs that are already open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Browser privacy") {
                Toggle("Restore open tabs when Clearframe starts", isOn: $restoresTabs)
                Text("When enabled, Clearframe stores only each open tab’s current URL and title in this Mac user profile. Page contents and assistant results are not restored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Load every restored tab at start", isOn: $reloadsRestoredTabs)
                    .disabled(!restoresTabs)
                Text("Off by default, as in other browsers: the tab you were on loads, and the rest load the first time you open them. They are all there with their names and site icons either way. Turning this on opens every page at start, which costs a burst of network and memory in exchange for pages already loaded when you get to them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Save browsing history on this Mac", isOn: $savesHistory)
                Text("History stays in this Mac user profile and is never included in AI requests. Turning this off stops Clearframe recording new visits; visits it already saved stay until you clear them from All Bookmarks (⌘⌥B) or with Clear local browsing data below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let notice = workspace.dataStore.recoveryNotice {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Local data recovery", systemImage: "externaldrive.badge.checkmark")
                            .font(.callout.weight(.semibold))
                        Text(notice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Dismiss") { workspace.dataStore.dismissRecoveryNotice() }
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
                Button("Clear local browsing data…", role: .destructive) {
                    showsResetConfirmation = true
                }
                .disabled(isResettingBrowserData || workspace.downloads.activeCount > 0)
                Text(workspace.downloads.activeCount > 0
                     ? "Cancel or finish active downloads before clearing browser data. Saved files are never deleted."
                     : "Clears tabs, history, bookmarks, the in-app download list, cookies, caches, local website storage, per-site tracker-blocking exceptions, and recovery backups. Saved files, search choice, onboarding state, and the Optional AI key are kept.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isResettingBrowserData {
                    ProgressView("Clearing local browser data…")
                        .font(.caption)
                } else if !browserDataStatus.isEmpty {
                    Text(browserDataStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SiteDataSettingsSection(inventory: siteData)

            ContentBlockingSettingsSection(provider: workspace.contentBlocking)

            Section("Bookmarks bar") {
                Toggle(
                    "Show bookmarks below the address bar",
                    isOn: Binding(
                        get: { workspace.dataStore.showsBookmarksBar },
                        set: { workspace.dataStore.showsBookmarksBar = $0 }
                    )
                )
                Text("Shows top-level folders and unfiled bookmarks in a compact local bar. Folder menus include nested subfolders. This preference and all bookmark data stay on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("OpenAI prototype connection") {
                SecureField("API key", text: $configuration.apiKey)
                    .disabled(!configuration.isEnabled)
                TextField("Model", text: $configuration.model)
                    .disabled(!configuration.isEnabled)
                Text("The key is stored in macOS Keychain. Improve with AI sends the page title, hostname, declared language, and up to 18,000 characters of extracted text only after you click. The full URL, query, fragment, cookies, form values, and history are not sent. Translation sends only the displayed summary and language names. Requests use `store: false`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Save settings") { configuration.save() }
                        .buttonStyle(.borderedProminent)
                    Button("Remove API key", role: .destructive) { configuration.removeKey() }
                    Spacer()
                }
                if !configuration.statusMessage.isEmpty {
                    Text(configuration.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("About") {
                LabeledContent("Clearframe") {
                    Text("by Zincoo")
                        .foregroundStyle(.secondary)
                }
                Link("zincoo.com", destination: URL(string: "https://zincoo.com/")!)
                    .font(.caption)
            }

            Section("Production boundary") {
                Text("Direct user-key access is only for this personal prototype. A public product must use an authenticated, metered backend, redact sensitive data, publish retention controls, and keep page agents read-only until a separate security review.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .task { await siteData.refresh() }
        .onChange(of: restoresTabs) { _, enabled in
            if !enabled {
                workspace.dataStore.clearSavedWorkspace()
            }
        }
        // Deliberately no `onChange` for `savesHistory`: switching it off used
        // to delete every stored visit as a side effect of a preference. The
        // preference decides what Clearframe records next (`recordVisit`
        // checks it); erasing what is already saved is a separate, confirmed
        // action the user takes from Clear History or Clear local browsing data.
        .confirmationDialog(
            "Clear local browsing data?",
            isPresented: $showsResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear browsing data", role: .destructive) {
                isResettingBrowserData = true
                browserDataStatus = ""
                Task { @MainActor in
                    await workspace.resetLocalBrowsingData()
                    isResettingBrowserData = false
                    browserDataStatus = "Local browsing data cleared."
                    // The per-site list describes the same WebKit store the
                    // reset just emptied; leaving it on screen would show
                    // sites that no longer hold anything.
                    await siteData.refresh()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Your Optional AI key and general preferences will remain.")
        }
    }
}

private struct SearchEngineSettingsSection: View {
    @ObservedObject var settings: SearchSettingsStore

    var body: some View {
        Section("Search engine") {
            Picker("Address-bar searches use", selection: $settings.selectedEngine) {
                ForEach(SearchEngine.allCases) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }

            Text("DuckDuckGo is Clearframe’s initial default, not its browser engine. You can change it here or from the search-engine menu inside the address bar.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Only text submitted as a search is sent to \(settings.selectedEngine.displayName). Website addresses open directly. Clearframe does not request suggestions while you type and has no claimed partnership with any listed provider.")
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
/// "4.9 MB · 34 cookies" is not something Clearframe could report without
/// inventing it.
private struct SiteDataSettingsSection: View {
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

            Text("Clearframe shows which kinds of data a site stored, not how much: WebKit reports no size and no number of cookies, so no amount is shown anywhere. Removing a site's data usually signs you out of it. Bookmarks, history, and downloaded files are kept.")
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

private struct ContentBlockingSettingsSection: View {
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
            Text("Blocks third-party requests to a curated list of common advertising and tracking domains — not a complete ad blocker. It does not stop first-party analytics, cookie-based tracking, or browser fingerprinting, and Clearframe cannot see or report how many requests were blocked on any page. The list changes only when Clearframe itself updates.")
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
