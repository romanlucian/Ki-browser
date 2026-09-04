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
