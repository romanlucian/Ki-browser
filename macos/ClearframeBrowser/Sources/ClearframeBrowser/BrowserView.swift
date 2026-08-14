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
            // No divider here: the active tab's rounded-top shape is filled
            // the same bg2 as the toolbar below it so the two visually join.
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
        .background(ClearframeTheme.bg0)
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

    private var tabCountLabel: String {
        workspace.tabs.count == 1 ? "1 TAB" : "\(workspace.tabs.count) TABS"
    }

    private var tabCountAccessibilityLabel: String {
        workspace.tabs.count == 1 ? "1 tab open" : "\(workspace.tabs.count) tabs open"
    }

    var body: some View {
        ZStack {
            // Sits behind everything below; SwiftUI routes clicks on the
            // chips/button/pill in front of it before this ever sees them.
            // Explicit fill: a representable with no intrinsic size should
            // not be left to guess the strip's bounds.
            WindowDragArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

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
                }
                .buttonStyle(GhostButtonStyle(size: 26))
                .help("New tab (⌘T)")

                Text(tabCountLabel)
                    .font(ClearframeTheme.metaFont)
                    .tracking(ClearframeTheme.metaTracking)
                    .foregroundStyle(ClearframeTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(ClearframeTheme.bg3, in: Capsule())
                    .overlay(Capsule().stroke(ClearframeTheme.hairline2))
                    .accessibilityLabel(tabCountAccessibilityLabel)
            }
            // 78pt clears the inline traffic lights that hiddenTitleBar
            // leaves floating at the top-left of the window content.
            .padding(.leading, 78)
            .padding(.trailing, 10)
        }
        .frame(height: 38)
        .background(ClearframeTheme.bg1)
    }
}

private struct TabChip: View {
    @ObservedObject var tab: BrowserTab
    @ObservedObject private var session: BrowserSession
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void
    @State private var isHovered = false

    init(tab: BrowserTab, isSelected: Bool, select: @escaping () -> Void, close: @escaping () -> Void) {
        self.tab = tab
        _session = ObservedObject(wrappedValue: tab.session)
        self.isSelected = isSelected
        self.select = select
        self.close = close
    }

    private var identityColor: Color {
        IdentityColor.color(forHost: URL(string: session.currentURLString)?.host ?? "")
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
                        Circle()
                            .fill(identityColor)
                            .frame(width: 6, height: 6)
                            .frame(width: 12)
                    }
                    Text(tab.displayTitle)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? ClearframeTheme.textPrimary : ClearframeTheme.textSecondary)
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
            .foregroundStyle(ClearframeTheme.textTertiary)
            .help("Close tab")
        }
        .padding(.leading, 9)
        .padding(.trailing, 4)
        .frame(height: 30)
        .background(
            isSelected ? ClearframeTheme.bg2 : (isHovered ? Color.white.opacity(0.05) : Color.clear),
            in: UnevenRoundedRectangle(topLeadingRadius: ClearframeTheme.radius8, topTrailingRadius: ClearframeTheme.radius8)
        )
        .onHover { isHovered = $0 }
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
                // Purple wash over the toolbar surface rather than a bare
                // translucent patch, so it reads correctly on near-black.
                .background(Color.purple.opacity(0.14))
                .background(ClearframeTheme.bg2)
            }
            if session.isLoading {
                ProgressView(value: session.estimatedProgress)
                    .progressViewStyle(.linear)
                    .tint(ClearframeTheme.accent)
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
            HStack(spacing: 10) {
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

                addressPill

                Button { voiceInput.toggle() } label: {
                    Image(systemName: voiceInput.isListening ? "waveform" : "mic")
                }
                .buttonStyle(GhostButtonStyle(tint: voiceInput.isListening ? Color.red : ClearframeTheme.textPrimary))
                .help(voiceInput.isListening ? "Stop voice input" : "Start on-device voice input")
                .accessibilityLabel(voiceInput.isListening ? "Stop voice input" : "Start voice input")
                .accessibilityHint("Voice input fills the address field but does not submit automatically.")

                Button { workspace.toggleBookmarkForSelectedTab() } label: {
                    Image(systemName: isBookmarked ? "star.fill" : "star")
                }
                .buttonStyle(GhostButtonStyle(tint: isBookmarked ? Color.orange : ClearframeTheme.textPrimary))
                .disabled(session.currentURLString.isEmpty)
                .help(isBookmarked ? "Remove bookmark" : "Bookmark this page (⌘D)")

                Button { showsLibrary.toggle() } label: {
                    Image(systemName: "books.vertical")
                }
                .buttonStyle(GhostButtonStyle())
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
                                .foregroundStyle(ClearframeTheme.onAccent)
                                .padding(3)
                                .background(ClearframeTheme.accent, in: Circle())
                                .offset(x: 3, y: -1)
                        }
                    }
                }
                .buttonStyle(GhostButtonStyle())
                .help("Show downloads")
                .accessibilityLabel("Downloads")
                .accessibilityHint("Shows downloaded files and their save locations.")
                .popover(isPresented: $downloads.isPanelPresented, arrowEdge: .top) {
                    DownloadsPopover(center: downloads)
                }

                Button { showsAssistant.toggle() } label: {
                    Image(systemName: "sparkles.rectangle.stack")
                }
                .buttonStyle(GhostButtonStyle(isActive: showsAssistant))
                .help("Show or hide the page assistant")
                .accessibilityLabel("Assistant")
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background(ClearframeTheme.bg2)

            if dataStore.showsBookmarksBar {
                // No divider: BookmarksBar supplies its own hairline bottom
                // edge, and the bg2→bg1 color change alone reads as a seam.
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
                        .foregroundStyle(voiceInput.isListening ? Color.red : ClearframeTheme.textSecondary)
                    Text(voiceInput.statusMessage)
                        .font(.caption)
                        .foregroundStyle(ClearframeTheme.textSecondary)
                        .accessibilityLabel(voiceInput.statusMessage)
                    Spacer()
                    if voiceInput.isListening {
                        Button("Stop") { voiceInput.stop() }
                            .buttonStyle(.plain)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ClearframeTheme.textPrimary)
                    } else {
                        Button("Dismiss") { voiceInput.dismissStatus() }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(ClearframeTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(ClearframeTheme.bg2)
            }
        }
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

    /// Shield + search-engine + drag handle | URL text (host emphasized when
    /// unfocused) | clear/Go/⌘L hint — one rounded pill, per the Halo design.
    private var addressPill: some View {
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
                .foregroundStyle(ClearframeTheme.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Search engine: \(searchSettings.selectedEngine.displayName). Click to change.")
            .accessibilityLabel("Search engine: \(searchSettings.selectedEngine.displayName)")

            Rectangle()
                .fill(ClearframeTheme.hairline2)
                .frame(width: 1, height: 16)

            HStack(spacing: 8) {
                PageLinkDragHandle(
                    urlString: session.currentURLString,
                    title: session.pageTitle,
                    isSecure: session.isSecure
                )
                ZStack(alignment: .leading) {
                    TextField("Search \(searchSettings.selectedEngine.displayName) or enter a website", text: $addressText)
                        .textFieldStyle(.plain)
                        .focused(addressFocused)
                        .frame(maxWidth: .infinity)
                        .onSubmit { submitAddress() }
                        .foregroundStyle(ClearframeTheme.textPrimary)
                        // D11: the field stays mounted and keeps receiving
                        // focus/typed input at all times; emphasis only
                        // hides its text by opacity, never its identity.
                        .opacity(showsHostEmphasis ? 0 : 1)

                    if showsHostEmphasis, let hostEmphasisText {
                        hostEmphasisText
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .allowsHitTesting(false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if !addressText.isEmpty {
                    Button { addressText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(ClearframeTheme.textTertiary)
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

            Button { submitAddress() } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(ClearframeTheme.textSecondary)
            .help("Go")

            if !addressFocused.wrappedValue {
                Text("⌘L")
                    .font(ClearframeTheme.metaFont)
                    .tracking(ClearframeTheme.metaTracking)
                    .foregroundStyle(ClearframeTheme.textTertiary)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(ClearframeTheme.bg3, in: RoundedRectangle(cornerRadius: ClearframeTheme.radius6))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(ClearframeTheme.bg1, in: RoundedRectangle(cornerRadius: ClearframeTheme.radius10))
        .overlay(
            RoundedRectangle(cornerRadius: ClearframeTheme.radius10)
                .stroke(addressFocused.wrappedValue ? ClearframeTheme.accent : ClearframeTheme.hairline2, lineWidth: 1)
        )
    }

    private var showsHostEmphasis: Bool {
        !addressFocused.wrappedValue && hostEmphasisText != nil
    }

    /// Splits the address into scheme/path (textTertiary) and host
    /// (textPrimary, semibold) so the host reads as the trustworthy part of
    /// the address when the field isn't focused. Returns `nil` for anything
    /// that isn't a parseable URL with a host, which simply leaves the plain
    /// field visible instead.
    private var hostEmphasisText: Text? {
        guard !addressText.isEmpty,
              let url = URL(string: addressText),
              let host = url.host, !host.isEmpty,
              let hostRange = addressText.range(of: host) else { return nil }
        let prefix = String(addressText[addressText.startIndex..<hostRange.lowerBound])
        let suffix = String(addressText[hostRange.upperBound...])
        return Text(prefix).foregroundStyle(ClearframeTheme.textTertiary)
            + Text(host).foregroundStyle(ClearframeTheme.textPrimary).fontWeight(.semibold)
            + Text(suffix).foregroundStyle(ClearframeTheme.textTertiary)
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
                .font(.system(size: 13, weight: .medium))
        }
        .buttonStyle(GhostButtonStyle(tint: enabled ? ClearframeTheme.textPrimary : ClearframeTheme.textTertiary))
        .disabled(!enabled)
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
