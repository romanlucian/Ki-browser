import AppKit
import SwiftUI

/// Makes a region behave like the window's own title bar even though
/// `.windowStyle(.hiddenTitleBar)` removes it: click-drag moves the window,
/// double-click zooms it. Meant to sit behind interactive content in a
/// ZStack — SwiftUI dispatches clicks on buttons/tabs stacked above it
/// before AppKit ever reaches this view, so in practice it only ever sees
/// mouseDown events that land on genuinely empty tab-strip background.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandlingView {
        DragHandlingView()
    }

    func updateNSView(_ nsView: DragHandlingView, context: Context) {}
}

final class DragHandlingView: NSView {
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.performZoom(nil)
        } else {
            window?.performDrag(with: event)
        }
    }
}
