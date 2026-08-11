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
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandMenu("Tabs") {
                Button("New Tab") { workspace.addTab() }
                    .keyboardShortcut("t", modifiers: [.command])
                Button("Close Current Tab") { workspace.closeSelectedTab() }
                    .keyboardShortcut("w", modifiers: [.command, .option])
                Divider()
                Button("Next Tab") { workspace.selectNextTab() }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Tab") { workspace.selectNextTab(direction: -1) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
            }
            CommandMenu("Page") {
                Button("Focus Address Bar") { workspace.requestAddressFocus() }
                    .keyboardShortcut("l", modifiers: [.command])
                Button("Toggle Bookmark") { workspace.toggleBookmarkForSelectedTab() }
                    .keyboardShortcut("d", modifiers: [.command])
                Button("Show Downloads") { workspace.downloads.isShelfVisible = true }
                    .keyboardShortcut("j", modifiers: [.command, .shift])
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
