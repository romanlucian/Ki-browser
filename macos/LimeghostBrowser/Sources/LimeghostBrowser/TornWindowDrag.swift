import AppKit

/// Keeps a freshly torn-off window under the pointer for the rest of the drag
/// that created it.
///
/// A tab pulled out of the strip becomes a window immediately, while the mouse
/// is still down. Chrome then hands the window to the system's own move loop so
/// it follows the cursor; AppKit has no equivalent for a window whose
/// `isMovable` is false — which ours is, so that dragging a tab never drags the
/// window — so the tracking is done here.
@MainActor
enum TornWindowDrag {
    /// How often the pointer is read while a torn-off window follows it. Fast
    /// enough to look continuous, and a release is noticed within one tick.
    private static let pointerPollInterval: TimeInterval = 1.0 / 120.0

    /// Follows the pointer until the button is released, then offers the tab to
    /// whichever window the pointer is over, so a tab torn out by mistake can
    /// be put back in the same gesture.
    ///
    /// Observes the pointer rather than consuming events, and that distinction
    /// is the whole point. This used to run a nested
    /// `NSApp.nextEvent(matching:…, dequeue: true)` loop, and `NSApp.nextEvent`
    /// takes from the *application's* queue, before anything is routed to a
    /// window. A tab is torn out mid-gesture, while the press that started it
    /// is still live in the window it came from — so that loop swallowed the
    /// drags and, fatally, the mouse-up belonging to the source window's own
    /// SwiftUI gesture. That gesture then never ended: `dragEnded` never ran,
    /// `dragToreOff` stayed true so no further tab could be torn out of that
    /// window, and its chrome stopped answering clicks while hover, the menu
    /// bar and the page itself carried on working.
    ///
    /// A timer reading `NSEvent.pressedMouseButtons` and `NSEvent.mouseLocation`
    /// consumes nothing, so every window keeps receiving its own events.
    static func follow(window: NSWindow, workspace: BrowserWorkspace, stripHeight: CGFloat) {
        // The gesture may already be over — a very fast flick releases before
        // the window exists — and then there is nothing to follow.
        guard NSEvent.pressedMouseButtons & 1 != 0 else { return }

        let startMouse = NSEvent.mouseLocation
        let startOrigin = window.frame.origin
        let timer = Timer(timeInterval: pointerPollInterval, repeats: true) { [weak window] timer in
            MainActor.assumeIsolated {
                guard let window, window.isVisible else {
                    timer.invalidate()
                    return
                }
                guard NSEvent.pressedMouseButtons & 1 != 0 else {
                    timer.invalidate()
                    reattachIfDroppedOnAStrip(window: window, workspace: workspace, stripHeight: stripHeight)
                    return
                }
                let mouse = NSEvent.mouseLocation
                window.setFrameOrigin(
                    CGPoint(
                        x: startOrigin.x + (mouse.x - startMouse.x),
                        y: startOrigin.y + (mouse.y - startMouse.y)
                    )
                )
            }
        }
        // `.common` so it keeps firing while the button is down and AppKit is
        // in a tracking mode; the default mode alone would stall exactly when
        // the window needs to move.
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Released over another window's tab strip? Then the tab goes back where
    /// it was dropped and this window closes, which is the round trip Chrome
    /// completes inside one gesture.
    private static func reattachIfDroppedOnAStrip(
        window: NSWindow,
        workspace: BrowserWorkspace,
        stripHeight: CGFloat
    ) {
        let services = BrowserServices.shared
        guard let (target, targetWindow) = services.dropTarget(
            at: NSEvent.mouseLocation,
            excluding: workspace,
            stripHeight: stripHeight
        ),
            target.profileID == workspace.profileID,
            target.isPrivate == workspace.isPrivate,
            let tab = workspace.tabs.first,
            let moved = workspace.detachTab(tab.id, evenIfLast: true)
        else { return }
        target.adopt(moved)
        targetWindow?.makeKeyAndOrderFront(nil)
        services.forgetWindow(of: workspace)
        window.performClose(nil)
    }
}
