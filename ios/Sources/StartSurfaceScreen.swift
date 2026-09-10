import LimeghostCore
import LimeghostShared
import SwiftUI

/// The AI guide: the first thing a person sees, every time they open a tab
/// (D6, `startSurface == .aiHome`).
///
/// `AIToolStartPage` is the Mac's own view — the design, the copy, the
/// catalog grid — added to this target unchanged rather than rewritten
/// (Task 8). It compiles here together with the Mac files it depends on:
/// `LimeghostTheme` and `SiteIconView` from the start, and since September
/// 10, 2026 `StartSurfaceChrome` and `BrandMark`, which the Mac's AI-home
/// repairs made it need. This wrapper only supplies what that view asks for
/// and wires its doors to the workspace every other phone screen already
/// goes through.
///
/// The doors are named methods, not inline closures. The inline closures
/// they replace were invisible to every test: emptied out, the suite stayed
/// green, so a door could have stopped opening anything without a single
/// failure. A named method is a value a test can call directly and check
/// the result of, like any other method here.
@MainActor
struct StartSurfaceScreen: View {
    let workspace: BrowserWorkspace

    var body: some View {
        AIToolStartPage(
            store: workspace.dataStore,
            openTool: openTool,
            openSource: openSource,
            openReference: openReference
        )
    }

    /// All three closures are doors: `CLAUDE.md` names an AI-guide card among
    /// the ways of asking for a page, so all three go through `open(_:)`,
    /// which calls `makeRoomForPage()` before loading — never a session load
    /// directly, which would skip it. `tool.officialURL` is already an
    /// absolute https address, exactly what `open(_:)` accepts, so there is
    /// no reason to reach for `navigate(_:)` here — that door exists for what
    /// a person *types*.
    ///
    /// Records the open first, matching the Mac's own order
    /// (`BrowserView.swift`'s `stateOverlay`, the `.aiHome` case): opening a
    /// tool is what puts it on the reader's row. The phone shipped without
    /// this line once, and the row could then never change — `shelfTools`
    /// only fills from what has been recorded, so the guide read "GOOD PLACES
    /// TO START" forever instead of "YOUR TOOLS", and pin and remove
    /// (`canManage`, gated on the same emptiness) were permanently dead.
    func openTool(_ tool: AIToolListing) {
        workspace.dataStore.recordAIToolOpen(tool.id)
        workspace.open(tool.officialURL.absoluteString)
    }

    /// The recommendation's own official source link — not the tool itself,
    /// so it does not join the shelf the way opening a tool does. Matches
    /// the Mac, which loads the source URL directly with no
    /// `recordAIToolOpen` call of its own.
    func openSource(_ tool: AIToolListing, _ url: URL) {
        workspace.open(url.absoluteString)
    }

    /// One of the field notes' references: a place that holds the live
    /// numbers the guide deliberately does not copy. Like a source link, it
    /// records nothing, because a reference is not a tool somebody chose to
    /// open. The Mac's version is the `openReference` closure in
    /// `BrowserView`, which loads the same address after making room itself.
    func openReference(_ reference: AIFieldReference) {
        workspace.open(reference.url.absoluteString)
    }
}
