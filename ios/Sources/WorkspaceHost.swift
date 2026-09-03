import Combine
import SwiftUI
import LimeghostShared

/// Owns the one `BrowserWorkspace` this scene drives.
///
/// The workspace is the Mac's, unchanged. It holds the tabs and it holds every
/// door — every way a person can ask for a page. That is why the phone gets it
/// rather than a version of its own: the rule that a door uncovers the page
/// half-shipped on the Mac once, when one door stepped aside and nine did not,
/// and writing the doors a second time here is how that happens again.
@MainActor
final class WorkspaceHost: ObservableObject {
    let workspace: BrowserWorkspace

    private var cancellable: AnyCancellable?

    private init(workspace: BrowserWorkspace) {
        self.workspace = workspace
        // SwiftUI observes this object; the workspace's own changes have to
        // reach it or nothing redraws when a tab opens.
        cancellable = workspace.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    /// The app's own workspace: the standard defaults, and the saved session
    /// restored, because that is what a person expects on reopening a browser.
    static func live() -> WorkspaceHost {
        WorkspaceHost(workspace: BrowserWorkspace(
            downloads: NoDownloads(),
            pageSharing: IOSPageSharing.self,
            clipboard: IOSClipboard(),
            makeSessionPlatform: { IOSSessionPlatform() }
        ))
    }

    /// A workspace on a throwaway defaults suite that restores nothing. These
    /// tests run inside the app, so anything else would write into the
    /// simulator's real session.
    static func forTesting(defaults: UserDefaults) -> WorkspaceHost {
        WorkspaceHost(workspace: BrowserWorkspace(
            dataStore: BrowserDataStore(defaults: defaults),
            downloads: NoDownloads(),
            pageSharing: IOSPageSharing.self,
            clipboard: IOSClipboard(),
            makeSessionPlatform: { IOSSessionPlatform() },
            searchSettings: SearchSettingsStore(defaults: defaults),
            restoresSession: false
        ))
    }
}
