import SwiftUI
import LimeghostShared

/// Limeghost on iPhone.
///
/// The browser's rules — tabs, the doors that uncover a page, the assistant's
/// layout, extraction — live in `LimeghostShared` and are the same code the Mac
/// runs. This target supplies only what a phone must supply itself: the screen,
/// the touch surfaces, and the handful of things `BrowserSessionPlatform` asks
/// the operating system for.
@main
struct LimeghostApp: App {
    var body: some Scene {
        WindowGroup {
            Text(verbatim: "Limeghost")
        }
    }
}
