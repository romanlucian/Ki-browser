import LimeghostCore
import LimeghostShared
import SwiftUI

/// What Settings reads and changes, apart from how it draws, so a test can
/// call it, as `HistoryModel` is for History. Every value lives in a store the
/// rest of the app already reads, and every one is a setting the Mac's
/// Settings changes too: the phone offers fewer of them, never different ones.
@MainActor
struct SettingsModel {
    let workspace: BrowserWorkspace
    /// Application-wide, as on the Mac. A test hands in its own, so it never
    /// writes into the simulator's real preferences.
    var preferences: BrowserPreferences = .shared

    /// Two of the Mac's three. The third, a page of one's own choosing, would
    /// mean typing an address into Settings for a moment iOS picks rather
    /// than the person: an iPhone app is resumed far more often than it is
    /// started, and starts again only after it has been ended.
    static let startupChoices: [StartupBehaviour] = [.restore, .newTab]

    /// Per profile on the Mac, so it lives in the data store rather than the
    /// preferences. Choosing anything but restore also erases the saved
    /// session, in the store's own setter.
    var startup: StartupBehaviour {
        get { workspace.dataStore.startupBehaviour }
        nonmutating set { workspace.dataStore.startupBehaviour = newValue }
    }

    /// The size pages open at, and on the phone the size of the ones already
    /// open as well: there is no ⌘+ here, so without that a change would look
    /// as though it did nothing until a new tab opened.
    var pageZoom: CGFloat {
        get { preferences.defaultPageZoom }
        nonmutating set {
            preferences.defaultPageZoom = newValue
            for tab in workspace.tabs {
                tab.session.setPageZoom(newValue)
            }
        }
    }

    var searchEngine: SearchEngine {
        get { workspace.searchSettings.selectedEngine }
        nonmutating set { workspace.searchSettings.selectedEngine = newValue }
    }

    /// Decides what is recorded next, and nothing more. Turning it off erases
    /// no visit already saved; on the Mac it once did, as a side effect of a
    /// preference, and that was taken out.
    var savesHistory: Bool {
        get { workspace.dataStore.savesHistory }
        nonmutating set { workspace.dataStore.savesHistory = newValue }
    }

    var upgradesToHTTPS: Bool {
        get { workspace.webFeatures.upgradesToHTTPS }
        nonmutating set { workspace.webFeatures.setUpgradesToHTTPS(newValue) }
    }

    var blocksTrackers: Bool { workspace.contentBlocking.settings.isEnabled }

    /// Returns once every open page has the change.
    func setBlocksTrackers(_ value: Bool) async {
        await workspace.contentBlocking.setEnabled(value)
    }

    /// The Mac's reset, unchanged: see `BrowserWorkspace.resetLocalBrowsingData`.
    func clearBrowsingData() async {
        await workspace.resetLocalBrowsingData()
    }

    /// A tab of its own, through the door every other page is asked for by.
    func openMakersSite() {
        workspace.open(SettingsWording.makersAddress, inNewTab: true)
    }
}

/// Settings' words. Each says only what the code does, and the tests hold
/// them to it. Adapted from the Mac's Settings, with "this Mac" made "this
/// iPhone" and the parts about controls the phone lacks left out.
enum SettingsWording {
    static func startupExplanation(_ choice: StartupBehaviour) -> String {
        switch choice {
        case .restore:
            // A relaunch restores at most twelve: `BrowserWorkspaceSnapshot.normalized`.
            return "Your open tabs come back when Limeghost starts again \u{2014} the twelve you used last, if there are more. Private tabs never do."
        case .newTab:
            return "Limeghost starts on the AI guide, and your tabs are not reopened. An iPhone can end an app in the background to free memory, so this can happen without you closing it."
        case .specificPage:
            // The phone never offers it, but the Mac's store can hold it.
            return "Limeghost starts on the page chosen for start-up, and your tabs are not reopened."
        }
    }

    static func percent(_ zoom: CGFloat) -> String {
        "\(Int((zoom * 100).rounded()))%"
    }

    static let textSizeFooter = "Applies to the pages you have open, and to every page you open after."

    static func searchFooter(_ engine: SearchEngine) -> String {
        "Only text you submit as a search is sent to \(engine.displayName). Addresses open directly, and nothing is sent while you type."
    }

    static let historyFooter = "Limeghost never sends your history anywhere. Turning this off stops new visits being saved; the ones already saved stay until you clear them in History."

    static let httpsFooter = "Opens a site over HTTPS when WebKit already knows it supports it. It applies to tabs you open from now on, and does not promise that everything a page loads is encrypted."

    static let siteDataFooter = "Cookies, cached files and storage that websites keep on this iPhone. Removing a site\u{2019}s data usually signs you out of it. Private tabs are not listed: their storage goes when the tab closes."

    /// The Mac's own caveats, shortened, none dropped: a list, not a complete
    /// ad blocker, nothing counted.
    static let blockingFooter = "Blocks requests to a list of common advertising and tracking sites. It is not a complete ad blocker: a site\u{2019}s own analytics, cookies and fingerprinting are not stopped, and Limeghost cannot see how many requests it blocked."

    /// Everything `resetLocalBrowsingData` removes, in words. Bookmarks are
    /// named twice, here and in the confirmation, because Safari and Chrome
    /// keep them through the same action and somebody coming from either
    /// would not expect this to take them.
    static let clearFooter = "Removes your open and recently closed tabs, history, bookmarks, tab previews, site icons, cookies, caches and website storage, and closes the assistant. You will be signed out of websites, your assistant included. Your settings stay."
    static let clearLabel = "Clear Browsing Data"
    static let clearTitle = "Clear browsing data?"
    static let clearMessage = "This cannot be undone. Your bookmarks are removed too; your settings stay."
    static let clearedNotice = "Browsing data cleared."

    static let makersAddress = "https://zincoo.com/"

    static func version(in bundle: Bundle = .main) -> String {
        let marketing = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (marketing, build) {
        case let (marketing?, build?): return "Version \(marketing) (\(build))"
        case let (marketing?, nil): return "Version \(marketing)"
        default: return ""
        }
    }
}

/// Settings, over the page: what opens at start-up, how big pages are, the
/// search engine, the privacy switches, clearing, and who made it. Opened from
/// the page menu.
///
/// Left out on purpose: being the default browser (iOS grants that through an
/// entitlement Limeghost does not have yet), downloads (the phone keeps none),
/// and developer tools. Per-site exceptions to tracker blocking are left out
/// too, because nothing on the phone can make one; the Mac's list would be
/// empty here every time.
struct SettingsSheet: View {
    @ObservedObject private var dataStore: BrowserDataStore
    @ObservedObject private var searchSettings: SearchSettingsStore
    @ObservedObject private var webFeatures: WebFeatureSettingsStore
    @ObservedObject private var blocking: ContentRuleListProvider
    @ObservedObject private var blockingSettings: ContentBlockingSettingsStore
    @ObservedObject private var preferences: BrowserPreferences
    private let workspace: BrowserWorkspace
    private let dismiss: () -> Void

    @State private var isConfirmingClear = false
    @State private var isClearing = false
    @State private var hasCleared = false

    init(workspace: BrowserWorkspace, preferences: BrowserPreferences = .shared, dismiss: @escaping () -> Void) {
        self.dataStore = workspace.dataStore
        self.searchSettings = workspace.searchSettings
        self.webFeatures = workspace.webFeatures
        self.blocking = workspace.contentBlocking
        self.blockingSettings = workspace.contentBlocking.settings
        self.preferences = preferences
        self.workspace = workspace
        self.dismiss = dismiss
    }

    private var model: SettingsModel { SettingsModel(workspace: workspace, preferences: preferences) }

    var body: some View {
        NavigationStack {
            List {
                general
                search
                privacy
                trackers
                clearing
                about
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss)
                }
            }
            .confirmationDialog(
                SettingsWording.clearTitle,
                isPresented: $isConfirmingClear,
                titleVisibility: .visible
            ) {
                Button(SettingsWording.clearLabel, role: .destructive, action: clear)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(SettingsWording.clearMessage)
            }
        }
        .limeghostListSheet()
    }

    // MARK: - Sections

    @ViewBuilder
    private var general: some View {
        Section {
            Picker("On Start-up", selection: binding(\.startup)) {
                ForEach(SettingsModel.startupChoices) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .listRowBackground(LimeghostTheme.bg2)
        } header: {
            Text("General")
        } footer: {
            Text(SettingsWording.startupExplanation(dataStore.startupBehaviour))
        }
        Section {
            Picker("Text Size", selection: binding(\.pageZoom)) {
                ForEach(BrowserSession.pageZoomSteps, id: \.self) { Text(SettingsWording.percent($0)).tag($0) }
            }
            .pickerStyle(.menu)
            .listRowBackground(LimeghostTheme.bg2)
        } footer: {
            Text(SettingsWording.textSizeFooter)
        }
    }

    private var search: some View {
        Section {
            Picker("Search Engine", selection: binding(\.searchEngine)) {
                ForEach(SearchEngine.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)
            .listRowBackground(LimeghostTheme.bg2)
        } header: {
            Text("Search")
        } footer: {
            Text(SettingsWording.searchFooter(searchSettings.selectedEngine))
        }
    }

    @ViewBuilder
    private var privacy: some View {
        Section {
            Toggle("Save History", isOn: binding(\.savesHistory))
                .listRowBackground(LimeghostTheme.bg2)
        } header: {
            Text("Privacy")
        } footer: {
            Text(SettingsWording.historyFooter)
        }
        Section {
            Toggle("Upgrade to HTTPS", isOn: binding(\.upgradesToHTTPS))
                .listRowBackground(LimeghostTheme.bg2)
        } footer: {
            Text(SettingsWording.httpsFooter)
        }
        Section {
            NavigationLink("Website Data") {
                SiteDataScreen()
            }
            .listRowBackground(LimeghostTheme.bg2)
        } footer: {
            Text(SettingsWording.siteDataFooter)
        }
    }

    private var trackers: some View {
        Section {
            Toggle(
                "Block Trackers",
                isOn: Binding(
                    get: { blockingSettings.isEnabled },
                    set: { value in Task { await model.setBlocksTrackers(value) } }
                )
            )
            .listRowBackground(LimeghostTheme.bg2)
            if case .unavailable(let reason) = blocking.status {
                Label("Blocking is unavailable: \(reason)", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .listRowBackground(LimeghostTheme.bg2)
            }
        } header: {
            Text("Tracker Blocking")
        } footer: {
            Text(SettingsWording.blockingFooter)
        }
    }

    private var clearing: some View {
        Section {
            Button(role: .destructive) {
                isConfirmingClear = true
            } label: {
                HStack {
                    Text(SettingsWording.clearLabel + "\u{2026}")
                    Spacer()
                    if isClearing { ProgressView() }
                }
            }
            .disabled(isClearing)
            .listRowBackground(LimeghostTheme.bg2)
        } footer: {
            Text(hasCleared ? SettingsWording.clearedNotice + " " + SettingsWording.clearFooter : SettingsWording.clearFooter)
        }
    }

    private var about: some View {
        Section {
            HStack(spacing: 12) {
                BrandMark(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Limeghost")
                        .font(.headline)
                        .foregroundStyle(LimeghostTheme.textPrimary)
                    Text("by Zincoo")
                        .font(.subheadline)
                        .foregroundStyle(LimeghostTheme.textSecondary)
                }
                Spacer()
                Text(SettingsWording.version())
                    .font(.footnote)
                    .foregroundStyle(LimeghostTheme.textTertiary)
            }
            .padding(.vertical, 4)
            .listRowBackground(LimeghostTheme.bg2)
            .accessibilityElement(children: .combine)
            Button("zincoo.com") {
                model.openMakersSite()
                dismiss()
            }
            .listRowBackground(LimeghostTheme.bg2)
        } header: {
            Text("About")
        }
    }

    // MARK: - Actions

    private func clear() {
        isClearing = true
        hasCleared = false
        Task {
            await model.clearBrowsingData()
            isClearing = false
            hasCleared = true
        }
    }

    /// A two-way binding through the model, so the view and a test change a
    /// setting the same way.
    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<SettingsModel, Value>) -> Binding<Value> {
        let model = model
        return Binding(get: { model[keyPath: keyPath] }, set: { model[keyPath: keyPath] = $0 })
    }
}

/// Every site holding data in the phone's WebKit store, each removable on its
/// own, beside Clear Browsing Data rather than instead of it.
///
/// Kinds of data, never an amount: WebKit reports no size and no count, so
/// none is shown, as on the Mac. The store is the default one because that is
/// what the phone's ordinary tabs use (`WorkspaceHost.live` passes no other),
/// and a private tab's store is never listed: it goes with the tab.
struct SiteDataScreen: View {
    @StateObject private var inventory = SiteDataInventory()
    @State private var pendingRemoval: SiteDataEntry?

    var body: some View {
        List {
            if !inventory.sites.isEmpty {
                Section {
                    ForEach(inventory.sites) { site in
                        row(site)
                    }
                } footer: {
                    Text(SettingsWording.siteDataFooter)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .overlay {
            switch inventory.state {
            case .idle, .loading:
                ProgressView("Reading stored site data\u{2026}")
            case .loaded:
                if inventory.sites.isEmpty {
                    ContentUnavailableView(
                        "No Website Data",
                        systemImage: "externaldrive",
                        description: Text("No site has stored anything on this iPhone.")
                    )
                }
            }
        }
        .navigationTitle("Website Data")
        .navigationBarTitleDisplayMode(.inline)
        .task { await inventory.refresh() }
        .confirmationDialog(
            "Remove data stored by \(pendingRemoval?.displayName ?? "this site")?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { site in
            Button("Remove Site Data", role: .destructive) {
                pendingRemoval = nil
                Task { await inventory.remove(site) }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { site in
            Text("This removes \(site.displayName)\u{2019}s cookies, cached files and other stored data from this iPhone. You will probably be signed out of it. Your bookmarks and history are kept. This cannot be undone.")
        }
    }

    private func row(_ site: SiteDataEntry) -> some View {
        HStack(spacing: 12) {
            SiteIconView(urlString: "https://\(site.displayName)")
            VStack(alignment: .leading, spacing: 2) {
                Text(site.displayName)
                    .foregroundStyle(LimeghostTheme.textPrimary)
                    .lineLimit(1)
                Text(site.kindSummary)
                    .font(.caption)
                    .foregroundStyle(LimeghostTheme.textTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if inventory.removingSite == site.displayName {
                ProgressView()
            }
        }
        .listRowBackground(LimeghostTheme.bg2)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingRemoval = site
            } label: {
                Label("Remove", systemImage: "trash")
            }
            .disabled(inventory.removingSite != nil)
        }
        .accessibilityHint("Swipe left to remove the data this site stored.")
    }
}
