import ClearframeCore
import SwiftUI

@main
struct ClearframeBrowserApp: App {
    @NSApplicationDelegateAdaptor(ClearframeApplicationDelegate.self) private var applicationDelegate
    @StateObject private var aiConfiguration = AIConfigurationStore()
    @StateObject private var onboarding = OnboardingController()
    /// The workspace of the window in front. Every menu command acts on this
    /// one: with more than one window open, "Close Current Tab" has to mean
    /// the tab the person is looking at.
    @FocusedValue(\.browserWorkspace) private var focusedWorkspace
    @Environment(\.openWindow) private var openWindow
    /// The History and Bookmarks menus list what is actually saved.
    private var dataStore: BrowserDataStore { BrowserServices.shared.dataStore }
    /// The Profiles menu lists what exists and ticks the window in front, so
    /// it has to be rebuilt when either changes.
    @ObservedObject private var profiles = BrowserServices.shared.profiles

    var body: some Scene {
        WindowGroup("Clearframe", id: Self.browserWindowID) {
            BrowserWindow(aiConfiguration: aiConfiguration, onboarding: onboarding)
        }
        .defaultSize(width: 1280, height: 820)
        // Traffic lights move inline into the tab strip (see WindowDragArea
        // in WindowChromeSupport.swift); there is no separate title bar row.
        .windowStyle(.hiddenTitleBar)
        .commands {
            // ⌘W closes a tab here, as it does in every browser, so the
            // window-list group that would also claim it is dropped. AppKit
            // still lists the open windows at the foot of the Window menu, and
            // Close Window below takes ⇧⌘W, which is Chrome's chord for it.
            CommandGroup(replacing: .singleWindowList) {}
            CommandGroup(replacing: .newItem) {
                Button("New Tab") { focusedWorkspace?.addTab() }
                    .keyboardShortcut("t", modifiers: [.command])
                Button("New Window") { openNewWindow() }
                    .keyboardShortcut("n", modifiers: [.command])
                // A window rather than a tab, which is what both Safari and
                // Chrome mean by this chord. Everything opened in it is
                // private, so there is no way to mix the two by accident.
                Button("New Private Window") { openNewPrivateWindow() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("New Empty Tab Group") { focusedWorkspace?.createEmptyGroup() }
                    .keyboardShortcut("n", modifiers: [.control, .command])
            }
            CommandGroup(after: .newItem) {
                // Each of these puts a standard macOS panel in front of the
                // person before anything happens; none of them can be reached
                // by a page.
                Button("Open File…") {
                    guard let file = PageFileCommands.chooseFileToOpen() else { return }
                    focusedWorkspace?.openLocalFile(file)
                }
                .keyboardShortcut("o", modifiers: [.command])
                // Its standard name, and the menu both browsers keep it in.
                Button("Open Location…") { focusedWorkspace?.requestAddressFocus() }
                    .keyboardShortcut("l", modifiers: [.command])
                Divider()
                Button("Close Window") {
                    NSApplication.shared.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                Button("Close All Windows") {
                    for window in NSApplication.shared.windows where window.isVisible {
                        window.performClose(nil)
                    }
                }
                .keyboardShortcut("w", modifiers: [.command, .option, .shift])
                Button("Close Tab") { focusedWorkspace?.closeSelectedTab() }
                    .keyboardShortcut("w", modifiers: [.command])
                Divider()
                Button("Save Page As…") { focusedWorkspace?.saveSelectedPage() }
                    .keyboardShortcut("s", modifiers: [.command])
                    .disabled(!(focusedWorkspace?.canSaveSelectedPage ?? false))
                Button("Export as PDF…") { focusedWorkspace?.exportSelectedPageAsPDF() }
                    .disabled(!(focusedWorkspace?.canSaveSelectedPage ?? false))
                Button("Share Page…") { focusedWorkspace?.shareSelectedPage() }
                    .disabled(!(focusedWorkspace?.canShareSelectedPage ?? false))
                Divider()
                Button("Print…") { focusedWorkspace?.printSelectedPage() }
                    .keyboardShortcut("p", modifiers: [.command])
                    .disabled(!(focusedWorkspace?.canPrintSelectedPage ?? false))
            }
            // Reload, stop, and zoom change what the page looks like rather
            // than where it is, and on a Mac that is the View menu — which
            // until now held nothing but Enter Full Screen.
            CommandGroup(before: .toolbar) {
                Button("Reload Page") { focusedWorkspace?.reloadSelectedTab() }
                    .keyboardShortcut("r", modifiers: [.command])
                Button("Stop Loading") { focusedWorkspace?.stopLoadingSelectedTab() }
                    .keyboardShortcut(".", modifiers: [.command])
                    .disabled(!(focusedWorkspace?.isSelectedTabLoading ?? false))
                Divider()
                Button("Zoom In") { focusedWorkspace?.zoomInSelectedTab() }
                    .keyboardShortcut("+", modifiers: [.command])
                Button("Zoom Out") { focusedWorkspace?.zoomOutSelectedTab() }
                    .keyboardShortcut("-", modifiers: [.command])
                Button("Actual Size") { focusedWorkspace?.resetZoomInSelectedTab() }
                    .keyboardShortcut("0", modifiers: [.command])
                Divider()
            }
            CommandMenu("Tabs") {
                Button("New Private Tab") { focusedWorkspace?.addTab(isPrivate: true) }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                    .disabled(focusedWorkspace?.isPrivate ?? true)
                Button("Reopen Closed Tab") { focusedWorkspace?.reopenClosedTab() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                    .disabled(!(focusedWorkspace?.canReopenClosedTab ?? false))
                Button("Duplicate Tab") { focusedWorkspace?.duplicateSelectedTab() }
                Divider()
                Button("Next Tab") { focusedWorkspace?.selectNextTab() }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Tab") { focusedWorkspace?.selectNextTab(direction: -1) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                // ⌘1-⌘8 pick that tab and ⌘9 picks the last one, matching
                // Safari rather than counting to nine.
                ForEach(1...9, id: \.self) { ordinal in
                    Button(ordinal == 9 ? "Last Tab" : "Tab \(ordinal)") {
                        focusedWorkspace?.selectTab(atOrdinal: ordinal)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(ordinal)")), modifiers: [.command])
                }
                Divider()
                // ⌃⌘P is the shortcut Chrome uses for the same action, so a
                // switching user's fingers already know it.
                Button("New Tab Group with This Tab") { focusedWorkspace?.createGroupForSelectedTab() }
                    .keyboardShortcut("p", modifiers: [.control, .command])
                Button("Remove Tab from Group") { focusedWorkspace?.removeSelectedTabFromGroup() }
                    .disabled(focusedWorkspace?.selectedTabGroup == nil)
            }
            // The two menus every Mac browser has and Clearframe did not.
            // Both read what is already saved; neither adds a second store.
            CommandMenu("History") {
                Button("Back") { focusedWorkspace?.goBackInSelectedTab() }
                    .keyboardShortcut("[", modifiers: [.command])
                    .disabled(!(focusedWorkspace?.canGoBackInSelectedTab ?? false))
                Button("Forward") { focusedWorkspace?.goForwardInSelectedTab() }
                    .keyboardShortcut("]", modifiers: [.command])
                    .disabled(!(focusedWorkspace?.canGoForwardInSelectedTab ?? false))
                Divider()
                Button("Reopen Closed Tab") { focusedWorkspace?.reopenClosedTab() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                    .disabled(!(focusedWorkspace?.canReopenClosedTab ?? false))
                Divider()
                if dataStore.history.isEmpty {
                    Text("No pages visited yet")
                } else {
                    // A menu is for the handful of pages someone might want
                    // back; the full list lives on the bookmarks home, which
                    // can search it.
                    ForEach(Self.recentPages(in: dataStore.history)) { entry in
                        Button(BookmarkMenuTitle.short(entry.title)) {
                            guard let url = WebURLPolicy.validatedURL(entry.url) else { return }
                            focusedWorkspace?.addTab(url: url)
                        }
                    }
                }
                Divider()
                Button("Show Full History…") { focusedWorkspace?.requestBookmarkLibrary() }
            }
            CommandMenu("Bookmarks") {
                Button("Add Bookmark") { focusedWorkspace?.toggleBookmarkForSelectedTab() }
                    .keyboardShortcut("d", modifiers: [.command])
                Button("New Bookmark Folder…") { focusedWorkspace?.requestNewBookmarkFolder() }
                Divider()
                Button("Show All Bookmarks") { focusedWorkspace?.requestBookmarkLibrary() }
                    .keyboardShortcut("b", modifiers: [.command, .option])
                Button("Toggle Bookmarks Bar") { dataStore.showsBookmarksBar.toggle() }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                Divider()
                let folders = dataStore.bookmarkFolders(in: nil)
                let unfiled = dataStore.bookmarks(in: nil)
                if folders.isEmpty && unfiled.isEmpty {
                    Text("No bookmarks yet")
                } else {
                    ForEach(folders) { folder in
                        Menu {
                            BookmarkMenuContents(
                                store: dataStore,
                                parentID: folder.id,
                                open: { focusedWorkspace?.addTab(url: $0) },
                                favicons: BrowserServices.shared.favicons
                            )
                        } label: {
                            Label(BookmarkMenuTitle.short(folder.title), systemImage: "folder")
                        }
                    }
                    ForEach(unfiled) { bookmark in
                        Button {
                            guard let url = WebURLPolicy.validatedURL(bookmark.url) else { return }
                            focusedWorkspace?.addTab(url: url)
                        } label: {
                            BookmarkMenuRow(
                                title: BookmarkMenuTitle.short(bookmark.title),
                                url: bookmark.url,
                                store: BrowserServices.shared.favicons
                            )
                        }
                    }
                }
            }
            // Choosing a profile opens a window in it rather than swapping the
            // one in front: a window's pages are bound to their profile's
            // cookies, and changing that underneath them would mean tearing
            // every one of them down.
            CommandMenu("Profiles") {
                ForEach(profiles.profiles) { profile in
                    Button(Self.profileMenuTitle(profile, focused: focusedWorkspace?.profileID)) {
                        openWindow(inProfile: profile.id)
                    }
                }
                Divider()
                Button("New Profile…") { addProfile() }
                Button("Rename This Profile…") { renameFocusedProfile() }
                    .disabled(focusedWorkspace == nil)
                Button("Delete This Profile…") { deleteFocusedProfile() }
                    .disabled(!(focusedWorkspace.map { profiles.canDelete($0.profileID) } ?? false))
            }
            CommandMenu("Page") {
                // ⌘R is the most-used key in a browser and ⌘[ / ⌘] are the
                // macOS history pair. ⇧⌘[ and ⇧⌘] already switch tabs; these
                // are separate chords and do not collide with them.
                Button("Show Downloads") { focusedWorkspace?.downloads.isPanelPresented = true }
                    .keyboardShortcut("j", modifiers: [.command, .shift])
                Divider()
                // Find, zoom, and print all act on the page in front, so they
                // live with the rest of the page commands. Each one reaches the
                // selected tab only.
                Button("Find in Page") { focusedWorkspace?.findInSelectedTab() }
                    .keyboardShortcut("f", modifiers: [.command])
                Button("Find Next") { focusedWorkspace?.findNextInSelectedTab() }
                    .keyboardShortcut("g", modifiers: [.command])
                Button("Find Previous") { focusedWorkspace?.findPreviousInSelectedTab() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
            }
        }

        Settings {
            AISettingsView()
                .environmentObject(aiConfiguration)
                .environmentObject(onboarding)
                .frame(width: 560)
                .frame(minHeight: 690)
        }
    }

    static let browserWindowID = "clearframe-browser"

    /// The recently visited pages worth offering, one entry per page. History
    /// records every visit, so without this the menu shows the same title
    /// several times over and holds far fewer than twelve actual pages.
    static func recentPages(in history: [HistoryRecord], limit: Int = 12) -> [HistoryRecord] {
        var seen = Set<String>()
        var result: [HistoryRecord] = []
        for entry in history where seen.insert(entry.url).inserted {
            result.append(entry)
            if result.count == limit { break }
        }
        return result
    }

    /// Opens an empty window. Tearing a tab out opens the same scene, having
    /// left the tab in `BrowserServices` for the new window to pick up.
    @MainActor
    private func openNewWindow() {
        openWindow(id: Self.browserWindowID)
    }

    /// A tick beside the profile the window in front belongs to, the way
    /// Chrome marks the one in use.
    static func profileMenuTitle(_ profile: BrowserProfileRecord, focused: UUID?) -> String {
        profile.id == focused ? "✓ \(profile.name)" : "    \(profile.name)"
    }

    @MainActor
    private func openWindow(inProfile profileID: UUID) {
        let services = BrowserServices.shared
        services.profiles.setCurrent(profileID)
        services.markNextWindow(profileID: profileID)
        openWindow(id: Self.browserWindowID)
    }

    @MainActor
    private func addProfile() {
        guard let name = ProfilePrompts.askForName(
            title: "New profile",
            message: "A profile keeps its own bookmarks, history, site icons and signed-in sessions. Nothing is shared with your other profiles except downloads and your search choice.",
            initial: ""
        ) else { return }
        let created = BrowserServices.shared.profiles.addProfile(name: name)
        openWindow(inProfile: created.id)
    }

    @MainActor
    private func renameFocusedProfile() {
        guard let profileID = focusedWorkspace?.profileID,
              let current = profiles.profile(profileID),
              let name = ProfilePrompts.askForName(
                  title: "Rename profile",
                  message: "This changes the name only. Its bookmarks, history and signed-in sessions stay as they are.",
                  initial: current.name
              )
        else { return }
        profiles.rename(profileID, to: name)
    }

    @MainActor
    private func deleteFocusedProfile() {
        guard let profileID = focusedWorkspace?.profileID,
              let profile = profiles.profile(profileID),
              profiles.canDelete(profileID),
              ProfilePrompts.confirmDeletion(of: profile.name)
        else { return }
        BrowserServices.shared.discardServices(for: profileID)
        profiles.deleteProfile(profileID)
        NSApplication.shared.keyWindow?.performClose(nil)
    }

    /// A window whose every tab is private. The flag is left for the scene to
    /// pick up, the same way a torn-off tab is.
    @MainActor
    private func openNewPrivateWindow() {
        BrowserServices.shared.markNextWindowPrivate()
        openWindow(id: Self.browserWindowID)
    }
}

/// One browser window: its own tabs, its own selection, its own address bar,
/// sharing bookmarks, history, downloads and site icons with every other.
private struct BrowserWindow: View {
    @ObservedObject var aiConfiguration: AIConfigurationStore
    @ObservedObject var onboarding: OnboardingController
    @StateObject private var workspace: BrowserWorkspace

    init(aiConfiguration: AIConfigurationStore, onboarding: OnboardingController) {
        self.aiConfiguration = aiConfiguration
        self.onboarding = onboarding
        // Deliberately inside the autoclosure: this runs once, when the window
        // is created. Taking the handed-over tab from `init` itself would
        // consume it again on every re-render of the scene.
        _workspace = StateObject(wrappedValue: BrowserWindow.makeWorkspace())
    }

    private static func makeWorkspace() -> BrowserWorkspace {
        let services = BrowserServices.shared
        let adopted = services.takeTabAwaitingWindow()
        // A window opened around a torn-off tab shows that tab, so it must not
        // also restore the session; otherwise the first window's tabs appear
        // in it too.
        let isPrivate = services.takeNextWindowIsPrivate()
        let profileID = services.takeNextWindowProfileID()
        // Only the first window of the profile that owns the saved session
        // restores it.
        let restores = !isPrivate
            && adopted == nil
            && profileID == services.profiles.currentProfileID
            && services.claimSessionRestore()
        let workspace = BrowserWorkspace(
            services: services,
            restoresSession: restores,
            adopting: isPrivate ? nil : adopted,
            isPrivate: isPrivate,
            profileID: profileID
        )
        // Opened to show something — one bookmark, or a folder's worth. The
        // blank tab a new window starts with is replaced rather than left
        // sitting in front of them.
        let pages = services.takeURLsAwaitingWindow()
        if !pages.isEmpty {
            let blank = workspace.tabs.first
            pages.forEach { workspace.addTab(url: $0) }
            if let blank, workspace.tabs.count > pages.count { workspace.closeTab(blank.id) }
        }
        return workspace
    }

    var body: some View {
        ZStack {
            BrowserView()
                .allowsHitTesting(!onboarding.isPresented)
                .accessibilityHidden(onboarding.isPresented)
            if onboarding.isPresented {
                OnboardingView(
                    controller: onboarding,
                    searchSettings: workspace.searchSettings,
                    finish: finishOnboarding
                )
                .zIndex(2)
            }
        }
        .environmentObject(aiConfiguration)
        .environmentObject(workspace)
        .environmentObject(onboarding)
        .frame(minWidth: 920, minHeight: 620)
        .animation(.easeInOut(duration: 0.22), value: onboarding.isPresented)
        // Halo chrome is near-black by design; only the browser window
        // content is forced dark — Settings stays native.
        .preferredColorScheme(.dark)
        // What makes the menu commands act on this window when it is in front.
        .focusedSceneValue(\.browserWorkspace, workspace)
        .onOpenURL { url in
            workspace.openExternalURL(url)
            BrowserApplicationActivation.bringBrowserToFront()
        }
    }

    @MainActor
    private func finishOnboarding() {
        let shouldOpenHome = onboarding.isInitialPresentation
        onboarding.complete()
        if shouldOpenHome {
            workspace.selectedTab?.session.showStartPage()
        }
        workspace.requestAddressFocus()
    }
}

private struct BrowserWorkspaceFocusKey: FocusedValueKey {
    typealias Value = BrowserWorkspace
}

extension FocusedValues {
    var browserWorkspace: BrowserWorkspace? {
        get { self[BrowserWorkspaceFocusKey.self] }
        set { self[BrowserWorkspaceFocusKey.self] = newValue }
    }
}
