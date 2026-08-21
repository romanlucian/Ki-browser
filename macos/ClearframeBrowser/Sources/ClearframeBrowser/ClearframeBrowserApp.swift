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
                Button("New Window") { openNewWindow() }
                    .keyboardShortcut("n", modifiers: [.command])
            }
            CommandGroup(after: .newItem) {
                Button("Close Window") {
                    NSApplication.shared.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
            }
            CommandMenu("Tabs") {
                Button("New Tab") { focusedWorkspace?.addTab() }
                    .keyboardShortcut("t", modifiers: [.command])
                Button("New Private Tab") { focusedWorkspace?.addTab(isPrivate: true) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Close Current Tab") { focusedWorkspace?.closeSelectedTab() }
                    .keyboardShortcut("w", modifiers: [.command])
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
                Button("New Tab Group") { focusedWorkspace?.createGroupForSelectedTab() }
                    .keyboardShortcut("p", modifiers: [.control, .command])
                Button("Remove Tab from Group") { focusedWorkspace?.removeSelectedTabFromGroup() }
                    .disabled(focusedWorkspace?.selectedTabGroup == nil)
            }
            CommandMenu("Page") {
                // ⌘R is the most-used key in a browser and ⌘[ / ⌘] are the
                // macOS history pair. ⇧⌘[ and ⇧⌘] already switch tabs; these
                // are separate chords and do not collide with them.
                Button("Reload Page") { focusedWorkspace?.reloadSelectedTab() }
                    .keyboardShortcut("r", modifiers: [.command])
                Button("Stop Loading") { focusedWorkspace?.stopLoadingSelectedTab() }
                    .keyboardShortcut(".", modifiers: [.command])
                    .disabled(!(focusedWorkspace?.isSelectedTabLoading ?? false))
                Button("Back") { focusedWorkspace?.goBackInSelectedTab() }
                    .keyboardShortcut("[", modifiers: [.command])
                    .disabled(!(focusedWorkspace?.canGoBackInSelectedTab ?? false))
                Button("Forward") { focusedWorkspace?.goForwardInSelectedTab() }
                    .keyboardShortcut("]", modifiers: [.command])
                    .disabled(!(focusedWorkspace?.canGoForwardInSelectedTab ?? false))
                Divider()
                Button("Focus Address Bar") { focusedWorkspace?.requestAddressFocus() }
                    .keyboardShortcut("l", modifiers: [.command])
                Button("Add or Remove Bookmark") { focusedWorkspace?.toggleBookmarkForSelectedTab() }
                    .keyboardShortcut("d", modifiers: [.command])
                Button("New Bookmark Folder…") {
                    focusedWorkspace?.requestNewBookmarkFolder()
                }
                Button("All Bookmarks…") {
                    focusedWorkspace?.requestBookmarkLibrary()
                }
                .keyboardShortcut("b", modifiers: [.command, .option])
                Button("Toggle Bookmarks Bar") {
                    focusedWorkspace?.dataStore.showsBookmarksBar.toggle()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
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
                Divider()
                Button("Zoom In") { focusedWorkspace?.zoomInSelectedTab() }
                    .keyboardShortcut("+", modifiers: [.command])
                Button("Zoom Out") { focusedWorkspace?.zoomOutSelectedTab() }
                    .keyboardShortcut("-", modifiers: [.command])
                Button("Actual Size") { focusedWorkspace?.resetZoomInSelectedTab() }
                    .keyboardShortcut("0", modifiers: [.command])
                Divider()
                Button("Print…") { focusedWorkspace?.printSelectedPage() }
                    .keyboardShortcut("p", modifiers: [.command])
                    .disabled(!(focusedWorkspace?.canPrintSelectedPage ?? false))
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

    /// Opens an empty window. Tearing a tab out opens the same scene, having
    /// left the tab in `BrowserServices` for the new window to pick up.
    @MainActor
    private func openNewWindow() {
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
        let restores = adopted == nil && services.claimSessionRestore()
        return BrowserWorkspace(services: services, restoresSession: restores, adopting: adopted)
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
