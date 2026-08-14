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
                    } else if tab.isPrivate {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.purple)
                            .frame(width: 12)
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
            if tab.isPrivate {
                HStack(spacing: 7) {
                    Image(systemName: "eye.slash.fill")
                    Text("Private tab · history, cookies, and this tab are not saved after it closes")
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.purple)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 25, alignment: .leading)
                .background(Color.purple.opacity(0.08))
            }
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
        .task {
            if session.shouldFocusAddressOnAppActivation {
                await focusAddressBar()
            }
        }
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
    @State private var folderEditorRequest: BookmarkFolderEditorRequest?
    @Environment(\.scenePhase) private var scenePhase

    private var isBookmarked: Bool {
        dataStore.isBookmarked(session.currentURLString)
    }

    private var currentBookmark: BookmarkRecord? {
        dataStore.bookmark(for: session.currentURLString)
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
                ContentBlockingShieldButton(provider: workspace.contentBlocking, session: session)

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
                    PageLinkDragHandle(
                        urlString: session.currentURLString,
                        title: session.pageTitle,
                        isSecure: session.isSecure
                    )
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
                    currentPageURL: session.currentURLString,
                    currentBookmark: currentBookmark,
                    open: { workspace.open($0) },
                    addCurrentPage: { workspace.addSelectedPageBookmark(to: $0) },
                    fileDroppedURL: { workspace.fileBookmarkFromDrop($0, to: $1) },
                    newFolder: { presentFolderEditor(parentID: $0) }
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
        .onChange(of: workspace.bookmarkLibraryRequest) { _, _ in
            showsLibrary = true
        }
        .onChange(of: workspace.bookmarkFolderRequestID) { _, _ in
            presentFolderEditor(parentID: workspace.requestedBookmarkFolderParentID)
        }
        .sheet(item: $folderEditorRequest) { request in
            BookmarkFolderEditor(request: request) { title, emoji in
                _ = dataStore.createBookmarkFolder(
                    title: title,
                    emoji: emoji,
                    parentID: request.parentID
                )
                folderEditorRequest = nil
            }
        }
        .onDisappear { voiceInput.stop() }
    }

    private func presentFolderEditor(parentID: UUID?) {
        folderEditorRequest = BookmarkFolderEditorRequest(
            folderID: nil,
            parentID: parentID,
            title: "",
            emoji: "📁"
        )
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

private struct PageLinkDragHandle: View {
    let urlString: String
    let title: String
    let isSecure: Bool

    @ViewBuilder
    var body: some View {
        if let url = BookmarkURLPolicy.validatedURL(urlString) {
            symbol
                .frame(width: 20, height: 22)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 5))
                .contentShape(RoundedRectangle(cornerRadius: 5))
                .draggable(url) {
                    Label(title.isEmpty ? (url.host ?? "Web page") : title, systemImage: "link")
                        .lineLimit(1)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                .help("Drag this page link to the bookmarks bar or a visible folder")
                .accessibilityLabel("Page link drag handle")
                .accessibilityHint("Drag to the bookmarks bar to save this page, or onto a folder to file it there.")
        } else {
            symbol
                .frame(width: 20, height: 22)
                .accessibilityHidden(true)
        }
    }

    private var symbol: some View {
        Image(systemName: isSecure ? "lock.fill" : "globe")
            .foregroundStyle(isSecure ? Color.green : Color.secondary)
            .font(.system(size: 11, weight: .semibold))
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
