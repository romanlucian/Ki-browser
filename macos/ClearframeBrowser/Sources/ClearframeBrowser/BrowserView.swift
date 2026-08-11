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
            AIToolStartPage(
                openTool: { tool in
                    addressFocused = false
                    addressText = tool.officialURL.absoluteString
                    session.openAITool(tool)
                },
                openSource: { tool, sourceURL in
                    addressFocused = false
                    addressText = sourceURL.absoluteString
                    session.load(sourceURL, displayName: "\(tool.name) source")
                }
            )
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

            Button { downloads.togglePanel() } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: downloads.items.isEmpty ? "arrow.down.circle" : "arrow.down.circle.fill")
                        .frame(width: 28, height: 28)
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
            .help("Show downloads")
            .accessibilityLabel("Downloads")
            .accessibilityHint("Shows downloaded files and their save locations.")
            .popover(isPresented: $downloads.isPanelPresented, arrowEdge: .top) {
                DownloadsPopover(center: downloads)
            }

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

            if dataStore.showsBookmarksBar {
                Divider()
                BookmarksBar(
                    store: dataStore,
                    showsLibrary: $showsLibrary,
                    open: { workspace.open($0) }
                )
            }

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

private struct BookmarksBar: View {
    @ObservedObject var store: BrowserDataStore
    @Binding var showsLibrary: Bool
    let open: (String) -> Void

    private var rootFolders: [BookmarkFolderRecord] {
        store.bookmarkFolders(in: nil)
    }

    private var rootBookmarks: [BookmarkRecord] {
        store.bookmarks(in: nil)
    }

    private var isEmpty: Bool {
        rootFolders.isEmpty && rootBookmarks.isEmpty
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.48, blue: 0.36))
                .accessibilityHidden(true)

            if isEmpty {
                Button {
                    showsLibrary = true
                } label: {
                    HStack(spacing: 5) {
                        Text("Bookmarks bar is empty")
                            .fontWeight(.semibold)
                        Text("Save a page or create a folder")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 11))
                    .lineLimit(1)
                }
                .buttonStyle(.plain)
                .help("Open the bookmark organizer")
                .accessibilityHint("Opens the Library where you can create folders and organize saved pages.")
                Spacer(minLength: 0)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(rootFolders) { folder in
                            BookmarkFolderMenu(store: store, folder: folder, compact: true, open: open)
                        }
                        ForEach(rootBookmarks) { bookmark in
                            BookmarkBarLink(bookmark: bookmark, open: open)
                        }
                    }
                }
                .accessibilityLabel("Bookmarks bar")
            }

            Menu {
                if isEmpty {
                    Text("No bookmarks yet")
                } else {
                    ForEach(rootFolders) { folder in
                        BookmarkFolderMenu(store: store, folder: folder, compact: false, open: open)
                    }
                    if !rootFolders.isEmpty && !rootBookmarks.isEmpty {
                        Divider()
                    }
                    ForEach(rootBookmarks) { bookmark in
                        Button { open(bookmark.url) } label: {
                            Label(bookmark.title, systemImage: "bookmark")
                        }
                    }
                }
                Divider()
                Button {
                    showsLibrary = true
                } label: {
                    Label("Open Bookmark Organizer", systemImage: "books.vertical")
                }
                Button {
                    store.showsBookmarksBar = false
                } label: {
                    Label("Hide Bookmarks Bar", systemImage: "eye.slash")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "ellipsis")
                    Text("More")
                }
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 7)
                .frame(height: 24)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("All bookmarks and bar options")
            .accessibilityLabel("More bookmarks")
        }
        .padding(.horizontal, 11)
        .frame(height: 33)
        .background(Color.primary.opacity(0.018))
    }
}

private struct BookmarkBarLink: View {
    let bookmark: BookmarkRecord
    let open: (String) -> Void

    var body: some View {
        Button {
            open(bookmark.url)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "bookmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(bookmark.title)
                    .lineLimit(1)
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 180)
        .help("Open \(bookmark.title) — \(bookmark.url)")
        .accessibilityHint("Opens this bookmark in the current tab.")
    }
}

private struct BookmarkFolderMenu: View {
    @ObservedObject var store: BrowserDataStore
    let folder: BookmarkFolderRecord
    let compact: Bool
    let open: (String) -> Void

    var body: some View {
        Menu {
            BookmarkFolderMenuContents(store: store, folder: folder, open: open)
        } label: {
            HStack(spacing: 5) {
                Text(folder.emoji)
                Text(folder.title)
                    .lineLimit(1)
                if compact {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, compact ? 7 : 0)
            .frame(height: compact ? 24 : nil)
            .background(compact ? Color.primary.opacity(0.05) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
        .help("Open \(folder.title) folder")
        .accessibilityLabel("\(folder.title) bookmark folder")
    }
}

private struct BookmarkFolderMenuContents: View {
    @ObservedObject var store: BrowserDataStore
    let folder: BookmarkFolderRecord
    let open: (String) -> Void

    private var childFolders: [BookmarkFolderRecord] {
        store.bookmarkFolders(in: folder.id)
    }

    private var bookmarks: [BookmarkRecord] {
        store.bookmarks(in: folder.id)
    }

    var body: some View {
        if childFolders.isEmpty && bookmarks.isEmpty {
            Text("Empty folder")
        } else {
            ForEach(childFolders) { child in
                BookmarkFolderMenu(store: store, folder: child, compact: false, open: open)
            }
            if !childFolders.isEmpty && !bookmarks.isEmpty {
                Divider()
            }
            ForEach(bookmarks) { bookmark in
                Button { open(bookmark.url) } label: {
                    Label(bookmark.title, systemImage: "bookmark")
                }
            }
        }
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

            if section == .bookmarks {
                BookmarkOrganizerView(store: store, search: search, open: open)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
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
                if !store.history.isEmpty {
                    HStack {
                        Text("Stored only in this Mac user profile.").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear History", role: .destructive) { store.clearHistory() }.font(.caption)
                    }
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

private struct BookmarkFolderEditorRequest: Identifiable {
    let id = UUID()
    let folderID: UUID?
    let parentID: UUID?
    let title: String
    let emoji: String
}

private struct BookmarkFolderDestination: Identifiable {
    let folderID: UUID?
    let label: String
    var id: String { folderID?.uuidString ?? "unfiled" }
}

private struct BookmarkOrganizerView: View {
    @ObservedObject var store: BrowserDataStore
    let search: String
    let open: (String, Bool) -> Void
    @State private var currentFolderID: UUID?
    @State private var editorRequest: BookmarkFolderEditorRequest?
    @State private var pendingDeletion: BookmarkFolderRecord?

    private var currentFolder: BookmarkFolderRecord? {
        currentFolderID.flatMap(store.bookmarkFolder(id:))
    }

    private var visibleFolders: [BookmarkFolderRecord] {
        search.isEmpty ? store.bookmarkFolders(in: currentFolderID) : []
    }

    private var visibleBookmarks: [BookmarkRecord] {
        if search.isEmpty { return store.bookmarks(in: currentFolderID) }
        return store.bookmarks.filter {
            $0.title.localizedCaseInsensitiveContains(search) || $0.url.localizedCaseInsensitiveContains(search)
        }
    }

    private var destinations: [BookmarkFolderDestination] {
        var result = [BookmarkFolderDestination(folderID: nil, label: "Unfiled")]
        func appendChildren(of parentID: UUID?, prefix: String) {
            for folder in store.bookmarkFolders(in: parentID) {
                let path = prefix.isEmpty ? "\(folder.emoji) \(folder.title)" : "\(prefix) › \(folder.emoji) \(folder.title)"
                result.append(BookmarkFolderDestination(folderID: folder.id, label: path))
                appendChildren(of: folder.id, prefix: path)
            }
        }
        appendChildren(of: nil, prefix: "")
        return result
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if let currentFolder {
                    Button {
                        currentFolderID = currentFolder.parentID
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .help("Back to parent folder")
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(currentFolder.map { "\($0.emoji) \($0.title)" } ?? "Bookmarks")
                        .font(.callout.bold())
                    Text(search.isEmpty ? (currentFolder == nil ? "Folders and unfiled bookmarks" : "Local bookmark folder") : "Search all bookmarks")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    editorRequest = BookmarkFolderEditorRequest(
                        folderID: nil,
                        parentID: currentFolderID,
                        title: "",
                        emoji: "📁"
                    )
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityHint("Creates a subfolder inside the folder currently shown.")
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(visibleFolders) { folder in
                        BookmarkFolderRow(
                            folder: folder,
                            bookmarkCount: store.bookmarks(in: folder.id).count,
                            subfolderCount: store.bookmarkFolders(in: folder.id).count,
                            open: { currentFolderID = folder.id },
                            rename: {
                                editorRequest = BookmarkFolderEditorRequest(
                                    folderID: folder.id,
                                    parentID: folder.parentID,
                                    title: folder.title,
                                    emoji: folder.emoji
                                )
                            },
                            delete: { requestDeletion(folder) }
                        )
                    }

                    ForEach(visibleBookmarks) { bookmark in
                        BookmarkOrganizerRow(
                            bookmark: bookmark,
                            destinations: destinations,
                            open: { open(bookmark.url, false) },
                            openNewTab: { open(bookmark.url, true) },
                            move: { store.moveBookmark(bookmark, to: $0) },
                            remove: { store.removeBookmark(bookmark) }
                        )
                    }

                    if visibleFolders.isEmpty && visibleBookmarks.isEmpty {
                        ContentUnavailableView(
                            search.isEmpty ? "Nothing saved here" : "No matching bookmarks",
                            systemImage: "bookmark",
                            description: Text(search.isEmpty
                                              ? "Use the star to save a page, or create folders such as Web Design, Programming, and Shopping."
                                              : "Try a different title or website address.")
                        )
                        .frame(height: 255)
                    }
                }
            }

            HStack {
                Image(systemName: "lock")
                Text("Folders and bookmarks stay in this Mac user profile.")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $editorRequest) { request in
            BookmarkFolderEditor(request: request) { title, emoji in
                if let folderID = request.folderID {
                    store.updateBookmarkFolder(id: folderID, title: title, emoji: emoji)
                } else {
                    _ = store.createBookmarkFolder(title: title, emoji: emoji, parentID: request.parentID)
                }
                editorRequest = nil
            }
        }
        .alert(
            "Delete folder?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { folder in
            Button("Delete Folder", role: .destructive) {
                store.deleteBookmarkFolderPreservingContents(folder)
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { folder in
            Text("\(folder.emoji) \(folder.title) contains saved items. Its bookmarks and subfolders will move to the parent folder; nothing will be deleted.")
        }
    }

    private func requestDeletion(_ folder: BookmarkFolderRecord) {
        if store.bookmarkFolderContainsItems(folder) {
            pendingDeletion = folder
        } else {
            store.deleteBookmarkFolderPreservingContents(folder)
        }
    }
}

private struct BookmarkFolderRow: View {
    let folder: BookmarkFolderRecord
    let bookmarkCount: Int
    let subfolderCount: Int
    let open: () -> Void
    let rename: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button(action: open) {
                HStack(spacing: 9) {
                    Text(folder.emoji).font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(folder.title).font(.callout.weight(.semibold)).lineLimit(1)
                        Text("\(bookmarkCount) bookmarks · \(subfolderCount) folders")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(folder.title) folder, \(bookmarkCount) bookmarks, \(subfolderCount) subfolders")

            Menu {
                Button("Rename Folder", action: rename)
                Button("Delete Folder", role: .destructive, action: delete)
            } label: {
                Image(systemName: "ellipsis.circle").frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Folder actions")
        }
        .padding(9)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct BookmarkOrganizerRow: View {
    let bookmark: BookmarkRecord
    let destinations: [BookmarkFolderDestination]
    let open: () -> Void
    let openNewTab: () -> Void
    let move: (UUID?) -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(bookmark.title).font(.callout.weight(.medium)).lineLimit(1)
                    Text(bookmark.url).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                ForEach(destinations) { destination in
                    Button {
                        move(destination.folderID)
                    } label: {
                        if destination.folderID == bookmark.folderID {
                            Label(destination.label, systemImage: "checkmark")
                        } else {
                            Text(destination.label)
                        }
                    }
                }
            } label: {
                Image(systemName: "folder").frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Move bookmark")

            Button(action: openNewTab) { Image(systemName: "plus.square.on.square").frame(width: 22, height: 22) }
                .buttonStyle(.plain).help("Open in new tab")
            Button(action: remove) { Image(systemName: "trash").frame(width: 22, height: 22) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove bookmark")
        }
        .padding(8)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct BookmarkFolderEditor: View {
    let request: BookmarkFolderEditorRequest
    let save: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var emoji: String

    private let suggestedEmoji = ["📁", "🎨", "💻", "🛍️", "📚", "✈️", "💡", "❤️"]

    init(request: BookmarkFolderEditorRequest, save: @escaping (String, String) -> Void) {
        self.request = request
        self.save = save
        _title = State(initialValue: request.title)
        _emoji = State(initialValue: request.emoji)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(request.folderID == nil ? "New bookmark folder" : "Edit bookmark folder")
                .font(.title2.bold())
            TextField("Folder title", text: $title)
                .textFieldStyle(.roundedBorder)
            HStack {
                TextField("Emoji", text: $emoji)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 85)
                    .onChange(of: emoji) { _, value in
                        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.count > 1 { emoji = String(trimmed.prefix(1)) }
                    }
                Text("Choose one or enter your own")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                ForEach(suggestedEmoji, id: \.self) { suggestion in
                    Button(suggestion) { emoji = suggestion }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Use \(suggestion) folder icon")
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    save(title, emoji)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 470)
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

private struct DownloadsPopover: View {
    @ObservedObject var center: DownloadCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Downloads", systemImage: "arrow.down.circle.fill")
                    .font(.headline)
                Spacer()
                if center.items.contains(where: { !$0.status.isActive }) {
                    Button("Clear Finished") { center.clearFinished() }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                }
            }

            if center.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text(DownloadCenter.emptyStateTitle)
                        .font(.headline)
                    Text(DownloadCenter.emptyStateMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text("Clearframe asks where to save every file and does not keep permanent download history yet.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(center.items) { item in
                            DownloadItemView(item: item, center: center, detailWidth: 275)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }

            Divider()
            Button {
                center.openDownloadsFolder()
            } label: {
                Label("Open Downloads Folder", systemImage: "folder")
            }
            .buttonStyle(.plain)
            .font(.callout.weight(.medium))
        }
        .padding(16)
        .frame(width: 420)
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
                        Text(DownloadCenter.emptyStateMessage)
                            .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                    }
                    ForEach(center.items) { item in
                        DownloadItemView(item: item, center: center, detailWidth: 210)
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
    let detailWidth: CGFloat

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
            .frame(width: detailWidth, alignment: .leading)
            if item.status.isActive {
                Button("Cancel") { center.cancel(item) }.buttonStyle(.plain).font(.caption)
            } else if item.status == .finished {
                Button("Reveal") { center.reveal(item) }.buttonStyle(.plain).font(.caption)
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
