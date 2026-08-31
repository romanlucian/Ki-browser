import AppKit

extension Notification.Name {
    static let limeghostShouldFocusAddress = Notification.Name("LimeghostShouldFocusAddress")
}

@MainActor
enum BrowserApplicationActivation {
    static func bringBrowserToFront() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeKey }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    static func requestSensibleAddressFocus() {
        NotificationCenter.default.post(name: .limeghostShouldFocusAddress, object: nil)
    }
}

final class LimeghostApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Limeghost draws its own tab strip. AppKit's window tabbing would
        // add a second, native one — along with Show Tab Bar and Show All Tabs
        // in the View menu, which act on tabs Limeghost does not have.
        NSWindow.allowsAutomaticWindowTabbing = false
        Task { @MainActor in
            BrowserApplicationActivation.bringBrowserToFront()
            try? await Task.sleep(nanoseconds: 120_000_000)
            BrowserApplicationActivation.bringBrowserToFront()
            BrowserApplicationActivation.requestSensibleAddressFocus()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in
            await Task.yield()
            BrowserApplicationActivation.requestSensibleAddressFocus()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in
            BrowserApplicationActivation.bringBrowserToFront()
            await Task.yield()
            BrowserApplicationActivation.requestSensibleAddressFocus()
        }
        return true
    }
}
