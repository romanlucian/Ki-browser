import SwiftUI
import LimeghostShared

@main
struct LimeghostApp: App {
    @StateObject private var host = WorkspaceHost.live()

    var body: some Scene {
        WindowGroup {
            BrowserScreen(host: host)
        }
    }
}
