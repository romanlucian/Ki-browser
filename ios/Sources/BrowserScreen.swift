import SwiftUI
import LimeghostShared

/// The whole browser, one screen.
struct BrowserScreen: View {
    @ObservedObject var host: WorkspaceHost
    @State private var isPresentingAddressSheet = false
    @State private var isPresentingTabSwitcher = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let tab = host.workspace.selectedTab {
                    TabSurface(tab: tab, workspace: host.workspace)
                } else {
                    Color.clear
                }
            }

            BottomBar(
                model: BottomBarModel(
                    urlString: host.workspace.selectedTab?.session.currentURLString ?? "",
                    tabCount: host.workspace.visibleTabs.count,
                    canGoBack: host.workspace.canGoBackInSelectedTab
                ),
                goBack: { host.workspace.goBackInSelectedTab() },
                openAddress: { isPresentingAddressSheet = true },
                openTabs: { isPresentingTabSwitcher = true }
            )
        }
        .sheet(isPresented: $isPresentingAddressSheet) {
            AddressSheet(workspace: host.workspace) {
                isPresentingAddressSheet = false
            }
        }
        .sheet(isPresented: $isPresentingTabSwitcher) {
            TabSwitcher(workspace: host.workspace) {
                isPresentingTabSwitcher = false
            }
        }
    }
}

/// The selected tab's own surface: the AI guide (Task 8) while the tab is on
/// its start page and hasn't been told which one to show but `.aiHome`
/// (D6's default), or the web view once a page is loading or loaded.
///
/// The shared layer also loads its own HTML start page into every fresh
/// tab's web view — `session.loadState == .startPage` is true for that page
/// too — so this branch *replaces* `WebViewHost` outright rather than
/// layering the native guide over it; showing both at once is exactly the
/// bug this gate exists to prevent.
///
/// `@ObservedObject` on `tab` *and* `session`, not only on `host` above:
/// `startSurface` is published by the tab and `loadState` by the session,
/// and a tab does not forward every session change into its own
/// `objectWillChange` (only `BrowserWorkspace` does that, and only for the
/// tab's own published properties). Reading `host.workspace.selectedTab`
/// again here without observing the session directly would leave a card tap
/// showing the guide for one extra redraw, or none at all, after
/// `open(_:)` starts the load — the same reason the Mac's own
/// `BrowserTabContent` observes both rather than relying on the workspace
/// alone.
private struct TabSurface: View {
    @ObservedObject var tab: BrowserTab
    @ObservedObject var session: BrowserSession
    let workspace: BrowserWorkspace

    init(tab: BrowserTab, workspace: BrowserWorkspace) {
        self.tab = tab
        self.session = tab.session
        self.workspace = workspace
    }

    var body: some View {
        if session.loadState == .startPage, tab.startSurface == .aiHome {
            StartSurfaceScreen(workspace: workspace)
        } else {
            WebViewHost(session: session)
                .id(session.instanceID)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}
