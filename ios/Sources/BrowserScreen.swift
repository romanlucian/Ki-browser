import SwiftUI
import LimeghostShared

/// The whole browser, one screen. Task 5 adds the bottom bar beneath.
struct BrowserScreen: View {
    @ObservedObject var host: WorkspaceHost

    var body: some View {
        Group {
            if let tab = host.workspace.selectedTab {
                WebViewHost(session: tab.session)
                    .id(tab.session.instanceID)
            } else {
                Color.clear
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}
