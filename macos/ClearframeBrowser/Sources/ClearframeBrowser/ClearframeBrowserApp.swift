import SwiftUI

@main
struct ClearframeBrowserApp: App {
    @NSApplicationDelegateAdaptor(ClearframeApplicationDelegate.self) private var applicationDelegate
    @StateObject private var aiConfiguration = AIConfigurationStore()
    @StateObject private var workspace = BrowserWorkspace()
    @StateObject private var onboarding = OnboardingController()

    var body: some Scene {
        Window("Clearframe", id: "clearframe-browser") {
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
            // content is forced dark — Settings below stays native.
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                workspace.openExternalURL(url)
                BrowserApplicationActivation.bringBrowserToFront()
            }
        }
        .defaultSize(width: 1280, height: 820)
        // Traffic lights move inline into the tab strip (see WindowDragArea
        // in WindowChromeSupport.swift); there is no separate title bar row.
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Tabs") {
                Button("New Tab") { workspace.addTab() }
                    .keyboardShortcut("t", modifiers: [.command])
                Button("New Private Tab") { workspace.addTab(isPrivate: true) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Close Current Tab") { workspace.closeSelectedTab() }
                    .keyboardShortcut("w", modifiers: [.command])
                Divider()
                Button("Next Tab") { workspace.selectNextTab() }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Tab") { workspace.selectNextTab(direction: -1) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                Divider()
                // ⌃⌘P is the shortcut Chrome uses for the same action, so a
                // switching user's fingers already know it.
                Button("New Tab Group") { workspace.createGroupForSelectedTab() }
                    .keyboardShortcut("p", modifiers: [.control, .command])
                Button("Remove Tab from Group") { workspace.removeSelectedTabFromGroup() }
                    .disabled(workspace.selectedTabGroup == nil)
            }
            CommandMenu("Page") {
                Button("Focus Address Bar") { workspace.requestAddressFocus() }
                    .keyboardShortcut("l", modifiers: [.command])
                Button("Add or Remove Bookmark") { workspace.toggleBookmarkForSelectedTab() }
                    .keyboardShortcut("d", modifiers: [.command])
                Button("New Bookmark Folder…") {
                    workspace.requestNewBookmarkFolder()
                }
                Button("All Bookmarks…") {
                    workspace.requestBookmarkLibrary()
                }
                .keyboardShortcut("b", modifiers: [.command, .option])
                Button("Toggle Bookmarks Bar") {
                    workspace.dataStore.showsBookmarksBar.toggle()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                Button("Show Downloads") { workspace.downloads.isPanelPresented = true }
                    .keyboardShortcut("j", modifiers: [.command, .shift])
                Divider()
                // Find, zoom, and print all act on the page in front, so they
                // live with the rest of the page commands. Each one reaches the
                // selected tab only.
                Button("Find in Page") { workspace.findInSelectedTab() }
                    .keyboardShortcut("f", modifiers: [.command])
                Button("Find Next") { workspace.findNextInSelectedTab() }
                    .keyboardShortcut("g", modifiers: [.command])
                Button("Find Previous") { workspace.findPreviousInSelectedTab() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Divider()
                Button("Zoom In") { workspace.zoomInSelectedTab() }
                    .keyboardShortcut("+", modifiers: [.command])
                Button("Zoom Out") { workspace.zoomOutSelectedTab() }
                    .keyboardShortcut("-", modifiers: [.command])
                Button("Actual Size") { workspace.resetZoomInSelectedTab() }
                    .keyboardShortcut("0", modifiers: [.command])
                Divider()
                Button("Print…") { workspace.printSelectedPage() }
                    .keyboardShortcut("p", modifiers: [.command])
                    .disabled(!workspace.canPrintSelectedPage)
            }
        }

        Settings {
            AISettingsView()
                .environmentObject(aiConfiguration)
                .environmentObject(workspace)
                .environmentObject(onboarding)
                .frame(width: 560)
                .frame(minHeight: 690)
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
