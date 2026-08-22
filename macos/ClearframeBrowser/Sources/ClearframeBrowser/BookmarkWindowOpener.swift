import ClearframeCore
import Foundation
import SwiftUI

/// Opens saved pages in a window of their own, for the bookmark menus' "Open
/// in new window" and "Open all in new window".
///
/// The pages are left with `BrowserServices` and collected by the window as it
/// is built, because `openWindow` carries an identifier and nothing else.
@MainActor
enum BookmarkWindowOpener {
    static func open(
        _ urlStrings: [String],
        isPrivate: Bool,
        using openWindow: OpenWindowAction
    ) {
        // The same boundary as every other entry point: a saved record that is
        // not a web address does not open.
        let urls = urlStrings.compactMap { WebURLPolicy.validatedURL($0) }
        guard !urls.isEmpty else { return }
        let services = BrowserServices.shared
        services.openInNextWindow(
            urls,
            profileID: services.profiles.currentProfileID,
            isPrivate: isPrivate
        )
        openWindow(id: BrowserWindowScene.id)
    }
}
