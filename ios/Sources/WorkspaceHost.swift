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
    private var assistantCancellable: AnyCancellable?

    private init(workspace: BrowserWorkspace) {
        self.workspace = workspace
        // SwiftUI observes this object; the workspace's own changes have to
        // reach it or nothing redraws when a tab opens.
        cancellable = workspace.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        // The assistant's changes are not the workspace's, and the bar's
        // button has to hear them open and close it.
        assistantCancellable = workspace.aiCompanion.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        // The phone's assistant never shares the screen with the page, so a
        // door makes it leave rather than merely un-expand. Said once: unlike
        // a Mac window, this layer has no width at which it docks.
        workspace.aiCompanion.setCanShareWindow(false)
    }

    /// The app's own workspace: the standard defaults, and the saved session
    /// restored, because that is what a person expects on reopening a browser.
    /// Sign-in windows the assistant opens are shown over it, because the
    /// assistant covers the page and a tab would sit behind it.
    static func live() -> WorkspaceHost {
        WorkspaceHost(workspace: BrowserWorkspace(
            downloads: NoDownloads(),
            pageSharing: IOSPageSharing.self,
            clipboard: IOSClipboard(),
            makeSessionPlatform: { IOSSessionPlatform() },
            assistantPopups: .overAssistant
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
            restoresSession: false,
            assistantPopups: .overAssistant
        ))
    }
}
