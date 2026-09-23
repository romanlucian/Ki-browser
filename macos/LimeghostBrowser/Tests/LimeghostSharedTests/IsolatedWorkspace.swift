import LimeghostCore
@testable import LimeghostShared
import Foundation
import WebKit
import XCTest

/// A workspace that touches nothing outside its test: a preferences suite of
/// its own, a rule store of its own, and an icon folder of its own. The last
/// one is not tidiness — the browsing-data reset deletes the icon folder it is
/// handed, and a workspace built without one is handed the real profile's.
@MainActor
struct IsolatedWorkspace {
    let workspace: BrowserWorkspace
    let defaults: UserDefaults
    let iconDirectory: URL

    static func make(
        for testCase: XCTestCase,
        isPrivate: Bool = false,
        websiteDataStore: WKWebsiteDataStore? = nil
    ) throws -> IsolatedWorkspace {
        let suiteName = "clearframe.isolatedWorkspace.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        testCase.addTeardownBlock { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("limeghost-isolated-\(UUID().uuidString)", isDirectory: true)
        let rules = scratch.appendingPathComponent("Rules", isDirectory: true)
        let icons = scratch.appendingPathComponent("Favicons", isDirectory: true)
        try FileManager.default.createDirectory(at: rules, withIntermediateDirectories: true)
        testCase.addTeardownBlock { try? FileManager.default.removeItem(at: scratch) }

        let ruleStore = try XCTUnwrap(WKContentRuleListStore(url: rules), "no rule store at \(rules.path)")
        let blocking = ContentRuleListProvider(
            settings: ContentBlockingSettingsStore(defaults: defaults),
            blockList: TrackerBlockList(release: TrackerBlockerCatalog.release, domains: ["tracker.example"]),
            ruleStore: ruleStore
        )
        let workspace = BrowserWorkspace(
            dataStore: BrowserDataStore(defaults: defaults),
            downloads: NoDownloads(),
            pageSharing: NoPageSharing.self,
            clipboard: NoClipboard(),
            makeSessionPlatform: { RecordingPlatform() },
            searchSettings: SearchSettingsStore(defaults: defaults),
            contentBlocking: blocking,
            favicons: FaviconStore(directory: icons, fetch: { _ in nil }),
            restoresSession: false,
            isPrivate: isPrivate,
            websiteDataStore: websiteDataStore
        )
        return IsolatedWorkspace(workspace: workspace, defaults: defaults, iconDirectory: icons)
    }
}

/// Polls a main-actor condition until it holds or the time runs out.
@MainActor
func eventually(timeout: TimeInterval = 10, _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return condition()
}

/// Runs a script in a session's page and hands back what it returned.
@MainActor
func evaluate(_ script: String, in session: BrowserSession) async throws -> Any? {
    try await withCheckedThrowingContinuation { continuation in
        session.webView.evaluateJavaScript(script) { value, error in
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: value)
            }
        }
    }
}
