import AppKit
import LimeghostCore
import SwiftUI

struct BrowserView: View {
    @EnvironmentObject private var workspace: BrowserWorkspace
    @EnvironmentObject private var onboarding: OnboardingController
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            TabStrip(workspace: workspace)
            // No divider here: the active tab's rounded-top shape is filled
            // the same bg1 as the toolbar below it, and its bottom edge is
            // flush with the strip, so chip and toolbar read as one surface.
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
        .background(LimeghostTheme.bg0)
        // `hiddenTitleBar` leaves a title-bar safe area behind: without this
        // the strip's background bled up into it while the chips stayed
        // below, adding an empty band above the tabs and pushing the traffic
        // lights out of the strip. Ignoring it puts the lights inline with
        // the tabs — what the 78pt leading inset in TabStrip is for.
        .ignoresSafeArea(.container, edges: .top)
        // One store for the whole window: tab chips, bookmark chips, and the
        // bookmarks home all read icons captured by the tabs' own visits.
        .environment(\.faviconStore, workspace.favicons)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { workspace.persistNow() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .limeghostShouldFocusAddress)) { _ in
            if !onboarding.isPresented {
                workspace.requestAddressFocusForAppActivation()
            }
        }
        .onDisappear { workspace.persistNow() }
    }
}

private struct BrowserTabContent: View {
    /// Wide enough for an assistant's own page without forcing its phone layout.
    static let companionWidth: CGFloat = 500
    /// Below this a page is too narrow to read beside anything.
    static let minimumReadableWidth: CGFloat = 600

    @ObservedObject var tab: BrowserTab
    @ObservedObject private var session: BrowserSession
    @ObservedObject private var find: PageFindController
    @ObservedObject var workspace: BrowserWorkspace
    @ObservedObject private var companion: AICompanion
    @State private var addressText: String
    @State private var showsLibrary = false
    @State private var addressFocused = false

    init(tab: BrowserTab, workspace: BrowserWorkspace) {
        self.tab = tab
        _session = ObservedObject(wrappedValue: tab.session)
        _find = ObservedObject(wrappedValue: tab.find)
        self.workspace = workspace
        _companion = ObservedObject(wrappedValue: workspace.aiCompanion)
        _addressText = State(initialValue: tab.session.currentURLString)
    }

    var body: some View {
        VStack(spacing: 0) {
            BrowserToolbar(
                session: session,
                workspace: workspace,
                tab: tab,
                dataStore: workspace.dataStore,
                companion: companion,
                downloads: workspace.downloads,
                searchSettings: workspace.searchSettings,
                addressText: $addressText,
                addressFocused: $addressFocused,
                showsLibrary: $showsLibrary,
                goHome: {
                    workspace.makeRoomForPage()
                    tab.goHome()
                }
            )
            // The suggestion list hangs below the toolbar's own height; without
            // this it would be painted under the web view.
            .zIndex(1)
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
                .background(LimeghostTheme.bg1)
            }
            if find.isPresented {
                FindInPageBar(find: find) {
                    session.webView.window?.makeFirstResponder(session.webView)
                }
            }
            if let notice = session.linkNotice {
                LinkNoticeBar(message: notice) { session.dismissLinkNotice() }
            }
            if let notice = session.pageNotice {
                LinkNoticeBar(message: notice, symbol: "doc.on.doc") { session.dismissPageNotice() }
            }
            if session.isLoading {
                ProgressView(value: session.estimatedProgress)
                    .progressViewStyle(.linear)
                    .tint(LimeghostTheme.accent)
                    .frame(height: 2)
            }
            Divider()
            // Two columns need room for both. Below the threshold the assistant
            // covers the page instead of squeezing it — the same answer a phone
            // would need, arrived at on a small laptop first.
            GeometryReader { geometry in
                let fitsBesidePage = geometry.size.width >= Self.companionWidth + Self.minimumReadableWidth
                // Two assistants need two readable columns and nothing else.
                let fitsTwoAssistants = geometry.size.width >= Self.companionWidth * 2
                // Expanded by choice, or with no room to share.
                let fillsWindow = companion.isExpanded || !fitsBesidePage
                // **One panel, always in the same place in this tree.** Sharing
                // the window and filling it used to be two separate
                // `AICompanionPanel`s in two branches, and expanding moved the
                // panel from one to the other — which is a destroy and rebuild,
                // not a resize. `WebView` hands SwiftUI a web view the session
                // owns rather than one it builds, so that rebuild reattached the
                // assistant that already existed and left the one created in the
                // same update with no place in the view hierarchy: pressing
                // Compare showed the second assistant's header above a blank
                // rectangle. Widening one panel keeps every web view where it is.
                ZStack(alignment: .trailing) {
                    HStack(spacing: 0) {
                        ZStack {
                            WebView(session: session)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            stateOverlay
                            // Drawn over the page rather than in place of it.
                            // `WebView` hands SwiftUI a web view the session
                            // owns, so swapping it out of this branch would
                            // destroy and rebuild it — the same mistake that
                            // once shipped Compare as a blank rectangle.
                            if let article = tab.readerArticle {
                                ReaderView(
                                    article: article,
                                    copy: { tab.copyArticleForAI(article) },
                                    close: { tab.readerArticle = nil }
                                )
                                .transition(.opacity)
                            }
                        }
                        if companion.isVisible && !fillsWindow {
                            Divider()
                            // Holds the docked panel's width so the page lays out
                            // beside it instead of underneath it.
                            Color.clear.frame(width: Self.companionWidth)
                        }
                    }
                    if companion.isVisible {
                        AICompanionPanel(companion: companion, allowsComparison: fitsTwoAssistants)
                            .frame(width: fillsWindow ? geometry.size.width : Self.companionWidth)
                            .frame(maxHeight: .infinity)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                // Only the view knows how wide this window is. The companion
                // needs it to decide whether stepping out of a page's way means
                // shrinking or leaving — and to come back when there is room.
                .onChange(of: fitsBesidePage, initial: true) { _, canShare in
                    companion.setCanShareWindow(canShare)
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: companion.isVisible)
        // A restored tab starts loading before this view exists, so the change
        // that would have filled the address field has already happened by the
        // time anything is watching for it. Reopening the browser then showed a
        // fully loaded page above an empty address bar, which reads as the tab
        // not having restored at all.
        .onAppear {
            if !addressFocused, addressText != session.currentURLString {
                addressText = session.currentURLString
            }
        }
        .onChange(of: session.currentURLString) { _, newValue in
            if !addressFocused { addressText = newValue }
        }
        .onChange(of: session.navigationVersion) { _, _ in
            // A "No results" from the page that was just replaced would be a
            // statement about a page nobody is looking at any more.
            find.resetForNavigation()
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
            // D6: one load state, two surfaces. New and restored tabs stay on
            // the AI guide; only an explicit bookmarks entry point flips this.
            switch tab.startSurface {
            case .aiHome:
                AIToolStartPage(
                    store: workspace.dataStore,
                    openTool: { tool in
                        addressFocused = false
                        addressText = tool.officialURL.absoluteString
                        // Opening a tool is what puts it on the reader's row. It is
                        // recorded here rather than inside the page so the row also
                        // learns from a tool opened out of the search results.
                        workspace.dataStore.recordAIToolOpen(tool.id)
                        workspace.makeRoomForPage()
                        session.openAITool(tool)
                    },
                    openSource: { tool, sourceURL in
                        addressFocused = false
                        addressText = sourceURL.absoluteString
                        workspace.makeRoomForPage()
                        session.load(sourceURL, displayName: "\(tool.name) source")
                    }
                )
            case .bookmarksHome:
                BookmarksHomePage(
                    store: workspace.dataStore,
                    open: { url, inNewTab in
                        addressFocused = false
                        if !inNewTab { addressText = url }
                        workspace.open(url, inNewTab: inNewTab)
                    }
                )
            case .historyHome:
                HistoryHomePage(
                    store: workspace.dataStore,
                    open: { url, inNewTab in
                        addressFocused = false
                        if !inNewTab { addressText = url }
                        workspace.open(url, inNewTab: inNewTab)
                    }
                )
            }
        case .failed(let failure):
            BrowserErrorView(
                failure: failure,
                retry: { session.retry() },
                goHome: {
                    workspace.makeRoomForPage()
                    tab.goHome()
                }
            )
            // The suggestion list hangs below the toolbar's own height; without
            // this it would be painted under the web view.
            .zIndex(1)
        // Only when the tab has nothing else to show — a new tab going
        // somewhere for the first time, or a retry after an error. Following a
        // link from a page leaves that page up, exactly as every other browser
        // does; the progress bar is what says work is happening.
        case .loading where !session.hasCommittedNavigation && !session.hasRenderedPage:
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
    /// Observed, not reached through `workspace.selectedTab`: the Reader button
    /// lights from `tab.readerArticle`, and a nested object's change does not
    /// republish the view holding its owner.
    @ObservedObject var tab: BrowserTab
    @ObservedObject var dataStore: BrowserDataStore
    @ObservedObject var companion: AICompanion
    @ObservedObject var downloads: DownloadCenter
    @ObservedObject var searchSettings: SearchSettingsStore
    @Binding var addressText: String
    @Binding var addressFocused: Bool
    @Binding var showsLibrary: Bool
    /// Home always returns this tab to the AI guide surface, never to whatever
    /// start surface it last showed (B6/D6).
    let goHome: () -> Void
    @StateObject private var voiceInput = VoiceInputController()
    @State private var folderEditorRequest: BookmarkFolderEditorRequest?
    @State private var showsBookmarkImport = false
    /// Which suggestion row is highlighted. Row zero is the best answer, so
    /// Return without touching the arrows does what the field already shows.
    @State private var suggestionSelection = 0
    /// What is in the field before completion finishes it.
    @State private var addressTypedText = ""
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
                HStack(spacing: 4) {
                    NavigationButton(symbol: "chevron.left", label: "Back", enabled: session.canGoBack) { session.goBack() }
                    NavigationButton(symbol: "chevron.right", label: "Forward", enabled: session.canGoForward) { session.goForward() }
                    NavigationButton(symbol: "house", label: "Start page", enabled: true) { goHome() }
                    NavigationButton(
                        symbol: session.isLoading ? "xmark" : "arrow.clockwise",
                        label: session.isLoading ? "Stop" : "Reload",
                        enabled: true
                    ) { session.isLoading ? session.stopLoading() : session.reload() }
                }

                addressPill

                HStack(spacing: 4) {
                    Button { workspace.toggleBookmarkForSelectedTab() } label: {
                        Image(systemName: isBookmarked ? "star.fill" : "star")
                    }
                    .buttonStyle(GhostButtonStyle(tint: isBookmarked ? Color.orange : LimeghostTheme.textPrimary))
                    .disabled(session.currentURLString.isEmpty)
                    .help(isBookmarked ? "Remove bookmark" : "Bookmark this page (⌘D)")

                    Button { voiceInput.toggle() } label: {
                        Image(systemName: voiceInput.isListening ? "waveform" : "mic")
                    }
                    .buttonStyle(GhostButtonStyle(tint: voiceInput.isListening ? Color.red : LimeghostTheme.textPrimary))
                    .help(voiceInput.isListening ? "Stop voice input" : "Start on-device voice input")
                    .accessibilityLabel(voiceInput.isListening ? "Stop voice input" : "Start voice input")
                    .accessibilityHint("Voice input fills the address field but does not submit automatically.")

                    Button { showsLibrary.toggle() } label: {
                        Image(systemName: "books.vertical")
                    }
                    .buttonStyle(GhostButtonStyle())
                    .help("Bookmarks")
                    .popover(isPresented: $showsLibrary, arrowEdge: .top) {
                        BookmarkPopover(
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
                                    .foregroundStyle(LimeghostTheme.onAccent)
                                    .padding(3)
                                    .background(LimeghostTheme.accent, in: Circle())
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

                    // The AI workflow, ringed so it reads as one thing rather
                    // than two more icons in a row of seven. The assistant and
                    // the page it would be given belong together; bookmarks,
                    // voice, library and downloads do not.
                    //
                    // Ringed here rather than moved into the assistant panel's
                    // own header, which was the other idea: that header says
                    // "ChatGPT" and carries ChatGPT's mark, so a Copy button
                    // inside it reads as "send this to ChatGPT" — the one thing
                    // Limeghost must never do. The clipboard is a deliberate
                    // gap between this app and a provider, and hiding it inside
                    // the provider's frame would advertise an action that does
                    // not exist.
                    HStack(spacing: 2) {
                        Button { companion.toggle() } label: {
                            Image(systemName: "bubble.left.and.text.bubble.right")
                        }
                        .buttonStyle(GhostButtonStyle(isActive: companion.isVisible))
                        .keyboardShortcut("a", modifiers: [.command, .shift])
                        .help("Show or hide your AI beside the page (⇧⌘A)")
                        .accessibilityLabel("Assistant")

                        Button { Task { await toggleReader() } } label: {
                            Image(systemName: "doc.plaintext")
                        }
                        .buttonStyle(GhostButtonStyle(isActive: tab.readerArticle != nil))
                        .keyboardShortcut("r", modifiers: [.command, .shift])
                        .help("Read this page as Limeghost extracts it — the same text an AI would get (⇧⌘R)")
                        .accessibilityLabel("Reader")
                        .disabled(!session.loadState.showsLoadedPage)
                    }
                    .padding(2)
                    .overlay(
                        RoundedRectangle(cornerRadius: LimeghostTheme.radius10)
                            .stroke(LimeghostTheme.groupOutline, lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(LimeghostTheme.bg1)
            .zIndex(1)

            if dataStore.showsBookmarksBar {
                // No divider: the bar continues the toolbar's own bg1 plane
                // and closes it with a single hairline along its bottom edge.
                BookmarksBar(
                    store: dataStore,
                    currentPageURL: session.currentURLString,
                    currentBookmark: currentBookmark,
                    open: { workspace.open($0) },
                    addCurrentPage: { workspace.addSelectedPageBookmark(to: $0) },
                    fileDroppedURL: { workspace.fileBookmarkFromDrop($0, to: $1) },
                    newFolder: { presentFolderEditor(parentID: $0) },
                    openAllBookmarks: { workspace.openBookmarksHome() },
                    openInNewTab: { workspace.open($0, inNewTab: true) }
                )
            }

            if voiceInput.presentsStatus {
                HStack(spacing: 8) {
                    Image(systemName: voiceInput.isListening ? "mic.fill" : "info.circle")
                        .foregroundStyle(voiceInput.isListening ? Color.red : LimeghostTheme.textSecondary)
                    Text(voiceInput.statusMessage)
                        .font(.caption)
                        .foregroundStyle(LimeghostTheme.textSecondary)
                        .accessibilityLabel(voiceInput.statusMessage)
                    Spacer()
                    if voiceInput.isListening {
                        Button("Stop") { voiceInput.stop() }
                            .buttonStyle(.plain)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LimeghostTheme.textPrimary)
                    } else {
                        Button("Dismiss") { voiceInput.dismissStatus() }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(LimeghostTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(LimeghostTheme.bg1)
            }
        }
        .onChange(of: voiceInput.transcript) { _, transcript in
            addressText = transcript
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { voiceInput.stop() }
        }
        // D7: a bookmark-library request now opens the full-page bookmarks
        // home (BrowserWorkspace.requestBookmarkLibrary), so the toolbar no
        // longer forces its quick popover open. The books button still owns it.
        .onChange(of: workspace.bookmarkFolderRequestID) { _, _ in
            presentFolderEditor(parentID: workspace.requestedBookmarkFolderParentID)
        }
        .sheet(item: $folderEditorRequest) { request in
            BookmarkFolderEditor(request: request) { title, iconID, colorID in
                _ = dataStore.createBookmarkFolder(
                    title: title,
                    iconID: iconID,
                    colorID: colorID,
                    parentID: request.parentID
                )
                folderEditorRequest = nil
            }
        }
        .onChange(of: workspace.bookmarkImportRequestID) { _, _ in
            showsBookmarkImport = true
        }
        .sheet(isPresented: $showsBookmarkImport) {
            BookmarkImportSheet(store: dataStore) { didImport in
                showsBookmarkImport = false
                // The person may have been looking at any page when they
                // chose Import Bookmarks from the menu — this is what lets
                // them see the result instead of being told about it. A
                // plain Cancel never navigates them away from what they were
                // reading.
                if didImport { workspace.openBookmarksHome() }
            }
        }
        .onDisappear { voiceInput.stop() }
    }

    /// Shield + search-engine + drag handle | URL text (host emphasized when
    /// unfocused) | clear/Go/⌘L hint — one rounded pill, per the Halo design.
    /// Puts the page's readable text on the clipboard, headed by where it came
    /// from. Nothing is sent anywhere: this is the person's own clipboard, and
    /// what happens next is their own paste.
    ///
    /// Reader is a toggle, and closing it costs nothing to reopen — the page is
    /// still loaded underneath, and reading it again is one extraction.
    private func toggleReader() async {
        guard tab.readerArticle == nil else {
            tab.readerArticle = nil
            return
        }
        tab.readerArticle = await tab.readCurrentPage(verb: "read")
    }

    private var addressPill: some View {
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
                Text("Change this any time in Limeghost Settings.")
            } label: {
                // Compacted to the engine name alone: in the pill it is a
                // quiet label for what Enter will do, not a second control
                // competing with the site chip and the address itself.
                Text(searchSettings.selectedEngine.displayName)
                    .lineLimit(1)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LimeghostTheme.textTertiary)
                    .contentShape(Rectangle())
            }
            // `.borderlessButton` would flatten this label into a control
            // title, taking its colour and weight with it.
            .buttonStyle(.plain)
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Search engine: \(searchSettings.selectedEngine.displayName). Click to change.")
            .accessibilityLabel("Search engine: \(searchSettings.selectedEngine.displayName)")

            pillDivider

            // Outside the tap-to-focus block on purpose: the chip is now its own
            // control, so clicking it opens site information instead of putting
            // the cursor in the address field.
            SiteInformationChip(session: session, contentBlocking: workspace.contentBlocking)

            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    AddressField(
                        text: $addressText,
                        typedText: $addressTypedText,
                        isFocused: $addressFocused,
                        placeholder: "Search \(searchSettings.selectedEngine.displayName) or enter a website",
                        completion: addressCompletion,
                        onSubmit: submitAddress,
                        onMoveSelection: moveSuggestionSelection
                    )
                    .frame(maxWidth: .infinity)
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
                        Image(systemName: "xmark.circle.fill").foregroundStyle(LimeghostTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear address")
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    addressFocused = true
                }
            )

            Button { submitAddress() } label: {
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(LimeghostTheme.textSecondary)
            .help("Go")

            if !addressFocused {
                Text("⌘L")
                    .font(LimeghostTheme.metaFont)
                    .tracking(LimeghostTheme.metaTracking)
                    .foregroundStyle(LimeghostTheme.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(LimeghostTheme.bg3, in: RoundedRectangle(cornerRadius: LimeghostTheme.radius9))
        .overlay(
            RoundedRectangle(cornerRadius: LimeghostTheme.radius9)
                .stroke(addressFocused ? LimeghostTheme.accent : LimeghostTheme.hairline2, lineWidth: 1)
        )
        // Hung off the pill so it lines up with the field it belongs to, and
        // drawn outside the toolbar's own height so it floats over the page.
        .overlay(alignment: .topLeading) {
            if showsSuggestions {
                AddressSuggestionsView(
                    suggestions: addressSuggestions,
                    selection: suggestionSelection,
                    typed: addressText,
                    engineName: searchSettings.selectedEngine.displayName,
                    open: open(_:)
                )
                .offset(y: 36)
                .transition(.opacity)
            }
        }
        .onChange(of: addressText) { _, _ in suggestionSelection = 0 }
        .onChange(of: addressFocused) { _, focused in
            if !focused {
                suggestionSelection = 0
                addressTypedText = ""
            }
        }
    }

    private var showsSuggestions: Bool {
        addressFocused && !addressSuggestions.isEmpty
    }

    /// The rows for what is in the field, from this profile alone.
    ///
    /// Only for text the reader has actually typed. Falling back to the field's
    /// contents meant that merely focusing the bar opened a list offering to
    /// search the web for the address already on screen.
    private var addressSuggestions: [AddressSuggestion] {
        guard !session.isPrivate, !addressTypedText.isEmpty else { return [] }
        return AddressCompletion.suggestions(for: addressTypedText, in: addressCandidates)
    }

    /// Arrow keys wrap, so holding one never dead-ends at an edge.
    private func moveSuggestionSelection(_ step: Int) {
        let count = addressSuggestions.count
        guard count > 0 else { return }
        suggestionSelection = ((suggestionSelection + step) % count + count) % count
    }

    /// Opens one row. A search row hands the typed text to the engine through
    /// the same resolver the field uses, so there is one path to a search.
    private func open(_ suggestion: AddressSuggestion) {
        // Cleared first: submitAddress acts on the highlighted row, and this
        // row was chosen by name rather than by that index.
        suggestionSelection = 0
        switch suggestion.kind {
        case .search:
            addressText = suggestion.title
        case .place:
            addressText = suggestion.url
        }
        submitAddress()
    }

    /// The pill's internal seams: shield | engine | address.
    private var pillDivider: some View {
        Rectangle()
            .fill(LimeghostTheme.hairline2)
            .frame(width: 1, height: 16)
    }

    private var showsHostEmphasis: Bool {
        !addressFocused && hostEmphasisText != nil
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
        return Text(prefix).foregroundStyle(LimeghostTheme.textTertiary)
            + Text(host).foregroundStyle(LimeghostTheme.textPrimary).fontWeight(.semibold)
            + Text(suffix).foregroundStyle(LimeghostTheme.textTertiary)
    }

    private func presentFolderEditor(parentID: UUID?) {
        folderEditorRequest = BookmarkFolderEditorRequest(
            folderID: nil,
            parentID: parentID,
            title: "",
            iconID: LimeghostIconCatalog.defaultIconID,
            colorID: nil
        )
    }

    @MainActor
    /// Finishes a typed address from this profile's own history and bookmarks.
    ///
    /// Nothing is suggested in a private tab. The private-tab promise is that
    /// the tab leaves no trace, and quietly reading back everywhere the reader
    /// has been would work against the spirit of it even though it writes
    /// nothing down.
    private func addressCompletion(_ typed: String) -> String? {
        guard !session.isPrivate else { return nil }
        return AddressCompletion.completion(for: typed, in: addressCandidates)
    }

    /// Genuinely rebuilt only when history or bookmarks change — the store
    /// caches it and drops the cache when either changes. This used to say so
    /// while being a computed property on a view, which rebuilt it on every
    /// body evaluation, several times per keystroke.
    private var addressCandidates: [AddressCandidate] {
        dataStore.addressCandidates
    }

    private func submitAddress() {
        // Row zero is the field's own text, so only a deliberate move down the
        // list changes where Return goes.
        if suggestionSelection > 0, suggestionSelection < addressSuggestions.count {
            let chosen = addressSuggestions[suggestionSelection]
            suggestionSelection = 0
            open(chosen)
            return
        }
        suggestionSelection = 0
        let destination = addressText
        voiceInput.stop()
        voiceInput.dismissStatus()
        addressFocused = false
        workspace.makeRoomForPage()
        session.navigate(destination)
        DispatchQueue.main.async {
            session.webView.window?.makeFirstResponder(session.webView)
        }
    }
}

/// Find in page (⌘F), under the toolbar and inside the tab it belongs to.
///
/// WebKit reports whether a match was found and nothing else — no position, no
/// total — so this bar says "No results" or says nothing at all. It never
/// invents "3 of 12".
/// States a link Limeghost declined to open, above the page rather than over
/// it. A refused link is not a failed page: whatever the reader was reading
/// stays on screen and keeps working.
private struct LinkNoticeBar: View {
    let message: String
    var symbol: String = "link.badge.plus"
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LimeghostTheme.textTertiary)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(LimeghostTheme.textSecondary)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(GhostButtonStyle())
            .help("Dismiss this notice")
            .accessibilityLabel("Dismiss this notice")
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(LimeghostTheme.bg2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LimeghostTheme.hairline1)
                .frame(height: 1)
        }
    }
}

private struct FindInPageBar: View {
    @ObservedObject var find: PageFindController
    let returnFocusToPage: () -> Void
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 9) {
            field

            if find.outcome == .noResults {
                Text("No results")
                    .font(.system(size: 11))
                    .foregroundStyle(LimeghostTheme.textSecondary)
            }

            Spacer(minLength: 8)

            Button { find.step(backwards: true) } label: {
                Image(systemName: "chevron.up").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(GhostButtonStyle())
            .disabled(find.query.isEmpty)
            .help("Find the previous match (⇧⌘G)")
            .accessibilityLabel("Find the previous match")

            Button { find.step(backwards: false) } label: {
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(GhostButtonStyle())
            .disabled(find.query.isEmpty)
            .help("Find the next match (⌘G)")
            .accessibilityLabel("Find the next match")

            Button { close() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(GhostButtonStyle())
            .help("Close find in page (Escape)")
            .accessibilityLabel("Close find in page")
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(LimeghostTheme.bg2)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LimeghostTheme.hairline1)
                .frame(height: 1)
        }
        .onAppear { fieldFocused = true }
        .onChange(of: find.focusRequest) { _, _ in fieldFocused = true }
        .onChange(of: find.query) { _, _ in find.queryChanged() }
        .onExitCommand { close() }
    }

    private var field: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LimeghostTheme.textTertiary)
            TextField("Find in page", text: $find.query)
                .textFieldStyle(.plain)
                .focused($fieldFocused)
                .foregroundStyle(LimeghostTheme.textPrimary)
                .onSubmit { find.step(backwards: false) }
        }
        .padding(.horizontal, 11)
        .frame(width: 300, height: 26)
        .background(LimeghostTheme.bg3, in: RoundedRectangle(cornerRadius: LimeghostTheme.radius9))
        .overlay(
            RoundedRectangle(cornerRadius: LimeghostTheme.radius9)
                .stroke(fieldFocused ? LimeghostTheme.accent : LimeghostTheme.hairline2, lineWidth: 1)
        )
    }

    private func close() {
        find.close()
        returnFocusToPage()
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
        .buttonStyle(GhostButtonStyle(tint: enabled ? LimeghostTheme.textPrimary : LimeghostTheme.textTertiary))
        .disabled(!enabled)
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
