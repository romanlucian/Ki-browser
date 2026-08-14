import AppKit
import ClearframeCore
import SwiftUI

struct AISettingsView: View {
    @EnvironmentObject private var configuration: AIConfigurationStore
    @EnvironmentObject private var workspace: BrowserWorkspace
    @EnvironmentObject private var onboarding: OnboardingController
    @AppStorage("clearframe.restoreTabs") private var restoresTabs = true
    @AppStorage("clearframe.saveHistory") private var savesHistory = true
    @State private var showsResetConfirmation = false
    @State private var isResettingBrowserData = false
    @State private var browserDataStatus = ""

    var body: some View {
        Form {
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

            Section("Browser privacy") {
                Toggle("Restore open tabs when Clearframe starts", isOn: $restoresTabs)
                Text("When enabled, Clearframe stores only each open tab’s current URL and title in this Mac user profile. Page contents and assistant results are not restored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Save browsing history on this Mac", isOn: $savesHistory)
                Text("History stays in this Mac user profile, is never included in AI requests, and can be cleared from the Library.")
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
                     : "Clears tabs, history, bookmarks, the in-app download list, cookies, caches, local website storage, and recovery backups. Saved files, search choice, onboarding state, and the Optional AI key are kept.")
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

            Section("Production boundary") {
                Text("Direct user-key access is only for this personal prototype. A public product must use an authenticated, metered backend, redact sensitive data, publish retention controls, and keep page agents read-only until a separate security review.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .onChange(of: restoresTabs) { _, enabled in
            if !enabled {
                workspace.dataStore.clearSavedWorkspace()
            }
        }
        .onChange(of: savesHistory) { _, enabled in
            if !enabled { workspace.dataStore.clearHistory() }
        }
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
