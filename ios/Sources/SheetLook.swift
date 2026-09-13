import SwiftUI

extension View {
    /// How Bookmarks, History and Move to… sit over the page.
    ///
    /// They draw on Limeghost's surfaces, like the page menu they open from;
    /// a white sheet opening out of the dark menu would look broken. They ask
    /// for the dark appearance, so the system's own parts match those
    /// surfaces: bars, the search field, swipe buttons, alerts and menus. The
    /// rest of the app still follows the system until the phone's look is
    /// designed (step 5).
    func limeghostListSheet() -> some View {
        tint(LimeghostTheme.accent)
            .preferredColorScheme(.dark)
            .presentationBackground(LimeghostTheme.bg1)
    }
}
