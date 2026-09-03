import SwiftUI
import LimeghostShared

/// The whole browser, one screen. Task 5 adds the bottom bar beneath.
struct BrowserScreen: View {
    @ObservedObject var host: WorkspaceHost

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let tab = host.workspace.selectedTab {
                    WebViewHost(session: tab.session)
                        .id(tab.session.instanceID)
                        .ignoresSafeArea(edges: .bottom)
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
                openAddress: {}, // Task 6
                openTabs: {} // Task 7
            )
        }
    }
}
