import AppKit
import ClearframeCore
import SwiftUI

struct BrowserView: View {
    @EnvironmentObject private var workspace: BrowserWorkspace
    @EnvironmentObject private var onboarding: OnboardingController
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            TabStrip(workspace: workspace)
            Divider()
            if let tab = workspace.selectedTab {
                BrowserTabContent(tab: tab, workspace: workspace)
                    .id(tab.id)
            } else {
                ContentUnavailableView("No open tab", systemImage: "rectangle.on.rectangle.slash")
            }
            if workspace.downloads.isShelfVisible {
                Divider()
                DownloadShelf(center: workspace.downloads)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { workspace.persistNow() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clearframeShouldFocusAddress)) { _ in
            if !onboarding.isPresented {
                workspace.requestAddressFocusForAppActivation()
            }
        }
        .onDisappear { workspace.persistNow() }
    }
}

private struct TabStrip: View {
    @ObservedObject var workspace: BrowserWorkspace

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(workspace.tabs) { tab in
                        TabChip(
                            tab: tab,
                            isSelected: tab.id == workspace.selectedTabID,
                            select: { workspace.selectTab(tab.id) },
                            close: { workspace.closeTab(tab.id) }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }
            Button {
                workspace.addTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New tab (⌘T)")
            .padding(.trailing, 10)
        }
        .frame(height: 39)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
    }
}

private struct TabChip: View {
    @ObservedObject var tab: BrowserTab
    @ObservedObject private var session: BrowserSession
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void

    init(tab: BrowserTab, isSelected: Bool, select: @escaping () -> Void, close: @escaping () -> Void) {
        self.tab = tab
        _session = ObservedObject(wrappedValue: tab.session)
        self.isSelected = isSelected
        self.select = select
        self.close = close
    }

    var body: some View {
        HStack(spacing: 7) {
            Button(action: select) {
                HStack(spacing: 7) {
                    if session.isLoading {
                        ProgressView().controlSize(.mini).frame(width: 12, height: 12)
                    } else {
                        Image(systemName: session.isSecure ? "lock.fill" : "globe")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(session.isSecure ? Color.green : Color.secondary)
                            .frame(width: 12)
                    }
                    Text(tab.displayTitle)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .frame(maxWidth: 145, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close tab")
        }
        .padding(.leading, 9)
        .padding(.trailing, 4)
        .frame(height: 30)
        .background(
            isSelected ? Color(nsColor: .windowBackgroundColor) : Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.primary.opacity(0.12) : Color.clear)
        )
    }
}

private struct BrowserTabContent: View {
    @ObservedObject var tab: BrowserTab
    @ObservedObject private var session: BrowserSession
    @ObservedObject private var assistant: PageAssistantModel
    @ObservedObject var workspace: BrowserWorkspace
    @State private var addressText: String
    @State private var showsAssistant = true
    @State private var showsLibrary = false
    @FocusState private var addressFocused: Bool

    init(tab: BrowserTab, workspace: BrowserWorkspace) {
        self.tab = tab
        _session = ObservedObject(wrappedValue: tab.session)
        _assistant = ObservedObject(wrappedValue: tab.assistant)
        self.workspace = workspace
        _addressText = State(initialValue: tab.session.currentURLString)
    }

    var body: some View {
        VStack(spacing: 0) {
            BrowserToolbar(
                session: session,
                workspace: workspace,
                dataStore: workspace.dataStore,
                downloads: workspace.downloads,
                searchSettings: workspace.searchSettings,
                addressText: $addressText,
                addressFocused: $addressFocused,
                showsAssistant: $showsAssistant,
                showsLibrary: $showsLibrary
            )
            if session.isLoading {
                ProgressView(value: session.estimatedProgress)
                    .progressViewStyle(.linear)
                    .tint(Color(red: 0.22, green: 0.49, blue: 0.36))
                    .frame(height: 2)
            }
            Divider()
            HStack(spacing: 0) {
                ZStack {
                    WebView(session: session)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    stateOverlay
                }
                if showsAssistant {
                    Divider()
                    AssistantPanel(model: assistant, session: session)
                        .frame(width: 380)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showsAssistant)
        .onChange(of: session.currentURLString) { _, newValue in
            if !addressFocused { addressText = newValue }
        }
        .onChange(of: session.navigationVersion) { _, _ in
            assistant.clearForNavigation()
        }
        .onChange(of: workspace.focusAddressRequest) { _, _ in
            Task { await focusAddressBar() }
        }
        .task { await focusAddressBar() }
    }

    @MainActor
    private func focusAddressBar() async {
        addressText = session.currentURLString
        addressFocused = true
        await Task.yield()
        try? await Task.sleep(nanoseconds: 60_000_000)
        guard !Task.isCancelled else { return }
        NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
    }

    @ViewBuilder
    private var stateOverlay: some View {
        switch session.loadState {
        case .startPage:
            AIToolStartPage(openTool: { tool in
                addressFocused = false
                addressText = tool.officialURL.absoluteString
                session.openAITool(tool)
            })
        case .failed(let failure):
            BrowserErrorView(
                failure: failure,
                retry: { session.retry() },
                goHome: { session.showStartPage() }
            )
        case .loading where !session.hasCommittedNavigation:
            VStack(spacing: 13) {
                ProgressView().controlSize(.large)
                Text(session.loadingTitle)
                    .font(.headline)
                if !session.loadingHost.isEmpty {
                    Text(session.loadingHost)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        case .content, .loading:
            EmptyView()
        }
    }
}

private struct BrowserToolbar: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var workspace: BrowserWorkspace
    @ObservedObject var dataStore: BrowserDataStore
    @ObservedObject var downloads: DownloadCenter
    @ObservedObject var searchSettings: SearchSettingsStore
    @Binding var addressText: String
    var addressFocused: FocusState<Bool>.Binding
    @Binding var showsAssistant: Bool
    @Binding var showsLibrary: Bool
    @StateObject private var voiceInput = VoiceInputController()
    @Environment(\.scenePhase) private var scenePhase

    private var isBookmarked: Bool {
        dataStore.isBookmarked(session.currentURLString)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
            HStack(spacing: 2) {
                NavigationButton(symbol: "chevron.left", label: "Back", enabled: session.canGoBack) { session.goBack() }
                NavigationButton(symbol: "chevron.right", label: "Forward", enabled: session.canGoForward) { session.goForward() }
                NavigationButton(symbol: "house", label: "Start page", enabled: true) { session.showStartPage() }
                NavigationButton(
                    symbol: session.isLoading ? "xmark" : "arrow.clockwise",
                    label: session.isLoading ? "Stop" : "Reload",
                    enabled: true
                ) { session.isLoading ? session.stopLoading() : session.reload() }
            }

            HStack(spacing: 8) {
                Menu {
                    ForEach(SearchEngine.allCases) { engine in
                        Button {
                            workspace.selectSearchEngine(engine)
                        } label: {
                            if engine == searchSettings.selectedEngine {
                                Label(engine.displayName, systemImage: "checkmark")
                            } else {
                                Text(engine.displayName)
                            }
                        }
                    }
                    Divider()
                    Text("Change this any time in Clearframe Settings.")
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "magnifyingglass")
                        Text(searchSettings.selectedEngine.displayName)
                            .lineLimit(1)
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Search engine: \(searchSettings.selectedEngine.displayName). Click to change.")
                .accessibilityLabel("Search engine: \(searchSettings.selectedEngine.displayName)")

                Divider()
                    .frame(height: 17)

                HStack(spacing: 8) {
                    Image(systemName: session.isSecure ? "lock.fill" : "globe")
                        .foregroundStyle(session.isSecure ? Color.green : Color.secondary)
                        .font(.system(size: 11, weight: .semibold))
                    TextField("Search \(searchSettings.selectedEngine.displayName) or enter a website", text: $addressText)
                        .textFieldStyle(.plain)
                        .focused(addressFocused)
                        .frame(maxWidth: .infinity)
                        .onSubmit { submitAddress() }
                    if !addressText.isEmpty {
                        Button { addressText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear address")
                    }
                }
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded {
                        addressFocused.wrappedValue = true
                    }
                )
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(addressFocused.wrappedValue ? Color.green.opacity(0.45) : Color.primary.opacity(0.08)))

                Button { submitAddress() } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("Go")

                Button { voiceInput.toggle() } label: {
                    Image(systemName: voiceInput.isListening ? "waveform" : "mic")
                        .foregroundStyle(voiceInput.isListening ? Color.red : Color.primary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(voiceInput.isListening ? "Stop voice input" : "Start on-device voice input")
                .accessibilityLabel(voiceInput.isListening ? "Stop voice input" : "Start voice input")
                .accessibilityHint("Voice input fills the address field but does not submit automatically.")

            Button { workspace.toggleBookmarkForSelectedTab() } label: {
                Image(systemName: isBookmarked ? "star.fill" : "star")
                    .foregroundStyle(isBookmarked ? Color.orange : Color.primary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(session.currentURLString.isEmpty)
            .help(isBookmarked ? "Remove bookmark" : "Bookmark this page (⌘D)")

            Button { showsLibrary.toggle() } label: {
                Image(systemName: "books.vertical")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Bookmarks and history")
            .popover(isPresented: $showsLibrary, arrowEdge: .top) {
                LibraryPopover(
                    store: dataStore,
                    open: { url, newTab in
                        workspace.open(url, inNewTab: newTab)
                        showsLibrary = false
                    }
                )
            }

            Button { downloads.isShelfVisible.toggle() } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "arrow.down.circle").frame(width: 28, height: 28)
                    if downloads.activeCount > 0 {
                        Text("\(downloads.activeCount)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(Color.green, in: Circle())
                            .offset(x: 3, y: -1)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Downloads")

            Button { showsAssistant.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles.rectangle.stack")
                    Text("Assistant")
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(
                    showsAssistant ? Color(red: 0.09, green: 0.31, blue: 0.24) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 9)
                )
                .foregroundStyle(showsAssistant ? Color.white : Color.primary)
            }
            .buttonStyle(.plain)
            .help("Show or hide the page assistant")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            if voiceInput.presentsStatus {
                HStack(spacing: 8) {
                    Image(systemName: voiceInput.isListening ? "mic.fill" : "info.circle")
                        .foregroundStyle(voiceInput.isListening ? Color.red : Color.secondary)
                    Text(voiceInput.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(voiceInput.statusMessage)
                    Spacer()
                    if voiceInput.isListening {
                        Button("Stop") { voiceInput.stop() }
                            .buttonStyle(.plain)
                            .font(.caption.weight(.semibold))
                    } else {
                        Button("Dismiss") { voiceInput.dismissStatus() }
                            .buttonStyle(.plain)
                            .font(.caption)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 7)
            }
        }
        .background(.bar)
        .onChange(of: voiceInput.transcript) { _, transcript in
            addressText = transcript
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { voiceInput.stop() }
        }
        .onDisappear { voiceInput.stop() }
    }

    @MainActor
    private func submitAddress() {
        let destination = addressText
        voiceInput.stop()
        voiceInput.dismissStatus()
        addressFocused.wrappedValue = false
        session.navigate(destination)
        DispatchQueue.main.async {
            session.webView.window?.makeFirstResponder(session.webView)
        }
    }
}

private struct NavigationButton: View {
    let symbol: String
    let label: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 27, height: 27)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.45))
        .help(label)
    }
}

private struct BrowserErrorView: View {
    let failure: BrowserFailure
    let retry: () -> Void
    let goHome: () -> Void

    private var symbol: String {
        switch failure.kind {
        case .offline: return "wifi.slash"
        case .timedOut: return "clock.badge.exclamationmark"
        case .cannotReachHost: return "network.slash"
        case .blocked: return "hand.raised.fill"
        case .other: return "exclamationmark.triangle"
        }
    }

    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(failure.kind == .offline ? Color.orange : Color.secondary)
            Text(failure.title)
                .font(.system(size: 28, weight: .bold, design: .serif))
            Text(failure.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            HStack {
                if failure.retryable {
                    Button("Try Again", action: retry).buttonStyle(.borderedProminent)
                }
                Button("Start Page", action: goHome).buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

private enum LibrarySection: String, CaseIterable {
    case bookmarks = "Bookmarks"
    case history = "History"
}

private struct LibraryPopover: View {
    @ObservedObject var store: BrowserDataStore
    let open: (String, Bool) -> Void
    @State private var section: LibrarySection = .bookmarks
    @State private var search = ""

    private var filteredBookmarks: [BookmarkRecord] {
        guard !search.isEmpty else { return store.bookmarks }
        return store.bookmarks.filter { $0.title.localizedCaseInsensitiveContains(search) || $0.url.localizedCaseInsensitiveContains(search) }
    }

    private var filteredHistory: [HistoryRecord] {
        guard !search.isEmpty else { return store.history }
        return store.history.filter { $0.title.localizedCaseInsensitiveContains(search) || $0.url.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker("Library", selection: $section) {
                ForEach(LibrarySection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            TextField("Search saved pages", text: $search)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVStack(spacing: 5) {
                    if section == .bookmarks {
                        if filteredBookmarks.isEmpty { libraryEmpty("No bookmarks yet", "Bookmark pages with the star button.") }
                        ForEach(filteredBookmarks) { bookmark in
                            LibraryRow(
                                title: bookmark.title,
                                url: bookmark.url,
                                detail: nil,
                                open: { open(bookmark.url, false) },
                                openNewTab: { open(bookmark.url, true) },
                                remove: { store.removeBookmark(bookmark) }
                            )
                        }
                    } else {
                        if filteredHistory.isEmpty { libraryEmpty("No local history", "Completed page visits appear here.") }
                        ForEach(filteredHistory) { item in
                            LibraryRow(
                                title: item.title,
                                url: item.url,
                                detail: item.visitedAt.formatted(date: .abbreviated, time: .shortened),
                                open: { open(item.url, false) },
                                openNewTab: { open(item.url, true) },
                                remove: { store.removeHistory(item) }
                            )
                        }
                    }
                }
            }
            if section == .history && !store.history.isEmpty {
                HStack {
                    Text("Stored only in this Mac user profile.").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear History", role: .destructive) { store.clearHistory() }.font(.caption)
                }
            }
        }
        .padding(14)
        .frame(width: 430, height: 450)
    }

    private func libraryEmpty(_ title: String, _ detail: String) -> some View {
        ContentUnavailableView(title, systemImage: "books.vertical", description: Text(detail))
            .frame(height: 270)
    }
}

private struct LibraryRow: View {
    let title: String
    let url: String
    let detail: String?
    let open: () -> Void
    let openNewTab: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.callout.weight(.medium)).lineLimit(1)
                    Text(detail ?? url).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: openNewTab) { Image(systemName: "plus.square.on.square").frame(width: 22, height: 22) }
                .buttonStyle(.plain).help("Open in new tab")
            Button(action: remove) { Image(systemName: "trash").frame(width: 22, height: 22) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove")
        }
        .padding(8)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DownloadShelf: View {
    @ObservedObject var center: DownloadCenter

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Label("Downloads", systemImage: "arrow.down.circle.fill").font(.caption.bold())
                Spacer()
                if center.items.contains(where: { !$0.status.isActive }) {
                    Button("Clear Finished") { center.clearFinished() }.buttonStyle(.plain).font(.caption)
                }
                Button { center.isShelfVisible = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("Hide downloads")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if center.items.isEmpty {
                        Text("Downloads will appear here after you choose a file destination.")
                            .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                    }
                    ForEach(center.items) { item in
                        DownloadItemView(item: item, center: center)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct DownloadItemView: View {
    let item: DownloadItem
    @ObservedObject var center: DownloadCenter

    var body: some View {
        HStack(spacing: 9) {
            if item.status.isActive {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: statusSymbol).foregroundStyle(statusColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename).font(.caption.weight(.semibold)).lineLimit(1)
                Text(item.status.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                if let destination = item.destinationURL {
                    Text(destination.deletingLastPathComponent().path).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            .frame(width: 210, alignment: .leading)
            if item.status.isActive {
                Button("Cancel") { center.cancel(item) }.buttonStyle(.plain).font(.caption)
            } else if item.status == .finished {
                Button("Show") { center.reveal(item) }.buttonStyle(.plain).font(.caption)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
    }

    private var statusSymbol: String {
        switch item.status {
        case .finished: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle"
        case .failed: return "exclamationmark.triangle.fill"
        default: return "arrow.down.circle"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .finished: return .green
        case .failed: return .red
        default: return .secondary
        }
    }
}
