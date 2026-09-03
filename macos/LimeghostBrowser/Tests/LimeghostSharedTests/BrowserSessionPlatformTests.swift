import XCTest
import WebKit
@testable import LimeghostShared

/// Records what the session asked the platform to do, so a test can assert the
/// request without a window, a panel, or a person to dismiss one.
final class RecordingPlatform: BrowserSessionPlatform {
    var openedExternally: [URL] = []
    func openExternal(_ url: URL) { openedExternally.append(url) }
    func presentAlert(message: String) async {}
    func presentConfirm(message: String) async -> Bool { false }
    func presentPrompt(message: String, defaultText: String?) async -> String? { nil }
    func chooseFiles(allowsMultiple: Bool, allowsDirectories: Bool) async -> [URL]? { nil }
    func printPage(_ webView: WKWebView) {}
    func observeAppearance(_ apply: @escaping () -> Void) -> Any? { nil }
}

/// `BrowserSession` also needs something that can take a finished download off
/// its hands. `DownloadCenter` -- the real implementation -- is AppKit-heavy
/// (a save panel, Finder, notifications) and lives in the app target, well
/// beyond this test's reach and beyond what a session itself should need to
/// know about. This is the whole of what a session actually asks for.
@MainActor
private final class NoOpDownloadTracking: DownloadTracking {
    func track(_ download: WKDownload, sourceURL: URL?) {}
}

@MainActor
private func makeTestSession(platform: BrowserSessionPlatform) -> BrowserSession {
    let suiteName = "clearframe.browserSessionPlatform.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    return BrowserSession(
        platform: platform,
        downloadCenter: NoOpDownloadTracking(),
        searchSettings: SearchSettingsStore(defaults: defaults)
    )
}

final class BrowserSessionPlatformTests: XCTestCase {
    /// A `mailto:` link is not a page. The session must hand it to the platform
    /// rather than try to load it, on a phone exactly as on a Mac.
    @MainActor
    func testASchemeTheBrowserDoesNotRenderGoesToThePlatform() throws {
        let platform = RecordingPlatform()
        let session = makeTestSession(platform: platform)

        session.openExternalScheme(URL(string: "mailto:hello@example.com")!)

        XCTAssertEqual(platform.openedExternally.map(\.scheme), ["mailto"])
    }
}
