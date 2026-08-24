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
    /// How long each wait for a drag event lasts before the button is checked
    /// again. Short enough that a missed release is noticed immediately,
    /// long enough not to spin.
    private static let pointerPollInterval: TimeInterval = 0.05

    /// Follows the pointer until the button is released, then offers the tab to
    /// whichever window the pointer is over, so a tab torn out by mistake can
    /// be put back in the same gesture.
    static func follow(window: NSWindow, workspace: BrowserWorkspace, stripHeight: CGFloat) {
        // The gesture may already be over — a very fast flick releases before
        // the window exists — so the button is checked before waiting at all.
        guard NSEvent.pressedMouseButtons & 1 != 0 else { return }

        let startMouse = NSEvent.mouseLocation
        let startOrigin = window.frame.origin
        // Checking the button once and then waiting on `.distantFuture` was a
        // race: a release landing between the check and the first wait leaves
        // this loop waiting for a mouse-up that has already been delivered,
        // and it is a nested event loop, so nothing else in the app is
        // dispatched while it waits. The button is now re-checked on every
        // slice instead, which makes waiting forever impossible rather than
        // unlikely.
        while NSEvent.pressedMouseButtons & 1 != 0 {
            guard let event = NSApp.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp],
                until: Date().addingTimeInterval(pointerPollInterval),
                inMode: .eventTracking,
                dequeue: true
            ) else { continue } // Nothing this slice; the condition above decides whether to keep waiting.
            if event.type == .leftMouseUp { break }
            let mouse = NSEvent.mouseLocation
            window.setFrameOrigin(
                CGPoint(
                    x: startOrigin.x + (mouse.x - startMouse.x),
                    y: startOrigin.y + (mouse.y - startMouse.y)
                )
            )
        }

        reattachIfDroppedOnAStrip(window: window, workspace: workspace, stripHeight: stripHeight)
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
