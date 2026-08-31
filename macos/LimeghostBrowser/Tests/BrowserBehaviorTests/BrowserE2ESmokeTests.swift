import AppKit
import LimeghostCore
import Foundation
import SwiftUI
import XCTest
@preconcurrency import WebKit
@testable import LimeghostBrowser

private enum SmokeFailure: LocalizedError {
    case check(String)

    var errorDescription: String? {
        switch self {
        case .check(let message): return message
        }
    }
}

@MainActor
private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw SmokeFailure.check(message) }
}

private func requireValue<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else { throw SmokeFailure.check(message) }
    return value
}

@MainActor
private func waitUntil(
    timeout: TimeInterval = 8,
    condition: @escaping @MainActor () -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
    return condition()
}

@MainActor
private func evaluate(_ script: String, in session: BrowserSession) async throws {
    _ = try await evaluateValue(script, in: session)
}

@MainActor
private func evaluateValue(_ script: String, in session: BrowserSession) async throws -> Any {
    try await withCheckedThrowingContinuation { continuation in
        session.webView.evaluateJavaScript(script) { value, error in
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: value as Any)
            }
        }
    } as Any
}

@MainActor
private func loadDeterministicPage(
    in session: BrowserSession,
    localURL: URL,
    expectedTitle: String = "Limeghost Local Verification"
) async throws {
    session.navigate(localURL.absoluteString)
    let loaded = await waitUntil(condition: {
        session.loadState == .content && session.pageTitle == expectedTitle
    })
    try require(loaded, "deterministic page did not render from the verified local fixture server")
}

private func configuredFixtureURL() throws -> URL {
    guard let value = ProcessInfo.processInfo.environment["LIMEGHOST_SMOKE_BASE_URL"],
          let url = WebURLPolicy.validatedURL(value) else {
        throw SmokeFailure.check("LIMEGHOST_SMOKE_BASE_URL was not supplied by the smoke harness")
    }
    return url
}

private func reflectedNavigationOriginURL(_ session: BrowserSession) -> URL? {
    guard let stored = Mirror(reflecting: session).children.first(where: { $0.label == "navigationOriginURL" })?.value else {
        return nil
    }
    if let url = stored as? URL { return url }
    return Mirror(reflecting: stored).children.first?.value as? URL
}

private func reflectedRequestedURL(_ session: BrowserSession) -> URL? {
    guard let stored = Mirror(reflecting: session).children.first(where: { $0.label == "lastRequestedURL" })?.value else {
        return nil
    }
    if let url = stored as? URL { return url }
    return Mirror(reflecting: stored).children.first?.value as? URL
}

private func searchQuery(in url: URL?, named queryName: String = "q") -> String? {
    guard let url else { return nil }
    return URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?
        .first(where: { $0.name == queryName })?
        .value
}

/// The end-to-end smoke pass: one real window, one real `WKWebView`, real
/// pages served over HTTP by `scripts/fixture-server.py`. This is the only
/// place extraction, content blocking, focus, popups and navigation races run
/// against live WebKit rather than constructed state.
///
/// It lives inside the ordinary test target so that **every `swift test`
/// compiles it**. Its predecessor was compiled only by a hand-listed `swiftc`
/// invocation in `run-browser-smoke.sh`, and that list rotted silently twice in
/// nine days — commits could edit this very file and ship it uncompilable,
/// because nothing built it but the script nobody ran.
///
/// The live checks still need what CI does not have: a logged-in desktop
/// session for window focus, and the fixture server for pages. So everything
/// past the first guard runs only when `LIMEGHOST_SMOKE_BASE_URL` is set,
/// which `scripts/run-browser-smoke.sh` does after starting the server. On CI
/// and in a bare `swift test`, this compiles, skips, and stays honest.
final class BrowserE2ESmokeTests: XCTestCase {
    @MainActor
    func testBrowserEndToEndAgainstTheLocalFixtureServer() async throws {
        guard ProcessInfo.processInfo.environment["LIMEGHOST_SMOKE_BASE_URL"] != nil else {
            throw XCTSkip(
                "Live smoke checks need a desktop session and the fixture server; "
                    + "run scripts/run-browser-smoke.sh, which provides both."
            )
        }
        let suiteName = "clearframe.browser.e2e.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("could not create isolated defaults")
            return
        }
        defer { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }

        do {
            let application = NSApplication.shared
            application.finishLaunching()

            let onboardingPreferences = OnboardingPreferences(defaults: defaults)
            let onboarding = OnboardingController(preferences: onboardingPreferences)
            try require(onboarding.isPresented && onboarding.isInitialPresentation && onboarding.step == .welcome, "first run did not present the welcome step")
            onboarding.advance()
            try require(onboarding.step == .searchAndPrivacy, "onboarding did not advance to search and privacy")
            onboarding.advance()
            try require(onboarding.step == .analyzePages, "onboarding did not advance to Analyze page guidance")
            onboarding.complete()
            try require(!onboarding.isPresented && onboardingPreferences.hasCompletedIntroduction, "onboarding completion did not persist locally")
            onboarding.revisit()
            try require(onboarding.isPresented && !onboarding.isInitialPresentation && onboarding.step == .welcome, "Settings revisit did not reopen at the welcome step")
            onboarding.complete()
            print("PASS onboarding: first-run steps, local completion, and Settings revisit state succeeded")

            let dataStore = BrowserDataStore(defaults: defaults)
            let searchSettings = SearchSettingsStore(defaults: defaults)
            let workspace = BrowserWorkspace(
                dataStore: dataStore,
                downloads: DownloadCenter(),
                searchSettings: searchSettings
            )
            try require(dataStore.showsBookmarksBar, "bookmarks bar was not visibly enabled by default")
            dataStore.showsBookmarksBar = false
            try require(!BrowserDataStore(defaults: defaults).showsBookmarksBar, "hidden bookmarks-bar preference did not persist locally")
            dataStore.showsBookmarksBar = true
            try require(BrowserDataStore(defaults: defaults).showsBookmarksBar, "visible bookmarks-bar preference did not persist locally")
            print("PASS bookmarks bar preference: visible by default and show/hide choice persisted locally")
            try require(workspace.downloads.items.isEmpty, "new download center was not empty")
            try require(!workspace.downloads.isPanelPresented, "downloads panel started open")
            workspace.downloads.togglePanel()
            try require(workspace.downloads.isPanelPresented, "downloads control did not present the panel")
            try require(DownloadCenter.emptyStateTitle == "No downloads yet", "downloads empty state was unclear")
            try require(workspace.downloads.downloadsDirectory?.lastPathComponent == "Downloads", "downloads folder destination was unavailable")
            try require(
                BrowserSession.isDownloadTransitionError(NSError(domain: "WebKitErrorDomain", code: 102)),
                "expected WebKit download transition was not recognized"
            )
            try require(
                !BrowserSession.isDownloadTransitionError(NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)),
                "ordinary navigation failures were incorrectly hidden as downloads"
            )
            workspace.downloads.togglePanel()
            try require(!workspace.downloads.isPanelPresented, "downloads control did not dismiss the panel")
            print("PASS downloads: toolbar state, clear empty presentation, Downloads-folder destination, and policy-transition handling succeeded")
            let rootView = BrowserView()
                .environmentObject(workspace)
                .environmentObject(onboarding)
            let window = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 1_180, height: 760),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Limeghost E2E Verification"
            window.contentView = NSHostingView(rootView: rootView)
            window.makeKeyAndOrderFront(nil)
            BrowserApplicationActivation.bringBrowserToFront()
            let windowActivated = await waitUntil {
                window.isVisible
            }
            try require(windowActivated, "native SwiftUI browser window did not become visible")
            let addressFocusedAtLaunch = await waitUntil {
                window.firstResponder is NSTextView
            }
            try require(addressFocusedAtLaunch, "address field did not receive keyboard focus at launch")
            print("PASS window/focus: native SwiftUI window is visible and the address field owns keyboard focus")

            guard let session = workspace.selectedTab?.session else {
                throw SmokeFailure.check("initial browser tab was not created")
            }

            let focusRequestBeforeTab = workspace.focusAddressRequest
            workspace.addTab()
            try require(workspace.tabs.count == 2, "workspace did not create a second tab")
            try require(workspace.focusAddressRequest == focusRequestBeforeTab, "tab selection issued an unnecessary global address-focus request")
            workspace.closeSelectedTab()
            try require(workspace.tabs.count == 1, "workspace did not close the selected tab")
            let addressRefocused = await waitUntil { window.firstResponder is NSTextView }
            try require(addressRefocused, "address field did not regain focus after the tab change")
            print("PASS tab controls: a new start tab focused its address without a tab-wide focus request")

            try require(window.makeFirstResponder(session.webView), "web content could not take focus before provider selection")
            let focusRequestBeforeProvider = workspace.focusAddressRequest
            workspace.selectSearchEngine(.google)
            try require(workspace.focusAddressRequest > focusRequestBeforeProvider, "provider selection did not request address focus")
            let providerAddressFocused = await waitUntil { window.firstResponder is NSTextView }
            try require(providerAddressFocused, "address field did not receive focus after provider selection")
            guard let addressEditor = window.firstResponder as? NSTextView else {
                throw SmokeFailure.check("focused address editor was unavailable")
            }
            addressEditor.insertText("Lucian Roman", replacementRange: addressEditor.selectedRange())
            try require(addressEditor.string == "Lucian Roman", "focused address field did not accept representative keyboard text")
            print("PASS provider/input focus: choosing Google refocused the address field and accepted ‘Lucian Roman’")

            session.showStartPage()
            try require(window.makeFirstResponder(session.webView), "web view could not temporarily take focus on the start page")
            let focusRequestBeforeActivation = workspace.focusAddressRequest
            BrowserApplicationActivation.requestSensibleAddressFocus()
            try require(workspace.focusAddressRequest > focusRequestBeforeActivation, "start-page app activation did not request address focus")
            let addressFocusedAfterActivation = await waitUntil { window.firstResponder is NSTextView }
            try require(addressFocusedAfterActivation, "address field did not regain focus after start-page app activation")
            print("PASS activation focus: start-page reactivation restored the address keyboard target")

            session.navigate("https://example.com/focus-preservation")
            session.stopLoading()
            try require(window.makeFirstResponder(session.webView), "loaded web content could not take keyboard focus")
            let focusRequestBeforeContentActivation = workspace.focusAddressRequest
            BrowserApplicationActivation.requestSensibleAddressFocus()
            try require(workspace.focusAddressRequest == focusRequestBeforeContentActivation, "app activation tried to steal focus from loaded web content")
            try require(window.firstResponder === session.webView, "loaded web content lost keyboard focus during app activation")
            session.showStartPage()
            print("PASS content focus: reactivation did not steal keyboard focus from a loaded webpage")

            guard let seedance = AIToolCatalog.tools.first(where: { $0.id == "seedance" }) else {
                throw SmokeFailure.check("static AI tool catalog did not contain Seedance")
            }
            session.openAITool(seedance)
            try require(reflectedRequestedURL(session) == seedance.officialURL, "AI home card destination did not request its exact official URL")
            try require(session.currentURLString == seedance.officialURL.absoluteString, "AI home activation did not expose the destination in the address state immediately")
            try require(session.loadState == .loading && session.isLoading, "AI home activation did not enter visible loading state")
            try require(session.loadingTitle.contains("Seedance") && session.loadingHost == "seed.bytedance.com", "AI home activation did not expose provider-specific loading feedback")
            session.stopLoading()
            session.showStartPage()
            let videoTools = AIToolCatalog.filtered(category: .createVideos, query: "video")
            try require(videoTools.contains(where: { $0.id == "veo" }), "AI home video category did not expose Veo")
            try require(videoTools.contains(where: { $0.id == "seedance" }), "AI home video category did not expose Seedance")
            try require(AIToolCatalog.filtered(category: .research, query: "").first?.id == "perplexity", "task recommendation did not lead research ordering")
            try require(AIToolCatalog.tools.allSatisfy { AIToolAccessLabel.allCases.contains($0.access) }, "AI catalog contained a nonstandard access label")
            try require(!AIToolCatalog.release.version.isEmpty, "AI catalog release version was missing")
            try require(AIToolCatalog.release.lastChecked <= Date(), "AI catalog checked date was in the future")
            print("PASS AI home: card navigation, local filtering, task ordering, access labels, and catalog release metadata work")

            searchSettings.selectedEngine = .duckDuckGo

            session.navigate("limeghost deterministic smoke query")
            let deterministicSearchURL = reflectedRequestedURL(session)
            try require(deterministicSearchURL?.host == "duckduckgo.com", "search text did not resolve to the configured search URL")
            try require(searchQuery(in: deterministicSearchURL) == "limeghost deterministic smoke query", "search query was not preserved")
            session.stopLoading()
            session.showStartPage()
            print("PASS search resolution: plain text produced the expected DuckDuckGo request")

            searchSettings.selectedEngine = .startpage
            let restoredSearchSettings = SearchSettingsStore(defaults: defaults)
            try require(restoredSearchSettings.selectedEngine == .startpage, "search engine choice did not persist locally")
            session.navigate("limeghost alternate provider query")
            let alternateSearchURL = reflectedRequestedURL(session)
            try require(alternateSearchURL?.host == "www.startpage.com", "selected Startpage search did not use its configured host")
            try require(searchQuery(in: alternateSearchURL, named: "query") == "limeghost alternate provider query", "Startpage query was not preserved")
            session.stopLoading()
            session.showStartPage()
            print("PASS search settings: Startpage selection persisted locally and updated URL resolution")

            searchSettings.selectedEngine = .google
            let restoredGoogleSettings = SearchSettingsStore(defaults: defaults)
            try require(restoredGoogleSettings.selectedEngine == .google, "Google search selection did not persist locally")
            session.navigate("Limeghost source aware browser")
            let googleSearchURL = reflectedRequestedURL(session)
            try require(googleSearchURL?.scheme == "https", "Google search did not use HTTPS")
            try require(googleSearchURL?.host == "www.google.com", "selected Google search did not use google.com")
            try require(searchQuery(in: googleSearchURL) == "Limeghost source aware browser", "Google search query was not preserved")
            session.stopLoading()

            let directURL = URL(string: "https://example.com/direct-path?source=limeghost")!
            session.navigate(directURL.absoluteString)
            try require(reflectedRequestedURL(session) == directURL, "direct web address was incorrectly sent to the search provider")
            session.stopLoading()
            session.showStartPage()
            print("PASS Google search: selection persisted, plain text resolved to Google, and a direct URL bypassed search")

            searchSettings.selectedEngine = .duckDuckGo

            let fixtureURL = try configuredFixtureURL()
            let localURL = fixtureURL.absoluteString
            dataStore.toggleBookmark(title: "Local verification", url: localURL)
            dataStore.recordVisit(title: "Local verification", url: localURL)
            try require(dataStore.bookmarks.count == 1, "bookmark control did not persist a local record")
            try require(dataStore.history.count == 1, "history control did not persist a completed visit")
            let programmingFolder = try requireValue(
                dataStore.createBookmarkFolder(title: "Programming", iconID: "terminal", parentID: nil),
                "bookmark organizer did not create a root folder"
            )
            let swiftFolder = try requireValue(
                dataStore.createBookmarkFolder(title: "Swift", iconID: "branch", parentID: programmingFolder.id),
                "bookmark organizer did not create a nested folder"
            )
            dataStore.moveBookmark(dataStore.bookmarks[0], to: swiftFolder.id)
            try require(dataStore.bookmarks(in: swiftFolder.id).count == 1, "bookmark did not move into a nested folder")
            let contextualBookmark = dataStore.addBookmark(
                title: "Context menu page",
                url: "https://example.com/context-bookmark",
                folderID: programmingFolder.id
            )
            try require(contextualBookmark?.folderID == programmingFolder.id, "folder context action did not file the current page")
            let refiledContextualBookmark = dataStore.addBookmark(
                title: "Context menu page updated",
                url: "https://example.com/context-bookmark",
                folderID: swiftFolder.id
            )
            try require(refiledContextualBookmark?.id == contextualBookmark?.id, "refiling an existing current-page bookmark changed its identity")
            try require(dataStore.bookmarks.filter { $0.url == "https://example.com/context-bookmark" }.count == 1, "refiling created a duplicate bookmark")
            try require(dataStore.bookmarks(in: swiftFolder.id).contains(where: { $0.id == contextualBookmark?.id }), "folder context action did not move the existing bookmark")
            let draggedURL = URL(string: "https://example.com/address-drag")!
            let createdFromAddressDrag = dataStore.fileBookmarkFromDrop(
                draggedURL,
                title: "Address drag verification",
                to: nil
            )
            try require(createdFromAddressDrag?.disposition == .created, "address-link drop did not create an Unfiled bookmark")
            let movedFromBarDrag = dataStore.fileBookmarkFromDrop(
                draggedURL,
                title: nil,
                to: programmingFolder.id
            )
            try require(movedFromBarDrag?.disposition == .moved, "saved bookmark drag did not move the existing record into a folder")
            try require(movedFromBarDrag?.bookmark.id == createdFromAddressDrag?.bookmark.id, "drag refiling changed bookmark identity")
            try require(dataStore.bookmarks.filter { $0.url == draggedURL.absoluteString }.count == 1, "drag refiling created a duplicate URL")
            let repeatedFolderDrop = dataStore.fileBookmarkFromDrop(
                draggedURL,
                title: nil,
                to: programmingFolder.id
            )
            try require(repeatedFolderDrop?.disposition == .alreadyFiled, "repeated folder drop did not report an existing filing")
            let loadingTitleDropURL = URL(string: "https://example.com/loading-title-drag")!
            let loadingTitleDrop = dataStore.fileBookmarkFromDrop(
                loadingTitleDropURL,
                title: "Loading…",
                to: nil
            )
            try require(loadingTitleDrop?.bookmark.title == "example.com", "address drag persisted a transient Loading title")
            if let loadingTitleBookmark = dataStore.bookmark(for: loadingTitleDropURL.absoluteString) {
                dataStore.removeBookmark(loadingTitleBookmark)
            }
            let unsafeDrag = dataStore.fileBookmarkFromDrop(
                URL(string: "file:///tmp/not-a-web-bookmark")!,
                title: "Unsafe",
                to: nil
            )
            try require(unsafeDrag == nil, "non-web drag payload was persisted as a bookmark")
            try require(dataStore.bookmarkFolders(in: nil).map(\.id) == [programmingFolder.id], "bookmarks bar root included a nested folder")
            try require(dataStore.bookmarkFolders(in: programmingFolder.id).map(\.id) == [swiftFolder.id], "bookmarks bar folder hierarchy omitted a nested submenu")
            try require(dataStore.bookmarks(in: nil).isEmpty, "bookmarks bar root showed a filed bookmark as Unfiled")
            let libraryRequest = workspace.bookmarkLibraryRequest
            workspace.requestBookmarkLibrary()
            try require(workspace.bookmarkLibraryRequest == libraryRequest + 1, "Page menu did not request the bookmark organizer")

            // Bookmarks and history are separate destinations. This also
            // happens to be the only gate that proves HistoryHomePage.swift
            // and StartSurfaceChrome.swift are in this script's hand-listed
            // file set — a UI file missing from it stops the suite compiling
            // while `swift test` stays green.
            if let surfaceTab = workspace.selectedTab {
                workspace.openBookmarksHome()
                try require(surfaceTab.startSurface == .bookmarksHome, "the bookmarks home did not open")
                workspace.openHistoryHome()
                try require(surfaceTab.startSurface == .historyHome, "the history page did not open")
                try require(surfaceTab.session.loadState == .startPage, "the history page is not a start surface")
                surfaceTab.goHome()
                try require(surfaceTab.startSurface == .aiHome, "Home did not return the tab to the AI guide")
                print("PASS surfaces: bookmarks home and history page are separate destinations")
            }
            let folderRequestID = workspace.bookmarkFolderRequestID
            workspace.requestNewBookmarkFolder(parentID: swiftFolder.id)
            try require(workspace.bookmarkFolderRequestID != folderRequestID, "Page menu did not request a folder editor")
            try require(workspace.requestedBookmarkFolderParentID == swiftFolder.id, "subfolder request lost its selected parent")
            let restoredBookmarkStore = BrowserDataStore(defaults: defaults)
            try require(restoredBookmarkStore.bookmarkFolder(id: swiftFolder.id)?.parentID == programmingFolder.id, "nested folders did not persist locally")
            try require(restoredBookmarkStore.bookmarks(in: swiftFolder.id).count == 2, "folder assignments did not persist locally")
            try require(restoredBookmarkStore.bookmarks(in: programmingFolder.id).contains(where: { $0.id == createdFromAddressDrag?.bookmark.id }), "dragged bookmark folder assignment did not persist locally")
            dataStore.deleteBookmarkFolderPreservingContents(programmingFolder)
            try require(dataStore.bookmarks.count == 3, "deleting a parent folder discarded a bookmark")
            try require(dataStore.bookmarkFolder(id: swiftFolder.id)?.parentID == nil, "nested folder was not safely rehomed")
            print("PASS bookmark organizer: nested emoji folders, safe URL drag filing/refiling, context actions, and safe parent deletion succeeded")
            dataStore.toggleBookmark(title: "Local verification", url: localURL)
            if let contextualBookmark = dataStore.bookmark(for: "https://example.com/context-bookmark") {
                dataStore.removeBookmark(contextualBookmark)
            }
            if let draggedBookmark = dataStore.bookmark(for: draggedURL.absoluteString) {
                dataStore.removeBookmark(draggedBookmark)
            }
            if let loadingTitleBookmark = dataStore.bookmark(for: loadingTitleDropURL.absoluteString) {
                dataStore.removeBookmark(loadingTitleBookmark)
            }
            dataStore.clearHistory()
            try require(dataStore.bookmarks.isEmpty && dataStore.history.isEmpty, "library remove/clear controls failed")
            print("PASS library controls: bookmark add/remove and history add/clear succeeded")

            let deterministicPage = PageSnapshot(
                title: "Limeghost Local Verification",
                url: localURL,
                hostname: "127.0.0.1",
                scheme: "http",
                language: "en",
                text: "Cities are adding shaded public spaces as summer temperatures rise. A 2025 survey covering forty cities found that tree cover can make busy streets more comfortable. Planners say shade structures can be installed quickly, while mature trees provide broader environmental benefits. The report recommends measuring street temperature before and after each project. Residents also asked for drinking fountains near transit stops and published maintenance schedules. Maintenance crews water young trees twice a week through the first summer. The city budget sets aside money for replacing damaged shade fabric each year. Volunteers mapped every bench in the market district last autumn. Officials plan to publish the temperature readings on an open data page. An earlier pilot in 2019 covered only three streets, according to the appendix.",
                wordCount: 125,
                hasPasswordField: false,
                formActions: []
            )
            let deterministicText = LocalAnalysisEngine.readableText(page: deterministicPage)
            try require(deterministicText.count > 80, "readable text was unexpectedly short")
            try require(
                deterministicPage.text.contains(deterministicText),
                "readable text is not a verbatim slice of the page it came from"
            )
            print("PASS local assistant core: readable text prepared without a provider or credentials")

            let savedRecord = BrowserTabRecord(
                id: UUID(),
                url: localURL,
                title: "Local verification",
                lastActivatedAt: Date()
            )
            dataStore.saveWorkspace(BrowserWorkspaceSnapshot(tabs: [savedRecord], selectedTabID: savedRecord.id))
            try require(dataStore.loadWorkspace()?.tabs.first == savedRecord, "local session metadata did not round-trip")
            dataStore.clearSavedWorkspace()
            print("PASS session storage: recent-tab metadata saved and restored locally")

            try require(window.makeFirstResponder(session.webView), "WebKit could not accept normal content focus")
            try await loadDeterministicPage(in: session, localURL: fixtureURL)
            try require(session.currentURLString == localURL, "address state did not track local navigation")
            try require(!(window.firstResponder is NSTextView), "navigation unexpectedly stole focus back from web content")
            print("PASS navigation: deterministic page rendered from a verified local HTTP server")

            // A second navigation starting while the first is still in flight is
            // ordinary on real sites — a redirect, a player, a single-page app
            // taking over. The newest one has to win: if an older one stays
            // active, WebKit abandons it, the newer one's completion is dismissed
            // as stale, and the tab spins forever on a page that has finished.
            session.navigate(fixtureURL.deletingLastPathComponent().appendingPathComponent("self-navigating.html").absoluteString)
            let settled = await waitUntil(timeout: 12) {
                !session.isLoading && session.currentURLString.hasSuffix("index.html")
            }
            try require(settled, "a page that navigated itself left the tab loading forever")
            try require(session.loadState == .content, "the tab did not settle on the page it was sent to")
            print("PASS navigation race: a page that redirected itself finished loading")

            // A server redirect through a real navigation: the icon is captured
            // under where the page ended up, and a bookmark holds where it
            // started. Driven end to end on purpose — unit tests that call
            // `recordRedirectAlias` directly pass happily while the browser
            // hands it the post-redirect address, which is exactly the bug
            // this check exists to catch.
            let redirectSource = fixtureURL.deletingLastPathComponent()
                .appendingPathComponent("redirect-to-fixture")
            session.navigate(redirectSource.absoluteString)
            let followed = await waitUntil(timeout: 12) {
                !session.isLoading && session.currentURLString.hasSuffix("index.html")
            }
            try require(followed, "the server redirect never settled")
            let recordedOrigin = reflectedNavigationOriginURL(session)
            try require(
                recordedOrigin?.absoluteString == redirectSource.absoluteString,
                "the address the navigation started at was lost to the redirect — got \(recordedOrigin?.absoluteString ?? "nil")"
            )
            print("PASS redirect origin: the address a visit began at survives the redirect that follows it")

            // Leave the shared session on the page later checks expect.
            try await loadDeterministicPage(in: session, localURL: fixtureURL)

            // The safety net: whatever strands the chrome — a superseded
            // navigation, a site that never reports finishing — WebKit still
            // knows the truth. Strand it deliberately and it must recover.
            session.simulateStrandedLoadingForTesting()
            try require(session.isLoading, "the stranded state did not take hold")
            let recovered = await waitUntil(timeout: 6) { !session.isLoading }
            try require(recovered, "a stranded loading state never cleared itself")
            try require(session.loadState == .content, "recovery left the tab in the wrong state")
            print("PASS loading recovery: a stranded spinner cleared once WebKit reported idle")

            // Content blocking: (1) a control session with no provider proves the
            // fixture itself is valid — both its inline and external-script markers
            // load; (2) a provider scoped to a test-only list blocks the tracker
            // script while the page's own inline script still runs; (3) a per-site
            // exception lets it load again, and removing the exception blocks it
            // once more. The shipped catalog list is never used here.
            let blockingFixtureURL = fixtureURL.appendingPathComponent("blocking.html")
            let noProviderSession = BrowserSession(
                downloadCenter: DownloadCenter(),
                searchSettings: SearchSettingsStore(defaults: defaults)
            )
            try await loadDeterministicPage(
                in: noProviderSession,
                localURL: blockingFixtureURL,
                expectedTitle: "Limeghost Blocking Fixture"
            )
            let controlInlineMarker = try await evaluateValue(
                "window.__limeghostInlineMarker === true", in: noProviderSession
            ) as? Bool
            let controlTrackerMarker = try await evaluateValue(
                "window.__limeghostTrackerFixtureLoaded === true", in: noProviderSession
            ) as? Bool
            try require(
                controlInlineMarker == true && controlTrackerMarker == true,
                "the blocking fixture did not load both its inline and tracker-fixture markers with no content-blocking provider attached"
            )
            noProviderSession.teardown()
            print("PASS content blocking fixture: blocking.html loads its inline marker and tracker-fixture.js with no provider attached")

            let contentBlockingSuiteName = "clearframe.browser.e2e.contentBlocking.\(UUID().uuidString)"
            guard let contentBlockingDefaults = UserDefaults(suiteName: contentBlockingSuiteName) else {
                throw SmokeFailure.check("could not create isolated content-blocking defaults")
            }
            defer { UserDefaults.standard.removePersistentDomain(forName: contentBlockingSuiteName) }
            let ruleStoreDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("limeghost-smoke-content-blocking-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: ruleStoreDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: ruleStoreDirectory) }
            let ruleStore = try requireValue(
                WKContentRuleListStore(url: ruleStoreDirectory),
                "smoke harness could not open a temporary content-rule-list store"
            )
            // A test-only list scoped to the fixture server's own loopback host, and a
            // temp rule store, so this check never touches the shipped catalog or the
            // user's default WebKit rule store. thirdPartyOnly is false because the
            // fixture's "tracker" script is same-origin with the page that loads it.
            let blockingProvider = ContentRuleListProvider(
                settings: ContentBlockingSettingsStore(defaults: contentBlockingDefaults),
                blockList: TrackerBlockList(
                    release: TrackerBlockListRelease(version: "smoke-test.1", lastChecked: Date()),
                    domains: ["127.0.0.1"]
                ),
                ruleStore: ruleStore,
                thirdPartyOnly: false,
                resourceTypes: ["script"]
            )
            let blockedSession = BrowserSession(
                downloadCenter: DownloadCenter(),
                searchSettings: SearchSettingsStore(defaults: defaults),
                contentBlocking: blockingProvider
            )
            await blockingProvider.refresh()
            try await loadDeterministicPage(
                in: blockedSession,
                localURL: blockingFixtureURL,
                expectedTitle: "Limeghost Blocking Fixture"
            )
            let blockedInlineMarker = try await evaluateValue(
                "window.__limeghostInlineMarker === true", in: blockedSession
            ) as? Bool
            try require(blockedInlineMarker == true, "the page's own inline script did not run while its tracker script was blocked")
            let blockedTrackerMarkerType = try await evaluateValue(
                "typeof window.__limeghostTrackerFixtureLoaded", in: blockedSession
            ) as? String
            try require(blockedTrackerMarkerType == "undefined", "the compiled rule list did not block the tracker-fixture script")
            print("PASS content blocking: the compiled rule list blocked tracker-fixture.js while the page's own inline script still ran")

            let navigationVersionBeforeException = blockedSession.navigationVersion
            await blockingProvider.setSiteDisabled(true, forHost: "127.0.0.1")
            blockedSession.reload()
            let reloadedWithException = await waitUntil {
                blockedSession.navigationVersion > navigationVersionBeforeException && blockedSession.loadState == .content
            }
            try require(reloadedWithException, "the fixture page did not finish reloading after a per-site exception was set")
            let exceptedTrackerMarker = try await evaluateValue(
                "window.__limeghostTrackerFixtureLoaded === true", in: blockedSession
            ) as? Bool
            try require(exceptedTrackerMarker == true, "a per-site exception did not let the tracker-fixture script load")

            let navigationVersionBeforeReEnable = blockedSession.navigationVersion
            await blockingProvider.setSiteDisabled(false, forHost: "127.0.0.1")
            blockedSession.reload()
            let reloadedAfterReEnable = await waitUntil {
                blockedSession.navigationVersion > navigationVersionBeforeReEnable && blockedSession.loadState == .content
            }
            try require(reloadedAfterReEnable, "the fixture page did not finish reloading after the per-site exception was removed")
            let reblockedTrackerMarkerType = try await evaluateValue(
                "typeof window.__limeghostTrackerFixtureLoaded", in: blockedSession
            ) as? String
            try require(reblockedTrackerMarkerType == "undefined", "removing the per-site exception did not resume blocking the tracker-fixture script")
            blockedSession.teardown()
            print("PASS content blocking exception: a per-site exception let the tracker script load, and removing it resumed blocking")

            // Site information: the connection state the address chip and its
            // popover both read. It comes from the scheme *and* from WebKit's
            // own answer about the page's subresources, so an https page that
            // pulled part of itself over http can never show a plain lock.
            try require(
                ConnectionSecurity.make(
                    urlString: "https://example.com/",
                    hasOnlySecureContent: true,
                    hasCommittedNavigation: true
                ) == .secure,
                "a fully encrypted https page was not reported as secure"
            )
            try require(
                ConnectionSecurity.make(
                    urlString: "https://example.com/",
                    hasOnlySecureContent: false,
                    hasCommittedNavigation: true
                ) == .mixedContent,
                "an https page carrying insecure subresources was reported as fully secure"
            )
            try require(
                ConnectionSecurity.make(
                    urlString: "http://example.com/",
                    hasOnlySecureContent: true,
                    hasCommittedNavigation: true
                ) == .notSecure,
                "a plain http page was not reported as not secure"
            )
            try require(
                ConnectionSecurity.mixedContent.statusLine == "Parts of this page were loaded over an unencrypted connection",
                "the mixed-content state did not say what happened in plain words"
            )
            // The live session agrees with the derivation: the fixture server
            // speaks plain http, so nothing here may claim a secure connection.
            try require(
                session.connectionSecurity == .notSecure && !session.isSecure,
                "the loaded http fixture page did not report an insecure connection"
            )
            print("PASS site connection state: https, mixed-content, and http pages are reported from WebKit's own secure-content answer")

            // Per-site data removal, on a throwaway non-persistent store so the
            // tester's real cookies are never touched. Two sites are each given
            // a cookie; removing one must leave the other's record standing.
            let siteDataStore = WKWebsiteDataStore.nonPersistent()
            func smokeCookie(domain: String, name: String) throws -> HTTPCookie {
                try requireValue(
                    HTTPCookie(properties: [
                        .domain: domain,
                        .path: "/",
                        .name: name,
                        .value: "1",
                        .expires: Date().addingTimeInterval(3_600)
                    ]),
                    "smoke harness could not build a cookie for \(domain)"
                )
            }
            let firstSiteCookie = try smokeCookie(domain: "example.com", name: "limeghost-smoke-a")
            let secondSiteCookie = try smokeCookie(domain: "www.example.org", name: "limeghost-smoke-b")
            await siteDataStore.httpCookieStore.setCookie(firstSiteCookie)
            await siteDataStore.httpCookieStore.setCookie(secondSiteCookie)
            let siteData = SiteDataInventory(dataStore: siteDataStore)
            await siteData.refresh()
            try require(
                siteData.sites.contains { SiteDataInventory.matches(displayName: $0.displayName, host: "example.com") },
                "the site data list did not report the first site's stored cookie"
            )
            try require(
                siteData.sites.contains { SiteDataInventory.matches(displayName: $0.displayName, host: "www.example.org") },
                "the site data list did not report the second site's stored cookie"
            )
            try require(
                siteData.sites.allSatisfy { !$0.kinds.isEmpty && !$0.kindSummary.contains(where: \.isNumber) },
                "a site row described its stored data with a size or count WebKit never reports"
            )
            // Removed by subdomain on purpose: WebKit names the record after the
            // registrable domain, so this also proves the match is not equality.
            let removedFirstSite = await siteData.remove(forHost: "www.example.com")
            try require(removedFirstSite, "removing data for a subdomain of a listed site reported nothing to remove")
            try require(
                !siteData.sites.contains { SiteDataInventory.matches(displayName: $0.displayName, host: "example.com") },
                "the removed site was still listed as holding data"
            )
            try require(
                siteData.sites.contains { SiteDataInventory.matches(displayName: $0.displayName, host: "example.org") },
                "removing one site's data also removed another site's records"
            )
            let removedMissingSite = await siteData.remove(forHost: "never-visited.example.net")
            try require(!removedMissingSite, "a site that stored nothing was reported as having had data removed")
            print("PASS site data: one site's stored data was listed in plain words and removed without touching another site's records")

            let spaURL = fixtureURL.appendingPathComponent("spa-state").absoluteString
            try await evaluate("history.pushState({}, '', '/spa-state'); document.title = 'Limeghost SPA State'", in: session)
            let spaStateObserved = await waitUntil {
                session.currentURLString == spaURL && session.pageTitle == "Limeghost SPA State"
            }
            try require(spaStateObserved, "same-document URL/title changes were not reflected in browser chrome")
            try await evaluate("history.replaceState({}, '', '/'); document.title = 'Limeghost Local Verification'", in: session)
            let fixtureStateRestored = await waitUntil {
                session.currentURLString == localURL && session.pageTitle == "Limeghost Local Verification"
            }
            try require(fixtureStateRestored, "same-document fixture state did not restore")
            print("PASS SPA state: history API URL and document-title changes stayed synchronized")

            let livePage = try await session.extractPage()
            try require(livePage.title == "Limeghost Local Verification", "extraction did not retain source identity")
            try require(livePage.text.contains("Open shadow content"), "open Shadow DOM reading text was omitted")
            try require(!livePage.text.contains("HIDDEN CONTROL POLLUTION"), "hidden text polluted extraction")
            // Player controls are kept out at two layers. The extractor skips
            // containers that name themselves — this fixture's `.video-player`
            // class — which is what a live page can prove here. The second
            // layer, `readableText`'s phrase filter, exists for players that
            // expose bare label text with no telltale class (zf.ro, the
            // standing case) and is proven by `boilerplateCases` in the shared
            // contract; asserting it against this fixture would test nothing,
            // because the phrase never survives extraction to reach it.
            try require(
                !livePage.text.contains("Video Player is loading"),
                "the extractor read a container that names itself a video player"
            )
            let liveReadable = LocalAnalysisEngine.readableText(page: livePage)
            try require(liveReadable.count > 80, "readable text was unexpectedly short")
            try require(
                LocalAnalysisEngine.clipboardPayload(page: livePage) != nil,
                "a real article gave Copy for AI nothing to copy"
            )
            print("PASS extraction: live page read locally — shadow DOM in, hidden text out, player container skipped")


            // Copy for AI captures `navigationVersion` before reading and refuses
            // to paste if it moved. A History-API move runs none of the ordinary
            // navigation callbacks, so this is the case that quietly breaks: the
            // page changes identity and nothing else notices.
            let versionBeforeSameDocumentMove = session.navigationVersion
            try await evaluate("history.pushState({}, '', '/changed-after-analysis')", in: session)
            let sameDocumentMoveVersioned = await waitUntil {
                session.currentURLString.hasSuffix("/changed-after-analysis")
                    && session.navigationVersion > versionBeforeSameDocumentMove
            }
            try require(
                sameDocumentMoveVersioned,
                "a same-document move did not advance the navigation version, so Copy for AI could paste a page the reader already left"
            )
            try await evaluate("history.replaceState({}, '', '/')", in: session)
            let fixtureIdentityRestored = await waitUntil { session.currentURLString == localURL }
            try require(fixtureIdentityRestored, "fixture URL did not restore after the same-document check")
            print("PASS navigation identity: a History-API move advances the version Copy for AI checks first")

            let listingFixtureURL = fixtureURL.appendingPathComponent("listing.html")
            try await loadDeterministicPage(
                in: session,
                localURL: listingFixtureURL,
                expectedTitle: "Limeghost Local News Digest"
            )
            let listingPage = try await session.extractPage()
            try require(listingPage.title == "Limeghost Local News Digest", "the listing fixture lost its identity in extraction")
            try require(
                LocalAnalysisEngine.assessStructure(page: listingPage) == .listing,
                "a section-page fixture with many unrelated headlines was not recognised as a listing, so the copy notice would stay silent"
            )
            print("PASS structure: a live section page reads as a list of articles, which is what the copy notice tells the reader")

            // A link aggregator keeps every entry in a table row, so nothing on the
            // page is a paragraph and the extractor falls back to the whole
            // document. That fallback used to collapse every newline, handing
            // structure detection a single block it could never judge, and handing
            // the reader key points like "com)82 points by …".
            let tableListingURL = fixtureURL.appendingPathComponent("table-listing.html")
            try await loadDeterministicPage(
                in: session,
                localURL: tableListingURL,
                expectedTitle: "Limeghost Table Digest"
            )
            let tablePage = try await session.extractPage()
            let fallbackBlocks = tablePage.text.split(separator: "\n").count
            try require(
                fallbackBlocks >= 12,
                "the extractor flattened a table listing into \(fallbackBlocks) block(s), so structure detection could never see it"
            )
            try require(
                LocalAnalysisEngine.assessStructure(page: tablePage) == .listing,
                "a link-aggregator fixture built from table rows did not read as a listing"
            )
            print("PASS extractor fallback: a table listing kept its line structure and reads as a listing")

            // A specification page carries a few short paragraphs — a disclaimer, a
            // review teaser, two comments — and keeps its substance in a table. A
            // count of paragraphs called that a page of prose and refused to read
            // the table at all; a measure of how much prose there is does not.
            let specSheetURL = fixtureURL.appendingPathComponent("spec-sheet.html")
            try await loadDeterministicPage(
                in: session,
                localURL: specSheetURL,
                expectedTitle: "Limeghost Spec Sheet"
            )
            let specPage = try await session.extractPage()
            let specText = specPage.text
            try require(
                specText.contains("Super Retina XDR OLED"),
                "the specification table was refused because four short paragraphs counted as prose"
            )
            try require(
                specText.contains("Disclaimer."),
                "the page's own paragraphs went missing when its table was read"
            )
            print("PASS specification page: a table kept its content beside four short paragraphs")

            try await loadDeterministicPage(in: session, localURL: fixtureURL)
            let articleAgain = try await session.extractPage()
            try require(
                LocalAnalysisEngine.assessStructure(page: articleAgain) == .article,
                "the ordinary article fixture was mistaken for a listing"
            )
            try require(
                LocalAnalysisEngine.readableText(page: articleAgain).count > 80,
                "the ordinary article fixture produced unexpectedly little readable text"
            )
            print("PASS structure default: the article fixture reads as one article, so no copy notice interrupts it")

            // Copy for AI sits in the toolbar of every tab, and the start
            // surface is not a web page. Its guard is the address: no valid web
            // URL, no copy. If the start surface ever exposed one, the button
            // would read Limeghost's own start page onto the clipboard.
            session.showStartPage()
            let settledOnStartSurface = await waitUntil {
                session.loadState == .startPage && session.currentURLString.isEmpty
            }
            try require(settledOnStartSurface, "the tab did not return to its start surface")
            try require(
                WebURLPolicy.validatedURL(session.currentURLString) == nil,
                "the start surface claimed a copyable web address, so Copy for AI would read the start page instead of refusing"
            )
            try await loadDeterministicPage(in: session, localURL: fixtureURL)
            try require(
                WebURLPolicy.validatedURL(session.currentURLString) != nil,
                "a real page did not give Copy for AI a valid address to work with"
            )
            let recoveredPage = try await session.extractPage()
            try require(
                LocalAnalysisEngine.clipboardPayload(page: recoveredPage) != nil,
                "extraction did not recover once a real page was open"
            )
            print("PASS copy refusal: the start surface offers nothing to copy and a real page does")

            // File upload: WebKit only shows a file picker for a page if the UI
            // delegate answers this request. Without it every <input type=file>
            // is silently dead, so the wiring itself is what gets checked here;
            // opening a real NSOpenPanel would block this suite.
            try require(
                session.responds(to: #selector(WKUIDelegate.webView(_:runOpenPanelWith:initiatedByFrame:completionHandler:))),
                "the session did not answer WebKit's open-panel request, so file inputs would never show a picker"
            )
            print("PASS file upload: the session answers WebKit's open-panel request instead of leaving file inputs dead")

            guard let find = workspace.selectedTab?.find else {
                throw SmokeFailure.check("selected tab did not expose a find controller")
            }
            find.present()
            try require(find.isPresented, "⌘F did not present the find bar for the selected tab")
            find.query = "shade structures"
            let phraseOnPage = await find.search(backwards: false, fromTop: true)
            try require(
                phraseOnPage == .matched && find.outcome == .matched,
                "find in page did not match a phrase the fixture page contains"
            )
            find.query = "kumquat telemetry"
            let phraseNotOnPage = await find.search(backwards: false, fromTop: true)
            try require(
                phraseNotOnPage == .noResults && find.outcome == .noResults,
                "find in page claimed a match for text the fixture page does not contain"
            )
            find.close()
            try require(!find.isPresented && find.outcome == .idle, "closing the find bar left a stale result behind")
            print("PASS find in page: a phrase on the page matched, an absent phrase reported no results, and closing cleared the state")

            try require(
                session.pageZoom == BrowserSession.defaultPageZoom && session.webView.pageZoom == BrowserSession.defaultPageZoom,
                "the tab did not start at actual size"
            )
            session.zoomIn()
            let firstZoomStep = session.pageZoom
            try require(firstZoomStep > BrowserSession.defaultPageZoom, "⌘+ did not zoom the page in")
            try require(abs(session.webView.pageZoom - firstZoomStep) < 0.0001, "the zoom step never reached the web view")
            session.zoomIn()
            try require(session.pageZoom > firstZoomStep, "a second ⌘+ did not continue up the zoom steps")
            session.zoomOut()
            try require(session.pageZoom == firstZoomStep, "⌘− did not step back down to the previous zoom")
            session.resetPageZoom()
            try require(
                session.pageZoom == BrowserSession.defaultPageZoom && session.webView.pageZoom == BrowserSession.defaultPageZoom,
                "⌘0 did not restore actual size"
            )
            print("PASS page zoom: ⌘+ and ⌘− walked the zoom steps and ⌘0 restored actual size")

            try require(session.canPrintPage, "a loaded web page did not report itself printable")
            try require(workspace.canPrintSelectedPage, "Print was disabled while a real web page was open")
            session.showStartPage()
            let printUnavailableOnStartPage = await waitUntil { !workspace.canPrintSelectedPage }
            try require(printUnavailableOnStartPage, "Print stayed available on the start surface, where there is no page to print")
            try await loadDeterministicPage(in: session, localURL: fixtureURL)
            let printAvailableAgain = await waitUntil { workspace.canPrintSelectedPage }
            try require(printAvailableAgain, "Print did not become available again once a page finished loading")
            print("PASS print availability: the Print command followed the loaded page and disabled itself on the start surface")

            // Every tab opens on `loadHTMLString`, so its first back-forward
            // entry is `about:blank`. Once the reader has navigated away, Back
            // lands on it — and it used to be refused as an unsupported link,
            // covering the still-loaded page with a non-retryable error.
            // The audit expected a tab's start surface to sit in the back list,
            // so that pressing Back onto it would be refused as an unsupported
            // link. WebKit does not record `loadHTMLString` as a back entry at
            // all, so a tab that has navigated once has nothing behind it and
            // the chrome correctly offers no way back. The session still adopts
            // its start surface if an `about:blank` entry ever does arrive —
            // that path is kept as a guard, not as a fix for this.
            let freshTab = BrowserSession(
                downloadCenter: DownloadCenter(),
                searchSettings: SearchSettingsStore(defaults: defaults)
            )
            let freshOnStartSurface = await waitUntil { freshTab.loadState == .startPage && !freshTab.isLoading }
            try require(freshOnStartSurface, "a new tab did not settle on its start surface")
            try require(!freshTab.canGoBack, "a new tab offered a back step before it had been anywhere")
            try await loadDeterministicPage(in: freshTab, localURL: fixtureURL)
            try require(
                !freshTab.canGoBack,
                "the start surface entered the back list, so Back can land on it and must be handled"
            )
            try require(freshTab.loadState == .content, "the fresh tab did not settle on the page it loaded")
            freshTab.teardown()
            print("PASS back/forward: a tab's start surface stays out of the back list, so Back never lands on it")

            // Following a link must not cover the page being read. A tab with a
            // page on screen keeps it while the next one loads — the progress
            // bar carries that news — and only a tab with nothing to show gets
            // the opening card.
            let readingTab = BrowserSession(
                downloadCenter: DownloadCenter(),
                searchSettings: SearchSettingsStore(defaults: defaults)
            )
            try require(!readingTab.hasRenderedPage, "a new tab claimed to have a page on screen")
            try await loadDeterministicPage(in: readingTab, localURL: fixtureURL)
            try require(readingTab.hasRenderedPage, "a loaded page was not treated as being on screen")
            readingTab.navigate(fixtureURL.deletingLastPathComponent().appendingPathComponent("second.html").absoluteString)
            try require(
                readingTab.hasRenderedPage,
                "following a link dropped the page still on screen, so the opening card would cover it"
            )
            let arrived = await waitUntil { readingTab.loadState == .content && !readingTab.isLoading }
            try require(arrived, "the second page did not finish loading")
            readingTab.showStartPage()
            try require(!readingTab.hasRenderedPage, "the start surface still claimed a page was on screen")
            readingTab.teardown()
            print("PASS link follow: a page stays on screen while the next one loads")

            // A mailto: link is not a web link, but refusing it must not take
            // away the page the reader is reading. The hand-off is injected so
            // this check never launches a real mail client.
            var handedOffLink: URL?
            session.openExternalScheme = { handedOffLink = $0 }
            try await evaluate("location.href = 'mailto:someone@example.com?subject=Limeghost'", in: session)
            let mailtoHandedOff = await waitUntil { handedOffLink != nil }
            session.openExternalScheme = { _ in }
            try require(mailtoHandedOff, "a mailto: link was not handed to the app that owns it")
            try require(handedOffLink?.scheme == "mailto", "the hand-off received something other than the mailto: link")
            try require(session.loadState == .content, "a mailto: link replaced the page the reader was on")
            try require(session.currentURLString == localURL, "a mailto: link changed the address of the page the reader was on")
            print("PASS declined links: a mailto: link went to the app that owns it and left the open page untouched")

            workspace.toggleBookmarkForSelectedTab()
            try require(dataStore.bookmarks.count == 1, "bookmark was not saved")
            try require(dataStore.history.contains(where: { $0.url == localURL }), "completed visit was not recorded")
            print("PASS library: bookmark and local history entry created")

            try await evaluate("document.querySelector('a[target=_blank]').click()", in: session)
            let newTabOpened = await waitUntil { workspace.tabs.count == 2 }
            try require(newTabOpened, "target-blank link did not create a tab")
            try require(workspace.selectedTabID == workspace.tabs.last?.id, "new tab was not selected")
            let focusRequestBeforeClosingPopup = workspace.focusAddressRequest
            workspace.closeSelectedTab()
            try require(workspace.tabs.count == 1, "tab did not close cleanly")
            try require(workspace.selectedTab?.session === session, "closing the new tab did not return to the original tab")
            try require(
                workspace.focusAddressRequest == focusRequestBeforeClosingPopup,
                "closing a content tab issued an unnecessary address-focus request"
            )
            print("PASS tabs/focus: popup tab opened and closed without stealing focus into the address field")

            // A popup opened with no address of its own — the shape a script
            // uses when it opens the tab first and assigns location after.
            // It used to be dropped silently, so the flow appeared to do
            // nothing at all.
            try await evaluate("document.querySelector('#blank-popup').click()", in: session)
            let blankPopupOpened = await waitUntil { workspace.tabs.count == 2 }
            try require(blankPopupOpened, "a popup with no address of its own did not open a tab")
            try require(workspace.selectedTab?.session.currentURLString.isEmpty == true, "the blank popup tab was not left waiting on its start surface")
            workspace.closeSelectedTab()
            try require(workspace.tabs.count == 1, "the blank popup tab did not close cleanly")
            print("PASS blank popup: a popup with no address yet still opened a tab instead of vanishing")

            // window.open(): the popup tab has to adopt the exact web view
            // WebKit handed over. Building a different one severs the opener,
            // so a popup sign-in completes in the new tab and can never report
            // its result to the page that started it.
            try await evaluate("document.querySelector('#script-popup').click()", in: session)
            let scriptedPopupOpened = await waitUntil { workspace.tabs.count == 2 }
            try require(scriptedPopupOpened, "window.open() did not open a tab")
            guard let popupSession = workspace.selectedTab?.session, popupSession !== session else {
                throw SmokeFailure.check("window.open() did not select a popup tab of its own")
            }
            let popupLoaded = await waitUntil(timeout: 12) { popupSession.loadState == .content }
            try require(popupLoaded, "the adopted popup web view never loaded the page window.open() asked for")
            let openerIsConnected = try await evaluateValue("window.opener !== null", in: popupSession) as? Bool
            try require(
                openerIsConnected == true,
                "the popup lost its opener, so a popup sign-in could never notify the page that started it"
            )
            workspace.closeSelectedTab()
            try require(workspace.tabs.count == 1, "the scripted popup tab did not close cleanly")
            print("PASS window.open(): the popup adopted WebKit's own web view and kept its opener")

            session.navigate("limeghost deterministic smoke query")
            let searchURL = reflectedRequestedURL(session)
            try require(searchURL?.host == "duckduckgo.com", "search text did not resolve to the configured search URL")
            try require(searchQuery(in: searchURL) == "limeghost deterministic smoke query", "search query was not preserved")
            session.stopLoading()
            print("PASS search: plain text resolved to DuckDuckGo with the expected query")

            // Every listed engine reads a literal + in a query value as a
            // space, so "C++ tutorial" used to be searched as "C tutorial".
            session.navigate("C++ tutorial")
            let plusSearchURL = reflectedRequestedURL(session)
            try require(
                searchQuery(in: plusSearchURL) == "C++ tutorial",
                "a search containing + did not round-trip through the results URL"
            )
            try require(
                plusSearchURL?.absoluteString.contains("+") == false,
                "the results URL kept a literal +, which the search engine reads as a space"
            )
            session.stopLoading()
            print("PASS search encoding: a query containing + reached the engine as the words that were typed")

            try await loadDeterministicPage(in: session, localURL: fixtureURL)
            workspace.persistNow()
            let restored = BrowserWorkspace(
                dataStore: BrowserDataStore(defaults: defaults),
                downloads: DownloadCenter(),
                searchSettings: SearchSettingsStore(defaults: defaults)
            )
            try require(restored.tabs.count == 1, "saved tab session did not restore")
            try require(restored.selectedTab?.persistenceRecord.url == localURL, "restored tab URL was incorrect")
            print("PASS session: current tab restored from isolated local storage")

            workspace.toggleBookmarkForSelectedTab()
            dataStore.clearHistory()
            try require(dataStore.bookmarks.isEmpty, "bookmark removal failed")
            try require(dataStore.history.isEmpty, "history clear failed")
            print("PASS library controls: bookmark removal and history clear succeeded")

            window.close()
            try require(!window.isVisible, "native test window did not close")
            print("PASS lifecycle: native window closed cleanly")
            print("RESULT: all deterministic browser E2E checks passed")
        }
    }
}
