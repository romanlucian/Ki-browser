import AppKit
import SwiftUI

/// Holds the window the tab strip lives in, so SwiftUI can move it.
final class BrowserWindowHolder: ObservableObject {
    weak var window: NSWindow?
}

/// Captures the strip's window and takes AppKit's own dragging away from it.
///
/// `.windowStyle(.hiddenTitleBar)` keeps `fullSizeContentView`, so the tab
/// strip sits inside the band AppKit still treats as a title bar. A press
/// anywhere in that band lands on a SwiftUI-internal container — measured:
/// `PlatformGroupContainer` inside the strip's `HostingScrollView` — and every
/// view in that chain answers `mouseDownCanMoveWindow` with the NSView default
/// of `true`. Those views belong to SwiftUI and cannot be subclassed, so AppKit
/// would start a window drag from a tab chip and run a modal event loop that
/// swallowed the gesture before SwiftUI saw it: tabs could be clicked but never
/// reordered.
///
/// Nor can an AppKit view of our own take the press back. SwiftUI's containers
/// cover the strip, so a representable stacked behind them is never the view
/// AppKit hit-tests — which is why moving the window is SwiftUI's job here
/// (`TabStrip.windowDragGesture`) rather than this view's.
struct WindowDragArea: NSViewRepresentable {
    let holder: BrowserWindowHolder
    /// Paired with the window here rather than from `onAppear`, which can run
    /// before the view has a window to report.
    let workspace: BrowserWorkspace

    func makeNSView(context: Context) -> WindowCaptureView {
        WindowCaptureView(holder: holder, workspace: workspace)
    }

    func updateNSView(_ nsView: WindowCaptureView, context: Context) {
        nsView.holder = holder
        nsView.workspace = workspace
    }
}

final class WindowCaptureView: NSView {
    var holder: BrowserWindowHolder
    var workspace: BrowserWorkspace

    init(holder: BrowserWindowHolder, workspace: BrowserWorkspace) {
        self.holder = holder
        self.workspace = workspace
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        holder.window = window
        // The single switch that stops AppKit dragging the window off a tab.
        window?.isMovable = false
        BrowserServices.shared.registerWindow(window, for: workspace)
        // A window opened around a torn-off tab appears where the pointer let
        // go of it. Only such a window finds a value here, and it is cleared
        // on read, so an ordinary new window still cascades.
        if let window, let topLeft = BrowserServices.shared.takeWindowTopLeftAwaitingWindow() {
            window.setFrameTopLeftPoint(topLeft)
        }
    }
}
