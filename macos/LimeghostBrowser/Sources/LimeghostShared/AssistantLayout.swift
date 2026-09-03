import CoreGraphics

/// How much room the window has, and what that means for the assistant.
///
/// These two numbers used to live on the macOS `BrowserTabContent` view, where
/// an iOS view could not read them and a test could not assert them without
/// standing up SwiftUI. They are the same numbers; only their address changed.
///
/// **One rule serves every screen.** A phone is not a special case — it is a
/// window that never reaches `minimumBesidePage`, so the assistant always fills
/// it, which is what "stepping aside means leaving, not shrinking" already says
/// on a narrow Mac window.
public enum AssistantLayout {
    /// Wide enough for an assistant's own page without forcing its phone layout.
    /// Below the ~640-point breakpoint where providers show their own sidebar,
    /// which suits a side panel. The per-provider breakpoints have never been
    /// measured; do not defend this number as evidenced.
    public static let companionWidth: CGFloat = 500

    /// Below this a page is too narrow to read beside anything.
    public static let minimumReadableWidth: CGFloat = 600

    /// The width at which an assistant and a readable page both fit.
    public static var minimumBesidePage: CGFloat { companionWidth + minimumReadableWidth }

    /// Two readable columns and nothing else.
    public static var minimumForTwoAssistants: CGFloat { companionWidth * 2 }

    /// Can the assistant sit beside the page in a window this wide?
    public static func fitsBesidePage(width: CGFloat) -> Bool {
        width >= minimumBesidePage
    }

    /// Can two assistants sit side by side in a window this wide?
    public static func fitsTwoAssistants(width: CGFloat) -> Bool {
        width >= minimumForTwoAssistants
    }
}
