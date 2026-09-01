import AppKit
import LimeghostCore
import SwiftUI

/// One page of Settings.
///
/// Nine, because that is how many groups the settings actually fall into — not
/// a target. A category with nothing real in it is worse than no category, so
/// Profiles is absent: the Profiles menu already creates, renames, recolours
/// and deletes them, and a second surface for that would be two places to
/// change one thing.
enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case search
    case tabs
    case privacy
    case blocking
    case downloads
    case bookmarks
    case advanced
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .search: return "Search"
        case .tabs: return "Tabs"
        case .privacy: return "Privacy"
        case .blocking: return "Blocking"
        case .downloads: return "Downloads"
        case .bookmarks: return "Bookmarks"
        case .advanced: return "Advanced"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .search: return "magnifyingglass"
        case .tabs: return "square.on.square"
        case .privacy: return "hand.raised"
        case .blocking: return "shield"
        case .downloads: return "arrow.down.circle"
        case .bookmarks: return "book"
        case .advanced: return "wrench.and.screwdriver"
        case .about: return "info.circle"
        }
    }
}

/// Settings, as a sidebar and a page.
///
/// It was one scrolling `Form` of eleven sections until September 1, 2026. The
/// complaint that it "looked less professional" than other browsers was
/// structural rather than cosmetic: everything was on screen at once, so
/// nothing had a place, and finding one setting meant reading past ten. The
/// same fault the site information popover had, and the same fix.
struct LimeghostSettingsView: View {
    @EnvironmentObject private var onboarding: OnboardingController
    @State private var selection: SettingsCategory = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsCategory.allCases, selection: $selection) { category in
                NavigationLink(value: category) {
                    Label(category.title, systemImage: category.symbol)
                }
            }
            .navigationSplitViewColumnWidth(min: 168, ideal: 178, max: 220)
        } detail: {
            ScrollView {
                page
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(selection.title)
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    @ViewBuilder
    private var page: some View {
        switch selection {
        case .general: GeneralSettingsPage()
        case .search: SearchSettingsPage()
        case .tabs: TabsSettingsPage()
        case .privacy: PrivacySettingsPage()
        case .blocking: BlockingSettingsPage()
        case .downloads: DownloadsSettingsPage()
        case .bookmarks: BookmarksSettingsPage()
        case .advanced: AdvancedSettingsPage()
        case .about: AboutSettingsPage()
        }
    }
}

// MARK: - General

private struct GeneralSettingsPage: View {
    @EnvironmentObject private var onboarding: OnboardingController
    @ObservedObject private var preferences = BrowserPreferences.shared

    var body: some View {
        Form {
            DefaultBrowserSettingsSection()

            Section("Start-up") {
                Picker("When Limeghost opens, show", selection: $preferences.startup) {
                    ForEach(StartupBehaviour.allCases) { Text($0.title).tag($0) }
                }
                if preferences.startup == .specificPage {
                    TextField("Address", text: $preferences.startupPage, prompt: Text("example.com"))
                }
                Text(startupExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Home button") {
                Picker("The Home button opens", selection: $preferences.homeTarget) {
                    ForEach(HomeTarget.allCases) { Text($0.title).tag($0) }
                }
                if preferences.homeTarget == .specificPage {
                    TextField("Address", text: $preferences.homePage, prompt: Text("example.com"))
                }
                Text("Applies to the Home button in the toolbar. A new tab always opens the AI guide, which is what Limeghost is for.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Page text") {
                Picker("Text size on new pages", selection: $preferences.defaultPageZoom) {
                    ForEach(BrowserSession.pageZoomSteps, id: \.self) { step in
                        Text("\(Int((step * 100).rounded()))%").tag(step)
                    }
                }
                Text("The size a page opens at. ⌘+ and ⌘− still change the page in front of you without altering this.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Limeghost introduction") {
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
        }
        .formStyle(.grouped)
    }

    private var startupExplanation: String {
        switch preferences.startup {
        case .newTab:
            return "Limeghost opens on the AI guide and keeps no record of the tabs you had open."
        case .restore:
            return "Limeghost stores only each open tab's address and title in this Mac user profile. Page contents and assistant conversations are not restored."
        case .specificPage:
            return "Limeghost opens this page instead of the AI guide, and keeps no record of the tabs you had open."
        }
    }
}

// MARK: - Search

private struct SearchSettingsPage: View {
    var body: some View {
        Form {
            SearchEngineSettingsSection(settings: BrowserServices.shared.searchSettings)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Tabs

private struct TabsSettingsPage: View {
    @ObservedObject private var preferences = BrowserPreferences.shared
    @AppStorage("clearframe.reloadRestoredTabs") private var reloadsRestoredTabs = false

    var body: some View {
        Form {
            Section("Restoring") {
                Toggle("Load every restored tab at start", isOn: $reloadsRestoredTabs)
                    .disabled(preferences.startup != .restore)
                Text("Off by default, as in other browsers: the tab you were on loads, and the rest load the first time you open them. They are all there with their names and site icons either way. Turning this on opens every page at start, which costs a burst of network and memory in exchange for pages already loaded when you get to them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if preferences.startup != .restore {
                    Text("Available when start-up is set to open the tabs you had open, in General.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Privacy

private struct PrivacySettingsPage: View {
    private let services = BrowserServices.shared
    @ObservedObject private var dataStore = BrowserServices.shared.dataStore
    @ObservedObject private var downloads = BrowserServices.shared.downloads
    @ObservedObject private var webFeatures = BrowserServices.shared.webFeatures
    @AppStorage("clearframe.saveHistory") private var savesHistory = true
    @StateObject private var siteData = SiteDataInventory()
    @State private var showsResetConfirmation = false
    @State private var isResettingBrowserData = false
    @State private var browserDataStatus = ""

    var body: some View {
        Form {
            Section("Connection") {
                Toggle(
                    "Use HTTPS when a site is known to support it",
                    isOn: Binding(
                        get: { webFeatures.upgradesToHTTPS },
                        set: { webFeatures.setUpgradesToHTTPS($0) }
                    )
                )
                Text("Upgrades the address you are opening when WebKit already knows that host serves HTTPS. It applies to tabs you open from now on, and it upgrades the page request itself — it does not promise that everything the page then loads is encrypted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("History") {
                Toggle("Save browsing history on this Mac", isOn: $savesHistory)
                Text("History stays in this Mac user profile and is never included in AI requests. Turning this off stops Limeghost recording new visits; visits it already saved stay until you clear them from History (⌘Y) or with Clear local browsing data below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SiteDataSettingsSection(inventory: siteData)

            Section("Clear everything") {
                if let notice = dataStore.recoveryNotice {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("Local data recovery", systemImage: "externaldrive.badge.checkmark")
                            .font(.callout.weight(.semibold))
                        Text(notice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Dismiss") { dataStore.dismissRecoveryNotice() }
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
                Button("Clear local browsing data…", role: .destructive) {
                    showsResetConfirmation = true
                }
                .disabled(isResettingBrowserData || downloads.activeCount > 0)
                Text(downloads.activeCount > 0
                     ? "Cancel or finish active downloads before clearing browser data. Saved files are never deleted."
                     : "Clears tabs, history, bookmarks, the in-app download list, cookies, caches, local website storage, per-site tracker-blocking exceptions, and recovery backups. Saved files, search choice, and onboarding state are kept.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if isResettingBrowserData {
                    ProgressView("Clearing local browser data…")
                        .font(.caption)
                } else if !browserDataStatus.isEmpty {
                    Text(browserDataStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task { await siteData.refresh() }
        // Deliberately no `onChange` for `savesHistory`: switching it off used
        // to delete every stored visit as a side effect of a preference. The
        // preference decides what Limeghost records next (`recordVisit`
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
                    for window in services.liveWorkspaces { await window.resetLocalBrowsingData() }
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
            Text("This cannot be undone. Your general preferences will remain.")
        }
    }
}

// MARK: - Blocking

private struct BlockingSettingsPage: View {
    var body: some View {
        Form {
            ContentBlockingSettingsSection(provider: BrowserServices.shared.contentBlocking)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Downloads

private struct DownloadsSettingsPage: View {
    @ObservedObject private var preferences = BrowserPreferences.shared

    var body: some View {
        Form {
            Section("Saving") {
                Toggle("Ask where to save each file", isOn: $preferences.asksWhereToSave)
                LabeledContent("Save files to") {
                    HStack(spacing: 8) {
                        Text(preferences.downloadFolderDisplayName)
                            .foregroundStyle(.secondary)
                        Button("Choose…") { chooseFolder() }
                        if !preferences.downloadFolderPath.isEmpty {
                            Button("Reset") { preferences.downloadFolderPath = "" }
                        }
                    }
                }
                .disabled(preferences.asksWhereToSave)
                Text(preferences.asksWhereToSave
                     ? "Limeghost shows a save panel for every download, which is what it has always done. Turn this off to send files straight to the folder above."
                     : "Files are saved here without asking. If the folder is missing or Limeghost is not allowed to write to it, it shows the save panel instead rather than failing the download.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.title = "Save downloads to"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        preferences.downloadFolderPath = url.path
    }
}

// MARK: - Bookmarks

private struct BookmarksSettingsPage: View {
    @ObservedObject private var dataStore = BrowserServices.shared.dataStore

    var body: some View {
        Form {
            Section("Bookmarks bar") {
                Toggle(
                    "Show bookmarks below the address bar",
                    isOn: Binding(
                        get: { dataStore.showsBookmarksBar },
                        set: { dataStore.showsBookmarksBar = $0 }
                    )
                )
                Text("Shows top-level folders and unfiled bookmarks in a compact local bar. Folder menus include nested subfolders. This preference and all bookmark data stay on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Advanced

private struct AdvancedSettingsPage: View {
    private let services = BrowserServices.shared
    @ObservedObject private var webFeatures = BrowserServices.shared.webFeatures

    var body: some View {
        Form {
            Section("Web development") {
                Toggle(
                    "Show features for web developers",
                    isOn: Binding(
                        get: { webFeatures.showsDeveloperFeatures },
                        set: {
                            webFeatures.setShowsDeveloperFeatures($0)
                            services.liveWorkspaces.forEach { $0.applyDeveloperFeatureSetting() }
                        }
                    )
                )
                Text("Lets Safari's Develop menu attach the Web Inspector to pages open in Limeghost, so you can examine a page the way you would in Safari. Off by default. Changing it applies to tabs that are already open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Production boundary") {
                Text("Direct user-key access is only for this personal prototype. A public product must use an authenticated, metered backend, redact sensitive data, publish retention controls, and keep page agents read-only until a separate security review.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

private struct AboutSettingsPage: View {
    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    BrandMark(size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Limeghost")
                            .font(.title3.weight(.semibold))
                        Text("by Zincoo")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                Link("zincoo.com", destination: URL(string: "https://zincoo.com/")!)
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
    }
}
