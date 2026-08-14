import AppKit
import ClearframeCore
import Foundation
import SwiftUI

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
    expectedTitle: String = "Clearframe Local Verification"
) async throws {
    session.navigate(localURL.absoluteString)
    let loaded = await waitUntil(condition: {
        session.loadState == .content && session.pageTitle == expectedTitle
    })
    try require(loaded, "deterministic page did not render from the verified local fixture server")
}

private func configuredFixtureURL() throws -> URL {
    guard let value = ProcessInfo.processInfo.environment["CLEARFRAME_SMOKE_BASE_URL"],
          let url = WebURLPolicy.validatedURL(value) else {
        throw SmokeFailure.check("CLEARFRAME_SMOKE_BASE_URL was not supplied by the smoke harness")
    }
    return url
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

@main
@MainActor
struct BrowserE2ESmoke {
    static func main() async {
        let suiteName = "clearframe.browser.e2e.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fputs("FAIL: could not create isolated defaults\n", stderr)
            exit(1)
        }
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

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
            let aiConfiguration = AIConfigurationStore(defaults: defaults)
            let rootView = BrowserView()
                .environmentObject(workspace)
                .environmentObject(aiConfiguration)
                .environmentObject(onboarding)
            let window = NSWindow(
                contentRect: NSRect(x: 100, y: 100, width: 1_180, height: 760),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Clearframe E2E Verification"
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

            guard let session = workspace.selectedTab?.session,
                  let assistant = workspace.selectedTab?.assistant else {
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

            session.navigate("clearframe deterministic smoke query")
            let deterministicSearchURL = reflectedRequestedURL(session)
            try require(deterministicSearchURL?.host == "duckduckgo.com", "search text did not resolve to the configured search URL")
            try require(searchQuery(in: deterministicSearchURL) == "clearframe deterministic smoke query", "search query was not preserved")
            session.stopLoading()
            session.showStartPage()
            print("PASS search resolution: plain text produced the expected DuckDuckGo request")

            searchSettings.selectedEngine = .startpage
            let restoredSearchSettings = SearchSettingsStore(defaults: defaults)
            try require(restoredSearchSettings.selectedEngine == .startpage, "search engine choice did not persist locally")
            session.navigate("clearframe alternate provider query")
            let alternateSearchURL = reflectedRequestedURL(session)
            try require(alternateSearchURL?.host == "www.startpage.com", "selected Startpage search did not use its configured host")
            try require(searchQuery(in: alternateSearchURL, named: "query") == "clearframe alternate provider query", "Startpage query was not preserved")
            session.stopLoading()
            session.showStartPage()
            print("PASS search settings: Startpage selection persisted locally and updated URL resolution")

            searchSettings.selectedEngine = .google
            let restoredGoogleSettings = SearchSettingsStore(defaults: defaults)
            try require(restoredGoogleSettings.selectedEngine == .google, "Google search selection did not persist locally")
            session.navigate("Clearframe source aware browser")
            let googleSearchURL = reflectedRequestedURL(session)
            try require(googleSearchURL?.scheme == "https", "Google search did not use HTTPS")
            try require(googleSearchURL?.host == "www.google.com", "selected Google search did not use google.com")
            try require(searchQuery(in: googleSearchURL) == "Clearframe source aware browser", "Google search query was not preserved")
            session.stopLoading()

            let directURL = URL(string: "https://example.com/direct-path?source=clearframe")!
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
                dataStore.createBookmarkFolder(title: "Programming", emoji: "💻", parentID: nil),
                "bookmark organizer did not create a root folder"
            )
            let swiftFolder = try requireValue(
                dataStore.createBookmarkFolder(title: "Swift", emoji: "🐦", parentID: programmingFolder.id),
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
                title: "Clearframe Local Verification",
                url: localURL,
                hostname: "127.0.0.1",
                scheme: "http",
                language: "en",
                text: "Cities are adding shaded public spaces as summer temperatures rise. A 2025 survey covering forty cities found that tree cover can make busy streets more comfortable. Planners say shade structures can be installed quickly, while mature trees provide broader environmental benefits. The report recommends measuring street temperature before and after each project. Residents also asked for drinking fountains near transit stops and published maintenance schedules. Maintenance crews water young trees twice a week through the first summer. The city budget sets aside money for replacing damaged shade fabric each year. Volunteers mapped every bench in the market district last autumn. Officials plan to publish the temperature readings on an open data page. An earlier pilot in 2019 covered only three streets, according to the appendix.",
                wordCount: 125,
                hasPasswordField: false,
                formActions: []
            )
            let deterministicAnalysis = try await LocalPageIntelligenceProvider().analyze(page: deterministicPage)
            try require(deterministicAnalysis.summary.count > 80, "local assistant summary was unexpectedly short")
            try require(!deterministicAnalysis.claimsToCheck.isEmpty, "local assistant did not surface the test claim")
            print("PASS local assistant core: deterministic page summarized without a provider or credentials")

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

            let spaURL = fixtureURL.appendingPathComponent("spa-state").absoluteString
            try await evaluate("history.pushState({}, '', '/spa-state'); document.title = 'Clearframe SPA State'", in: session)
            let spaStateObserved = await waitUntil {
                session.currentURLString == spaURL && session.pageTitle == "Clearframe SPA State"
            }
            try require(spaStateObserved, "same-document URL/title changes were not reflected in browser chrome")
            try await evaluate("history.replaceState({}, '', '/'); document.title = 'Clearframe Local Verification'", in: session)
            let fixtureStateRestored = await waitUntil {
                session.currentURLString == localURL && session.pageTitle == "Clearframe Local Verification"
            }
            try require(fixtureStateRestored, "same-document fixture state did not restore")
            print("PASS SPA state: history API URL and document-title changes stayed synchronized")

            await assistant.analyzeCurrentPage(session: session)
            try require(assistant.state == .ready, "local assistant did not reach ready state")
            try require(assistant.analysis?.mode == .local, "assistant unexpectedly used a remote provider")
            try require((assistant.analysis?.content.summary.count ?? 0) > 80, "local summary was unexpectedly short")
            try require(assistant.snapshot?.title == "Clearframe Local Verification", "assistant did not retain source identity")
            try require(assistant.snapshot?.text.contains("Open shadow content") == true, "open Shadow DOM reading text was omitted")
            try require(assistant.snapshot?.text.contains("HIDDEN CONTROL POLLUTION") == false, "hidden text polluted extraction")
            try require(assistant.snapshot?.text.contains("Video Player is loading") == false, "media controls polluted extraction")
            print("PASS assistant: visible text extracted and summarized locally")

            let evidencePoint = try requireValue(
                assistant.analysis?.content.keyPoints.first,
                "local assistant did not produce evidence-test key points"
            )
            await assistant.revealEvidence(for: evidencePoint, session: session)
            try require(assistant.evidenceWasFoundOnPage, "Evidence Mode did not find the exact extracted sentence")
            let highlightedEvidence = try await evaluateValue(
                """
                (() => {
                  const roots = [document];
                  document.querySelectorAll('*').forEach(element => { if (element.shadowRoot) roots.push(element.shadowRoot); });
                  const element = roots.map(root => root.querySelector('[data-clearframe-evidence]')).find(Boolean);
                  return (element?.innerText || element?.textContent || '').replace(/\\s+/g, ' ').trim();
                })()
                """,
                in: session
            ) as? String
            try require(
                highlightedEvidence?.contains(evidencePoint) == true,
                "Evidence Mode highlighted a different or empty DOM node"
            )
            print("PASS evidence: exact extracted text was selected and visibly highlighted")

            try await evaluate("history.pushState({}, '', '/changed-after-analysis')", in: session)
            let staleAnalysisCleared = await waitUntil {
                session.currentURLString.hasSuffix("/changed-after-analysis") && assistant.state == .idle
            }
            try require(staleAnalysisCleared, "same-document navigation left stale assistant results attached")
            try await evaluate("history.replaceState({}, '', '/')", in: session)
            let evidenceFixtureRestored = await waitUntil { session.currentURLString == localURL }
            try require(evidenceFixtureRestored, "fixture URL did not restore after stale-analysis check")
            print("PASS assistant lifecycle: same-document navigation cleared stale analysis")

            let listingFixtureURL = fixtureURL.appendingPathComponent("listing.html")
            try await loadDeterministicPage(
                in: session,
                localURL: listingFixtureURL,
                expectedTitle: "Clearframe Local News Digest"
            )
            await assistant.analyzeCurrentPage(session: session)
            try require(assistant.state == .structureNotice, "a section-page fixture with many unrelated headlines did not produce a structure notice")
            try require(assistant.analysis == nil, "a structure notice unexpectedly produced an analysis before the reader chose to proceed")
            try require(assistant.snapshot?.title == "Clearframe Local News Digest", "the structure notice did not retain the listing snapshot")
            print("PASS structure notice: a section-page fixture with many unrelated headlines stopped at a notice instead of summarizing it")

            await assistant.analyzeDespiteStructure(session: session)
            try require(assistant.state == .ready, "Analyze anyway did not reach a ready state from the structure notice")
            try require(assistant.analysis?.mode == .local, "Analyze anyway unexpectedly used a remote provider")
            try require((assistant.analysis?.content.summary.count ?? 0) > 80, "Analyze anyway produced an unexpectedly short summary")
            print("PASS structure override: Analyze anyway summarized the already-extracted listing snapshot without reading the page again")

            try await loadDeterministicPage(in: session, localURL: fixtureURL)
            await assistant.analyzeCurrentPage(session: session)
            try require(assistant.state == .ready, "the ordinary article fixture no longer analyzes straight to a ready summary")
            try require((assistant.analysis?.content.summary.count ?? 0) > 80, "the ordinary article fixture produced an unexpectedly short summary")
            print("PASS structure default: the article fixture still analyzes straight to ready without a listing notice")

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

            session.navigate("clearframe deterministic smoke query")
            let searchURL = reflectedRequestedURL(session)
            try require(searchURL?.host == "duckduckgo.com", "search text did not resolve to the configured search URL")
            try require(searchQuery(in: searchURL) == "clearframe deterministic smoke query", "search query was not preserved")
            session.stopLoading()
            print("PASS search: plain text resolved to DuckDuckGo with the expected query")

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
        } catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
