import SwiftUI
import LimeghostShared

/// The whole browser, one screen. Task 7 adds the tabs sheet beside this one.
struct BrowserScreen: View {
    @ObservedObject var host: WorkspaceHost
    @State private var isPresentingAddressSheet = false

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
                openTabs: {} // Task 7
            )
        }
        .sheet(isPresented: $isPresentingAddressSheet) {
            AddressSheet(workspace: host.workspace) {
                isPresentingAddressSheet = false
            }
        }
    }
}
