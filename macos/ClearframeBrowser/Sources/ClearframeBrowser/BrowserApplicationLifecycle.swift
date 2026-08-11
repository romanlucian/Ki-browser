import AppKit

extension Notification.Name {
    static let clearframeShouldFocusAddress = Notification.Name("ClearframeShouldFocusAddress")
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
        NotificationCenter.default.post(name: .clearframeShouldFocusAddress, object: nil)
    }
}

final class ClearframeApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
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
