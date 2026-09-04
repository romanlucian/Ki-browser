import LimeghostCore
import LimeghostShared
import SwiftUI

/// The AI guide: the first thing a person sees, every time they open a tab
/// (D6, `startSurface == .aiHome`).
///
/// `AIToolStartPage` is the Mac's own view — the design, the copy, the
/// catalog grid — added to this target unchanged rather than rewritten
/// (Task 8): it, `LimeghostTheme` and `SiteIconView` typecheck together
/// against the iOS SDK as they stand. This wrapper only supplies what that
/// view asks for and wires its two doors to the workspace every other phone
/// screen already goes through.
struct StartSurfaceScreen: View {
    let workspace: BrowserWorkspace

    var body: some View {
        AIToolStartPage(
            store: workspace.dataStore,
            // Both closures are doors: `CLAUDE.md` names an AI-guide card
            // among the ways of asking for a page, so both go through
            // `open(_:)`, which calls `makeRoomForPage()` before loading —
            // never a session load directly, which would skip it. Both
            // `tool.officialURL` and a recommendation's source URL are
            // already absolute https addresses, exactly what `open(_:)`
            // accepts, so there is no reason to reach for `navigate(_:)`
            // here — that door exists for what a person *types*.
            openTool: { tool in workspace.open(tool.officialURL.absoluteString) },
            openSource: { _, url in workspace.open(url.absoluteString) }
        )
    }
}
