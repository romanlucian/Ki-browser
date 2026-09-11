# iPhone Page Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the iPhone app its page menu, plus Reader, a find bar and a notice banner on the phone.
- The menu is a `•••` sheet with ten items: Reader, Copy for AI, Reload, Forward, New Tab, New Private Tab, Add Bookmark, Find in Page, Share, and Request Desktop Site.

**Architecture:**
- The phone draws the Mac's own objects: `BrowserWorkspace`, `BrowserSession` and `ReaderView`.
- Every menu row calls a workspace method, and all but one of those methods already exist on the Mac. The one new method is the desktop-site toggle.
- Two small shared additions carry it: a per-tab desktop switch, and a copy confirmation.
- `PageMenuModel` is pure and decides what the sheet shows. `PageMenuActions` performs a row. `PageMenuPresentation` holds the rule that a row closes the sheet before it acts.
- The page-load hook in `BrowserSession` becomes a pure decision function, so its branches can be tested.

**Tech Stack:**
- Swift in language mode 5.
- SwiftUI with an iOS 17.0 deployment target, WebKit, and XCTest.
- Xcode 26.6 with the iOS 26.5 simulator SDK.
- SwiftPM for the Mac package.

**Spec:** [docs/superpowers/specs/2026-09-12-ios-page-menu-design.md](../specs/2026-09-12-ios-page-menu-design.md). The mockups are the canvas it links. Read the spec before any task; this plan argues from it.

## Global Constraints

These apply to every task:
- **Targets.** iOS deployment target 17.0 and `SWIFT_VERSION = 5.0`, as `ios/Limeghost.xcodeproj` sets them.
- **Platform code.** No `#if os` in `LimeghostShared`.
- **Colours.** New colours come from `LimeghostTheme`. The bottom bar and the find bar keep the system look until step 5.
- **Menu labels, exactly:** "Reader" / "Close Reader", "Copy for AI", "Reload", "Forward", "New Tab", "New Private Tab", "Add Bookmark" / "Remove Bookmark", "Find in Page", "Share", "Request Desktop Site" / "Request Mobile Site".
- **Notices, exactly:** "Bookmark added.", "Bookmark removed.", and `ReaderArticle.copyConfirmation`. That is the article's `copyNotice` when it has one, else "Copied \(words) words."
- **Find in Page** says "No results" or says nothing. Never a count, never a position.
- **Doors.** No new doors. Reload is not a door. New Tab, New Private Tab and Forward go through the workspace methods that already are doors.
- **Reader** draws `readableText` and nothing else. There is one `ReaderView`, compiled by both apps.
- **Signing.** `DEVELOPMENT_TEAM` stays `""` in `project.pbxproj`. Signing happens on the command line only.
- **Storage identifiers.** `com.clearframe.browser` and the `clearframe.*` keys are not touched. Test defaults suites keep the existing `clearframe.` prefix.
- **Tests.** Every test is watched failing before its code exists, then broken on purpose once it passes, to see it fail for its own reason.
- **Suites to run.** A change to `LimeghostShared`, `LimeghostCore`, or any file the phone compiles by reference is not finished on `swift test` alone. It also runs `LimeghostSharedLayer` on both destinations, and the phone's suite.
- **Validation.** No document calls any of this validated.

## Verified before this plan was written

Checked on September 12, 2026, by reading the files named, at `369898f` on `feature/ios-pocket-browser`.

**WebKit**
- `WKNavigationDelegate.h` in the iOS 26.5 simulator SDK declares `webView:decidePolicyForNavigationAction:preferences:decisionHandler:` as `API_AVAILABLE(macos(10.15), ios(13.0))`. Its comment says that when a delegate implements it, `-webView:decidePolicyForNavigationAction:decisionHandler: will not be called.`

**`BrowserSession`** (`macos/LimeghostBrowser/Sources/LimeghostShared/BrowserSession.swift`)
- It is `@MainActor public final class BrowserSession: NSObject, ObservableObject` (lines 67–68). The file uses `@preconcurrency import WebKit`.
- The navigation delegate conformance is `extension BrowserSession: WKNavigationDelegate` (line 992). The action-policy method runs from line 1119 to 1162.
- `isShowingStartPage` and `lastRequestedURL` are private vars (lines 138–139).
- `isStartSurfaceURL(_:)` is `static`, internal, and true only for `about:blank` (line 468). `handleUnsupportedLink(_:)` (476), `requestNewTab(for:)` (488) and `adoptStartPageEntry()` (534) are private.
- `load(_:displayName:)` sets `isShowingStartPage = false` and `currentURLString` synchronously (lines 304–320).
- `reload()` shows the start page when the tab is on it, and otherwise reloads the web view (426–428).
- `showPageNotice(_:)` clears the notice after 8 seconds, and `dismissPageNotice()` clears it at once (499–512).

**URL policy**
- `WebURLPolicy.validatedURL(_:)` accepts only `http` and `https`, with a host and no user or password. It returns `URLComponents.url` (`LimeghostCore/BrowserDataModels.swift`).
- `BookmarkURLPolicy.validatedURL` is the same function under another name.

**`BrowserWorkspace` and `BrowserTab`** (`BrowserWorkspace.swift`)
- `readCurrentPage(verb:)` posts "There is no web page in this tab to \(verb)." when the tab has no web address (157–160).
- `copyArticleForAI(_:)` posts `copyNotice` only when it is non-nil (186–191).
- `toggleReaderInSelectedTab()` and `copySelectedPageForAI()` are at 691–720. The only caller of the latter is `LimeghostBrowserApp.swift:277`, inside a `Task`.
- `findInSelectedTab()` calls `selectedTab?.find.present()` (1377).
- `canShareSelectedPage` is at 1464, and `reloadSelectedTab()` at 1470.
- `goForwardInSelectedTab()` calls `makeRoomForPage()` (1483).
- `addTab(url:select:isPrivate:)` is at 650.
- `BrowserTab.readerArticle` is `@Published public var` (33). It is cleared on every change of `navigationVersion` (142–145).
- `BrowserTab.find` and `BrowserTab.isPrivate` are public `let`s.

**Other shared types**
- `BrowserDataStore.isBookmarked(_:)` is an exact string match. `toggleBookmark(title:url:)` normalises through `BookmarkURLPolicy` and does nothing for an address it refuses (`BrowserDataStore.swift` 203, 259–273).
- `PageFindController`'s whole API is: `query`, `isPresented`, `outcome` (`.idle`, `.matched`, `.noResults`), `focusRequest`, `present()`, `close()`, `queryChanged()`, `step(backwards:)` and `resetForNavigation()`.

**Mac app views**
- `ReaderView(article:copy:close:)` is 126 lines in the Mac app target. It holds `@State private var didCopy`. Its one call site is `BrowserView.swift:151–155`.
- The Mac's find bar says "No results" for `.noResults` and nothing otherwise (`BrowserView.swift:913–917`). It disables its arrows only while the query is empty.
- The Mac's menu bar names: "New Tab", "New Private Tab", "Add Bookmark", "Find in Page", "Forward", "Reload Page", "Share Page…", "Copy Page for AI" (`LimeghostBrowserApp.swift`).

**The phone's code**
- The tab switcher's Private section uses `eye.slash.fill` (`ios/Sources/TabSwitcher.swift:123`).
- `IOSPageSharing.share` presents a `UIActivityViewController` from the key window's root view controller (`ios/Sources/IOSCollaborators.swift`).
- `WorkspaceHost.forTesting(defaults:)` builds a workspace on a throwaway suite with `restoresSession: false`.

**Tests and fixtures**
- `BrowserBehaviorTests` is a `@MainActor` class. It imports `LimeghostCore`, `SwiftUI` and `WebKit`, and uses `@testable import` for `LimeghostShared` and `LimeghostBrowser`. It has a private `renderedHeight(of:width:)` helper at line 891, and its Reader tests start at line 404.
- `PageSnapshot` has a public memberwise initialiser (`LimeghostCore/Models.swift:22`).
- `RecordingPlatform` (in `BrowserSessionPlatformTests.swift`) is internal, so it can be reused across `LimeghostSharedTests`. So can `NoDownloads`, `NoPageSharing` and `NoClipboard` (in `WorkspaceDoorTests.swift`).

**The project file**
- `ios/Limeghost.xcodeproj/project.pbxproj` has hand-assigned IDs.
- Free IDs used below: `…020D`–`…020F` and `…010C`–`…010E` for app sources; `…0667`/`…0677` for `ReaderView.swift` by reference; `…2207`–`…2209` and `…2107`–`…2109` for tests.
- The file indents with tabs.

**Toolchain**
- `xcodebuild -version` prints Xcode 26.6, build 17F113.
- `xcrun simctl list devices available` lists "iPhone 17 Pro".

**Last suite counts** (September 10, 2026; re-run before Task 1):
- Mac `swift test`: 504 executed, 0 failures.
- `LimeghostSharedLayer`: 256 on each destination, which is 236 `LimeghostCoreTests` plus 20 `LimeghostSharedTests`.
- The app: 28.

**Not verified here; each is a step below:**
- Whether `ReaderView.swift` compiles for iOS (Task 2, Step 4).
- Whether a `.height` detent leaves the last row above the home indicator (Task 8).
- Whether a reload after the switch brings a site's desktop version (Task 8).

## Commands

Run everything from the worktree root:

```bash
cd /Users/MacBook/Documents/browser/.claude/worktrees/ios-pocket-browser
```

A session whose working directory is the main checkout must give git the worktree explicitly: `git -C /Users/MacBook/Documents/browser/.claude/worktrees/ios-pocket-browser …`.

**The Mac.** This runs every package target: `LimeghostCoreTests`, `LimeghostSharedTests` and `BrowserBehaviorTests`.

```bash
cd macos/LimeghostBrowser && swift test
cd macos/LimeghostBrowser && swift test --filter <TestClassOrMethodName>
```

**The shared layer**, on the iPhone simulator and on macOS:

```bash
cd macos/LimeghostBrowser && xcodebuild test -scheme LimeghostSharedLayer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
cd macos/LimeghostBrowser && xcodebuild test -scheme LimeghostSharedLayer -destination 'platform=macOS'
```

**The iPhone app and its tests.** To run one class, add `-only-testing:LimeghostTests/<Class>`.

```bash
cd ios && xcodebuild test -scheme Limeghost -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

**Reading the counts:**
- Read counts with `grep -E "^\*\* TEST|Executed [0-9]+ tests"`, never with `tail`.
- Take `LimeghostSharedLayer`'s count from the test list, because its parallel log cannot be counted:

  ```bash
  swift test --list-tests | grep -cE '^(LimeghostCoreTests|LimeghostSharedTests)\.'
  ```

- The Mac's skipped count varies from 2 to 4 with the environment. Judge a run by the executed count and zero failures.

**Before Task 1,** run all four suites and write the numbers into the task's notes. The expected results in each step are those numbers plus that task's new tests.

## File Structure

**Shared** (`macos/LimeghostBrowser/Sources/LimeghostShared/`)

| File | Change |
|---|---|
| `BrowserSession.swift` | Adds the desktop switch. The page-load hook becomes `decide(…)`, a pure function. `applyContentMode(…)` is added, and the delegate takes its `preferences:` form. |
| `BrowserWorkspace.swift` | `copySelectedPageForAI()` returns the article it copied. `toggleDesktopSiteInSelectedTab()` is added. |
| `ReaderArticle.swift` | Adds `copyConfirmation`. |

**Mac app** (`macos/LimeghostBrowser/Sources/LimeghostBrowser/`)

| File | Change |
|---|---|
| `ReaderView.swift` | Adds `HeaderStyle` (`.pointer`, `.touch`) and a nested `Header` view. The phone compiles this file by reference. |

**Phone** (`ios/Sources/`)

| File | Change |
|---|---|
| `PageMenu.swift` (new) | `PageMenuItem`, `PageMenuModel`, `PageMenuActions`, `PageMenuPresentation`, and the `PageMenu` view. |
| `FindBar.swift` (new) | The find bar, with its outcome text and arrow state as pure static functions. |
| `NoticeBanner.swift` (new) | `NoticeBanner`, and `NoticeLayer`, which observes the selected session. |
| `BottomBar.swift` | Adds the `•••` button. |
| `BrowserScreen.swift` | The menu sheet, `BottomChrome` (find bar or bottom bar), `TabSurface.showsTheReader` with Reader over the page, and the banner over the tab's surface. |

**Tests**

| File | Covers |
|---|---|
| `LimeghostSharedTests/NavigationPolicyTests.swift` (new) | The decision, the delegate variant, and the switch. |
| `BrowserBehaviorTests.swift` | Two new tests: Reader's header, and `copyConfirmation`. |
| `ios/Tests/ReaderOnThePhoneTests.swift` (new) | The touch header, and Reader over the page. |
| `ios/Tests/PageMenuTests.swift` (new) | Model, actions and presentation. |
| `ios/Tests/FindBarTests.swift` (new) | The find bar's outcome text and arrows. |

**Project file.** `ios/Limeghost.xcodeproj/project.pbxproj` gains the three new sources, `ReaderView.swift` by reference, and the three new test files.

---

### Task 1: The page-load hook as a decision, and a desktop switch on each session

**Files:**
- Create: `macos/LimeghostBrowser/Tests/LimeghostSharedTests/NavigationPolicyTests.swift`
- Modify: `macos/LimeghostBrowser/Sources/LimeghostShared/BrowserSession.swift`, in four places:
  - below `pageNotice` (line 117);
  - after `reload()` (lines 426–428);
  - a new extension directly above `extension BrowserSession: WKNavigationDelegate` (line 992);
  - the delegate method at lines 1119–1162.

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces:
  - `BrowserSession.prefersDesktopSite: Bool`, declared `@Published public private(set)`.
  - `public func setPrefersDesktopSite(_ prefersDesktop: Bool)`.
  - `enum BrowserSession.NavigationActionDecision: Equatable`, internal, with the cases `.download`, `.openInNewTab(URL?)`, `.restoreStartSurface`, `.unsupported(URL)` and `.allow(mainFrameURL: URL?)`.
  - `static func decide(shouldPerformDownload: Bool, targetFrameIsMain: Bool?, url: URL?) -> NavigationActionDecision`, internal.
  - `static func applyContentMode(prefersDesktopSite: Bool, to preferences: WKWebpagePreferences)`, internal.

- [ ] **Step 1: Write the failing tests**

Create `macos/LimeghostBrowser/Tests/LimeghostSharedTests/NavigationPolicyTests.swift`:

```swift
import XCTest
import WebKit
@testable import LimeghostShared

/// The page-load hook, read as a decision, and a tab's request for a site's
/// desktop version.
///
/// The decision used to live only inside the navigation delegate, where no
/// test reached it. It is a pure function of four facts now, so each branch
/// is checked here with plain values, on the Mac and on the Simulator alike.
@MainActor
final class NavigationPolicyTests: XCTestCase {
    private let page = URL(string: "https://example.com/owls")!

    // MARK: - The decision, one branch at a time

    /// A link that asks to be saved is saved, whatever its address. Asked
    /// before anything else, because `<a download href="blob:…">` has an
    /// address no navigation would accept.
    func testALinkThatAsksToBeSavedIsDownloaded() {
        let blob = URL(string: "blob:https://example.com/5f0c")!
        XCTAssertEqual(
            BrowserSession.decide(shouldPerformDownload: true, targetFrameIsMain: true, url: blob),
            .download
        )
    }

    /// A link aimed at a new window opens a tab of its own.
    func testALinkWithNoTargetFrameOpensInANewTab() {
        XCTAssertEqual(
            BrowserSession.decide(shouldPerformDownload: false, targetFrameIsMain: nil, url: page),
            .openInNewTab(page)
        )
    }

    /// Going back onto a tab's first entry, `about:blank`, is a return to its
    /// start surface, not a link Limeghost cannot open.
    func testGoingBackOntoTheStartPageRestoresTheStartSurface() {
        let blank = URL(string: "about:blank")!
        XCTAssertEqual(
            BrowserSession.decide(shouldPerformDownload: false, targetFrameIsMain: true, url: blank),
            .restoreStartSurface
        )
    }

    /// Any other main-frame address that is not a web page goes to
    /// `handleUnsupportedLink`, which hands `mailto:` and `tel:` to their
    /// apps and names the rest in a notice.
    func testAnAddressThatIsNotAWebPageIsUnsupported() {
        let script = URL(string: "javascript:alert(1)")!
        XCTAssertEqual(
            BrowserSession.decide(shouldPerformDownload: false, targetFrameIsMain: true, url: script),
            .unsupported(script)
        )
    }

    /// A web page in the main frame loads, and is recorded as the page asked for.
    func testAWebPageLoadsAndIsRecordedAsThePageAskedFor() {
        XCTAssertEqual(
            BrowserSession.decide(shouldPerformDownload: false, targetFrameIsMain: true, url: page),
            .allow(mainFrameURL: page)
        )
    }

    /// A frame inside the page loads without becoming the page: nothing is
    /// recorded, whatever its address.
    func testAFrameInsideThePageLoadsWithoutBecomingThePage() {
        let frame = URL(string: "https://ads.example/frame")!
        XCTAssertEqual(
            BrowserSession.decide(shouldPerformDownload: false, targetFrameIsMain: false, url: frame),
            .allow(mainFrameURL: nil)
        )
    }

    // MARK: - The question WebKit asks

    /// WebKit asks the variant of the policy question that carries
    /// `WKWebpagePreferences`, and when a delegate answers it, never asks the
    /// older one (`WKNavigationDelegate.h`). The session answers that variant
    /// and only that one. So the desktop switch is read on every navigation,
    /// and no dead copy of the old hook is left to be edited by mistake.
    ///
    /// Asked by selector, because a Swift method that nearly matches an
    /// optional Objective-C requirement compiles with at most a warning and
    /// is then never called.
    func testTheSessionAnswersTheQuestionThatCarriesTheContentMode() {
        let session = makeSession()
        XCTAssertTrue(session.responds(
            to: NSSelectorFromString("webView:decidePolicyForNavigationAction:preferences:decisionHandler:")
        ))
        XCTAssertFalse(session.responds(
            to: NSSelectorFromString("webView:decidePolicyForNavigationAction:decisionHandler:")
        ))
    }

    // MARK: - The desktop switch

    /// With the switch off, WebKit's preferences go back exactly as they came
    /// in. That is all the Mac ever does: it already gets desktop pages.
    func testWithTheSwitchOffTheContentModeIsLeftAlone() {
        let preferences = WKWebpagePreferences()
        BrowserSession.applyContentMode(prefersDesktopSite: false, to: preferences)
        XCTAssertEqual(preferences.preferredContentMode, .recommended)
    }

    /// With it on, the site is asked for its desktop version.
    func testWithTheSwitchOnTheSiteIsAskedForItsDesktopVersion() {
        let preferences = WKWebpagePreferences()
        BrowserSession.applyContentMode(prefersDesktopSite: true, to: preferences)
        XCTAssertEqual(preferences.preferredContentMode, .desktop)
    }

    /// A tab starts with the switch off, and it turns on and off again.
    func testTheSwitchStartsOffAndTurnsOnAndOff() {
        let session = makeSession()
        XCTAssertFalse(session.prefersDesktopSite)

        session.setPrefersDesktopSite(true)
        XCTAssertTrue(session.prefersDesktopSite)

        session.setPrefersDesktopSite(false)
        XCTAssertFalse(session.prefersDesktopSite)
    }

    /// A throwaway session, on a defaults suite of its own that is emptied
    /// afterwards. `RecordingPlatform` and `NoDownloads` are the stand-ins
    /// this target's other tests already use.
    private func makeSession() -> BrowserSession {
        let suiteName = "clearframe.navigationPolicy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return BrowserSession(
            platform: RecordingPlatform(),
            downloadCenter: NoDownloads(),
            searchSettings: SearchSettingsStore(defaults: defaults)
        )
    }
}
```

- [ ] **Step 2: Run the tests to watch them fail**

Run: `cd macos/LimeghostBrowser && swift test --filter NavigationPolicyTests`

Expected: the build fails with errors like `type 'BrowserSession' has no member 'decide'`, `… 'applyContentMode'` and `value of type 'BrowserSession' has no member 'prefersDesktopSite'`.

- [ ] **Step 3: Add the switch**

In `BrowserSession.swift`, directly below `@Published public private(set) var pageNotice: String?` (line 117), add:

```swift
    /// Whether this tab asks sites for their desktop version: the phone's
    /// Request Desktop Site. Per tab, and for this run only. Nothing saves it,
    /// so a restored tab loads the ordinary version. The Mac never turns it
    /// on, because a Mac already gets desktop pages.
    @Published public private(set) var prefersDesktopSite = false
```

Directly after `reload()` (lines 426–428), add:

```swift
    /// Request Desktop Site and Request Mobile Site. Reloads, because the page
    /// on screen was fetched as the other version. The reload is a navigation,
    /// so it passes `decidePolicyFor`, which is where the switch is read. Not
    /// a door: it is the same page, asked for again.
    public func setPrefersDesktopSite(_ prefersDesktop: Bool) {
        guard prefersDesktop != prefersDesktopSite else { return }
        prefersDesktopSite = prefersDesktop
        reload()
    }
```

- [ ] **Step 4: Add the decision**

Directly above `extension BrowserSession: WKNavigationDelegate {` (line 992), add:

```swift
extension BrowserSession {
    /// What to do with a navigation WebKit is about to start: the page-load
    /// hook's decision, apart from WebKit, so each branch can be tested with
    /// plain values.
    enum NavigationActionDecision: Equatable {
        /// A link that asks to be saved rather than shown.
        case download
        /// A link aimed at a new window.
        case openInNewTab(URL?)
        /// Back onto this tab's own start page.
        case restoreStartSurface
        /// A main-frame address that is not a web page.
        case unsupported(URL)
        /// Let it load. `mainFrameURL` is the address when this is the page
        /// itself, and nil for a frame inside it.
        case allow(mainFrameURL: URL?)
    }

    /// The decision `webView(_:decidePolicyFor:preferences:decisionHandler:)`
    /// carries out, as a pure function of the four facts it reads.
    ///
    /// Downloads are asked about first, deliberately. `<a download
    /// href="blob:…">` is how a web app hands over a CSV or a PDF it built in
    /// the page, and a blob: or data: address is not a navigable web URL.
    /// Judging the scheme before asking WebKit what the link is for would
    /// refuse the file the user just asked to save.
    ///
    /// `targetFrameIsMain` is nil when the link has no target frame, which is
    /// a request for a new window.
    static func decide(
        shouldPerformDownload: Bool,
        targetFrameIsMain: Bool?,
        url: URL?
    ) -> NavigationActionDecision {
        if shouldPerformDownload { return .download }
        guard let targetFrameIsMain else { return .openInNewTab(url) }
        guard targetFrameIsMain, let url else { return .allow(mainFrameURL: nil) }
        guard let safeURL = WebURLPolicy.validatedURL(url) else {
            // Every tab opens on `loadHTMLString`, so its first back-forward
            // entry is `about:blank`. Going back onto that entry is a return
            // to this tab's start surface, not a link Limeghost cannot open.
            return isStartSurfaceURL(url) ? .restoreStartSurface : .unsupported(url)
        }
        return .allow(mainFrameURL: safeURL)
    }

    /// Asks the site for its desktop version while the switch is on, and
    /// otherwise leaves WebKit's preferences exactly as they came in.
    static func applyContentMode(prefersDesktopSite: Bool, to preferences: WKWebpagePreferences) {
        if prefersDesktopSite { preferences.preferredContentMode = .desktop }
    }
}
```

- [ ] **Step 5: Replace the delegate method**

In `extension BrowserSession: WKNavigationDelegate`, find the method that begins `public func webView(` at line 1119 and whose second parameter is `decidePolicyFor navigationAction: WKNavigationAction`. It ends at line 1162, just before the `decidePolicyFor navigationResponse` method. Replace the whole method with:

```swift
    /// WebKit asks this, and never the older form without `preferences`,
    /// once a delegate answers it (`WKNavigationDelegate.h`). The decision
    /// itself is `decide(…)`; this carries it out and hands WebKit its
    /// preferences back, with the desktop switch applied.
    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        Self.applyContentMode(prefersDesktopSite: prefersDesktopSite, to: preferences)
        switch Self.decide(
            shouldPerformDownload: navigationAction.shouldPerformDownload,
            targetFrameIsMain: navigationAction.targetFrame?.isMainFrame,
            url: navigationAction.request.url
        ) {
        case .download:
            decisionHandler(.download, preferences)
        case .openInNewTab(let url):
            requestNewTab(for: url)
            decisionHandler(.cancel, preferences)
        case .restoreStartSurface:
            // Let WebKit restore the document it already holds, and put the
            // chrome back on the start state.
            adoptStartPageEntry()
            decisionHandler(.allow, preferences)
        case .unsupported(let url):
            handleUnsupportedLink(url)
            decisionHandler(.cancel, preferences)
        case .allow(let mainFrameURL):
            if let mainFrameURL {
                isShowingStartPage = false
                lastRequestedURL = mainFrameURL
            }
            decisionHandler(.allow, preferences)
        }
    }
```

Compare the old method with `decide` and this `switch`, branch by branch, before going on.
- **Download:** `.download`, before anything else.
- **No target frame:** `requestNewTab` and `.cancel`.
- **Main frame, invalid URL:**
  - `about:blank` → `adoptStartPageEntry` and `.allow`.
  - Anything else → `handleUnsupportedLink` and `.cancel`.
- **Main frame, valid URL:** the two assignments, then `.allow`.
- **Everything else:** `.allow`.

- [ ] **Step 6: Run the tests to watch them pass**

Run: `cd macos/LimeghostBrowser && swift test --filter NavigationPolicyTests`

Expected: 10 tests, 0 failures.

- [ ] **Step 7: Break it on purpose, twice**

1. In `decide`, change `.unsupported(url)` to `.allow(mainFrameURL: nil)`, and run the filter again.
   Expected: `testAnAddressThatIsNotAWebPageIsUnsupported` fails. Restore the line.
2. In the delegate method, rename the argument label `preferences` to `settings`, keeping the parameter name, and run again.
   Expected: `testTheSessionAnswersTheQuestionThatCarriesTheContentMode` fails, and the compiler may warn that the method "nearly matches" the protocol requirement. Restore the label.

- [ ] **Step 8: Run every suite this change reaches**

Run all four commands from **Commands**. Expected:
- `swift test`: the Task 1 baseline plus 10 executed, 0 failures.
- `LimeghostSharedLayer` on both destinations: `** TEST SUCCEEDED **`. The test-list count is the baseline plus 10.
- The app: its baseline, 0 failures.

- [ ] **Step 9: Commit**

```bash
git add macos/LimeghostBrowser/Sources/LimeghostShared/BrowserSession.swift \
  macos/LimeghostBrowser/Tests/LimeghostSharedTests/NavigationPolicyTests.swift
git commit -m "Read the page-load hook as a decision, and give each tab a desktop switch"
```

End the message with the attribution lines your session's instructions give. That applies to every commit in this plan.

---

### Task 2: Reader's header for a finger, and Reader in the phone's build

**Files:**
- Modify: `macos/LimeghostBrowser/Sources/LimeghostBrowser/ReaderView.swift`. The whole file is replaced; the phone compiles it by reference.
- Modify: `macos/LimeghostBrowser/Tests/BrowserBehaviorTests/BrowserBehaviorTests.swift`. Add one test, directly after the closing brace of `testReaderRepeatsTheExtractorsDoubt` (which starts at line 466).
- Create: `ios/Tests/ReaderOnThePhoneTests.swift`
- Modify: `ios/Limeghost.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces:
  - `ReaderView.HeaderStyle`, with the cases `.pointer` and `.touch`.
  - `ReaderView(article:copy:close:headerStyle:)`, where `headerStyle` defaults to `.pointer`, so the Mac's call site is unchanged.
  - `ReaderView.Header(article:style:copy:close:)`, an internal nested `View`.

- [ ] **Step 1: Write the Mac's failing test**

In `BrowserBehaviorTests.swift`, directly after `testReaderRepeatsTheExtractorsDoubt`, add:

```swift
    /// Reader's header keeps the Mac's one row wherever the Mac draws it.
    ///
    /// The header has a second arrangement, two rows a finger can use, which
    /// the phone asks for by name. The break this catches is the Mac drawing
    /// the phone's rows, which would make its header grow for no reason. The
    /// pointer row must be the same height at two Mac widths, and shorter
    /// than the touch rows.
    func testReadersHeaderKeepsItsOneRowOnTheMac() throws {
        let article = try XCTUnwrap(ReaderArticle(page: PageSnapshot(
            title: "Title",
            url: "https://example.org/a",
            hostname: "example.org",
            scheme: "https",
            language: "en",
            text: "A sentence with enough words in it to be read as a page of prose rather than a fragment.",
            wordCount: 18,
            hasPasswordField: false,
            formActions: [],
            extractionConfidence: 0.9
        )))
        let pointer = ReaderView.Header(article: article, style: .pointer, copy: {}, close: {})
        let touch = ReaderView.Header(article: article, style: .touch, copy: {}, close: {})

        let typicalMac = try renderedHeight(of: pointer, width: 900)
        let widerStill = try renderedHeight(of: pointer, width: 1_600)

        XCTAssertEqual(typicalMac, widerStill, "the Mac's Reader header changed shape between two widths")
        XCTAssertLessThan(
            typicalMac,
            try renderedHeight(of: touch, width: 900),
            "the Mac is drawing the phone's header"
        )
    }
```

- [ ] **Step 2: Write the phone's failing test**

Create `ios/Tests/ReaderOnThePhoneTests.swift`:

```swift
import XCTest
import SwiftUI
import LimeghostCore
@testable import Limeghost
@testable import LimeghostShared

@MainActor
final class ReaderOnThePhoneTests: XCTestCase {
    /// An article the extractor is confident about, so no warning adds a
    /// third row to the header.
    private func article() throws -> ReaderArticle {
        try XCTUnwrap(ReaderArticle(page: PageSnapshot(
            title: "How owls fly without a sound",
            url: "https://example.com/owls",
            hostname: "example.com",
            scheme: "https",
            language: "en",
            text: "A barn owl can glide a few feet above a mouse without being heard. Its wings are not quieter by accident.",
            wordCount: 21,
            hasPasswordField: false,
            formActions: [],
            extractionConfidence: 0.9
        )))
    }

    // MARK: - The header

    /// Reader's header on a phone is two rows of 44 points, the smallest
    /// target Apple's guidelines give a finger, with 6 points above and
    /// below: 100 in all, at every phone width.
    ///
    /// The break this catches is the Mac's row on a phone. It fits at 428
    /// points, so a choice by width would pick it, and its buttons are 11- to
    /// 13-point text with no room around them. It also catches a row that
    /// wraps, which would make the header taller than 100.
    func testTheTouchHeaderIsTwoRowsAFingerCanUse() throws {
        let header = ReaderView.Header(article: try article(), style: .touch, copy: {}, close: {})
        for screenWidth in [375.0, 402.0, 428.0] {
            XCTAssertEqual(
                try renderedHeight(of: header, width: screenWidth),
                100,
                "on a \(Int(screenWidth))-point screen Reader's header is not two 44-point rows"
            )
        }
    }

    /// How tall a view draws at a given width, measured by rendering it.
    private func renderedHeight<Content: View>(of view: Content, width: CGFloat) throws -> CGFloat {
        let renderer = ImageRenderer(content: view.frame(width: width))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage, "the view did not render")
        return CGFloat(image.height)
    }
}
```

- [ ] **Step 3: Put `ReaderView.swift` and the test into the phone's project**

In `ios/Limeghost.xcodeproj/project.pbxproj`, add these lines, indented with tabs like their neighbours:

1. In `PBXBuildFile`, after the `…0675 /* BrandMark.swift in Sources */` line:
   ```
   		AA0000000000000000000677 /* ReaderView.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000667 /* ReaderView.swift */; };
   ```
   and after the `…2106 /* StartSurfaceTests.swift in Sources */` line:
   ```
   		AA0000000000000000002107 /* ReaderOnThePhoneTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000002207 /* ReaderOnThePhoneTests.swift */; };
   ```
2. In `PBXFileReference`, after the `…0666 /* limeghost-mark-small.png */` line:
   ```
   		AA0000000000000000000667 /* ReaderView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "../macos/LimeghostBrowser/Sources/LimeghostBrowser/ReaderView.swift"; sourceTree = "<group>"; };
   ```
   and after the `…2206 /* StartSurfaceTests.swift */` line:
   ```
   		AA0000000000000000002207 /* ReaderOnThePhoneTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ReaderOnThePhoneTests.swift; sourceTree = "<group>"; };
   ```
3. In the `Reused from macOS` group's `children`, after `AA0000000000000000000665 /* BrandMark.swift */,`:
   ```
   				AA0000000000000000000667 /* ReaderView.swift */,
   ```
   In the same group's comment, after the sentence that ends `…for \`BrandMark\` to find.`, add: `The page menu later brought Reader to the phone, so \`ReaderView.swift\` joined too; the phone asks for its touch header by name.`
4. In the `Tests` group's `children`, after `AA0000000000000000002206 /* StartSurfaceTests.swift */,`:
   ```
   				AA0000000000000000002207 /* ReaderOnThePhoneTests.swift */,
   ```
5. In the app's `Sources` phase (`…0A01`), after `AA0000000000000000000675 /* BrandMark.swift in Sources */,`:
   ```
   				AA0000000000000000000677 /* ReaderView.swift in Sources */,
   ```
6. In the tests' `Sources` phase (`…2A01`), after `AA0000000000000000002106 /* StartSurfaceTests.swift in Sources */,`:
   ```
   				AA0000000000000000002107 /* ReaderOnThePhoneTests.swift in Sources */,
   ```

- [ ] **Step 4: Run both tests to watch them fail**

Run: `cd macos/LimeghostBrowser && swift test --filter testReadersHeaderKeepsItsOneRowOnTheMac`

Expected: the build fails with `type 'ReaderView' has no member 'Header'`.

Run: `cd ios && xcodebuild test -scheme Limeghost -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LimeghostTests/ReaderOnThePhoneTests`

Expected: the build fails with `type 'ReaderView' has no member 'Header'`.

This run is also the first iOS compile of today's `ReaderView.swift`. If the phone's build names anything else, for example an API iOS lacks, that is the portability check the spec's §4 asks for. Fix it portably in `ReaderView.swift` before going on, and say so in the commit message.

- [ ] **Step 5: Replace `ReaderView.swift`**

Replace the whole of `macos/LimeghostBrowser/Sources/LimeghostBrowser/ReaderView.swift` with:

```swift
import LimeghostCore
import LimeghostShared
import SwiftUI

/// The page's own words, with the site's furniture removed.
///
/// Not a prettier rendering of the page: it is the extractor's output, drawn.
/// No images, no links, no reconstructed headings — adding any of those would
/// mean Reader and the assistant were looking at different things, and the one
/// thing this view is for is letting somebody see what the assistant will get.
///
/// It is also the only place extraction is visible at all. Everywhere else the
/// text goes straight to a clipboard, so a page the extractor reads badly used
/// to surface as a strange answer from an assistant with nothing to point at.
///
/// The iPhone app compiles this file by reference, so a change here is built
/// and tested on the phone too.
struct ReaderView: View {
    /// How the header is laid out. The caller chooses, rather than the width,
    /// because what differs is the pointer, not the space. The Mac's row fits
    /// a 428-point phone, and its 11- to 13-point buttons are still far too
    /// small for a finger.
    enum HeaderStyle {
        /// The Mac's single row, sized for a mouse.
        case pointer
        /// The phone's two rows of 44 points.
        case touch
    }

    let article: ReaderArticle
    let copy: () -> Void
    let close: () -> Void
    var headerStyle: HeaderStyle = .pointer

    /// The measure below is a reading column, not the window. Long lines are
    /// the thing reader modes exist to fix, and a paragraph the full width of a
    /// 2560-point display is worse to read than the page it replaced.
    private static let column: CGFloat = 680

    var body: some View {
        VStack(spacing: 0) {
            Header(article: article, style: headerStyle, copy: copy, close: close)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(article.title)
                        .font(.system(size: 30, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 4)

                    ForEach(Array(article.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(.system(size: 16))
                            .lineSpacing(6)
                            .foregroundStyle(LimeghostTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: Self.column, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 32)
                .padding(.vertical, 36)
            }
        }
        .background(LimeghostTheme.bg1)
    }

    /// What the page is, how much of it there is, and the two things to do
    /// with it. A nested type so a test can render it at a given width, as
    /// `AIToolStartPage.Header` is rendered.
    struct Header: View {
        let article: ReaderArticle
        let style: HeaderStyle
        let copy: () -> Void
        let close: () -> Void

        /// Briefly true after a copy. The toolbar icon used to carry this
        /// confirmation and no longer exists, so it moved to the button that
        /// replaced it — still a changed glyph rather than a sentence, because a
        /// sentence on every copy is one nobody reads by the third time.
        @State private var didCopy = false

        var body: some View {
            switch style {
            case .pointer: pointerRow
            case .touch: touchRows
            }
        }

        /// The Mac's arrangement, as it was before the phone needed a second one.
        private var pointerRow: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.plaintext")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LimeghostTheme.accent)
                    Text("Reader")
                        .font(.system(size: 13, weight: .semibold))
                    Text(article.host)
                        .font(.system(size: 12))
                        .foregroundStyle(LimeghostTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 12)

                    // Says what the assistant would receive, in the words the
                    // clipboard header uses, so the two never describe the same
                    // page differently.
                    Text("\(article.words) words · \(article.readingMinutes) min")
                        .font(.system(size: 11))
                        .foregroundStyle(LimeghostTheme.textTertiary)

                    Button(action: copyAndConfirm) {
                        Label(
                            didCopy ? "Copied" : "Copy for AI",
                            systemImage: didCopy ? "checkmark" : "doc.on.doc"
                        )
                        .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(didCopy ? LimeghostTheme.accent : LimeghostTheme.textPrimary)
                    .help("Copy this exact text, with its title and address, for pasting into an assistant (⇧⌘C)")

                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .help("Close Reader and go back to the page")
                    .accessibilityLabel("Close Reader")
                }

                if let warning = article.extractionWarning {
                    warningRow(warning, size: 11)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(LimeghostTheme.bg2)
        }

        /// A phone's arrangement: the same things, in two rows of 44 points,
        /// the smallest target Apple's guidelines give a finger. Each button's
        /// touch area fills its row, around the smaller shape drawn.
        private var touchRows: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.plaintext")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(LimeghostTheme.accent)
                    Text("Reader")
                        .font(.system(size: 15, weight: .semibold))
                    Text(article.host)
                        .font(.system(size: 13))
                        .foregroundStyle(LimeghostTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 12)

                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(LimeghostTheme.textSecondary)
                            .frame(width: 30, height: 30)
                            .background(LimeghostTheme.bg3, in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close Reader")
                }
                .frame(minHeight: 44)

                HStack(spacing: 10) {
                    Text("\(article.words) words · \(article.readingMinutes) min")
                        .font(.system(size: 13))
                        .foregroundStyle(LimeghostTheme.textTertiary)

                    Spacer(minLength: 12)

                    Button(action: copyAndConfirm) {
                        Label {
                            Text(didCopy ? "Copied" : "Copy for AI")
                                .foregroundStyle(didCopy ? LimeghostTheme.accent : LimeghostTheme.textPrimary)
                        } icon: {
                            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                                .foregroundStyle(LimeghostTheme.accent)
                        }
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(LimeghostTheme.bg3, in: Capsule())
                        .frame(height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(minHeight: 44)

                if let warning = article.extractionWarning {
                    warningRow(warning, size: 13)
                        .padding(.bottom, 8)
                }
            }
            .foregroundStyle(LimeghostTheme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(LimeghostTheme.bg2)
        }

        private func warningRow(_ warning: String, size: CGFloat) -> some View {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(.orange)
                Text(warning)
                    .font(.system(size: size))
                    .foregroundStyle(LimeghostTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        private func copyAndConfirm() {
            copy()
            didCopy = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                didCopy = false
            }
        }
    }
}
```

- [ ] **Step 6: Run both tests to watch them pass**

Run the two commands from Step 4 again. Expected: the Mac test passes, and the phone test passes, reporting 100 at all three widths.

- [ ] **Step 7: Break it on purpose**

In `Header.body`, make the `.touch` case draw `pointerRow`, then run both tests again. Expected:
- The phone test fails: the height is well under 100.
- The Mac test fails: "the Mac is drawing the phone's header" no longer holds.

Restore the `.touch` case.

- [ ] **Step 8: Check the Mac's row did not change**

Run: `git diff --color-moved=dimmed-zebra -- macos/LimeghostBrowser/Sources/LimeghostBrowser/ReaderView.swift`

Expected: the pointer row's lines show as moved. Inside it, only two lines change:
- the copy button's action, now `copyAndConfirm`;
- the warning block, now `warningRow(warning, size: 11)`.

Every font, colour, padding and help text is the same as before.

- [ ] **Step 9: Run every suite this change reaches**

`ReaderView.swift` is in the Mac app target, and the phone compiles it. Run `swift test` and the phone's suite. Expected: both pass, at the previous numbers plus 1 each.

- [ ] **Step 10: Commit**

```bash
git add macos/LimeghostBrowser/Sources/LimeghostBrowser/ReaderView.swift \
  macos/LimeghostBrowser/Tests/BrowserBehaviorTests/BrowserBehaviorTests.swift \
  ios/Tests/ReaderOnThePhoneTests.swift ios/Limeghost.xcodeproj/project.pbxproj
git commit -m "Give Reader a header a finger can use, and build Reader into the phone"
```

---

### Task 3: What the page menu offers

**Files:**
- Create: `ios/Sources/PageMenu.swift`
- Create: `ios/Tests/PageMenuTests.swift`
- Modify: `ios/Limeghost.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes:
  - From Task 1: `BrowserSession.prefersDesktopSite`.
  - Already there: `BrowserTab.readerArticle`, `BrowserWorkspace.canShareSelectedPage`, `.canGoForwardInSelectedTab` and `.dataStore.isBookmarked(_:)`.
- Produces:
  - `enum PageMenuItem: CaseIterable, Hashable`, with ten cases in display order.
  - `struct PageMenuModel: Equatable`, with the memberwise initialiser `(hasPage:canGoForward:isBookmarked:prefersDesktopSite:isReaderOpen:)`.
  - `@MainActor init(workspace: BrowserWorkspace)`.
  - `func isEnabled(_ item: PageMenuItem) -> Bool`, `func title(_ item: PageMenuItem) -> String` and `func symbol(_ item: PageMenuItem) -> String`.

- [ ] **Step 1: Write the failing tests**

Create `ios/Tests/PageMenuTests.swift`:

```swift
import XCTest
import LimeghostCore
@testable import Limeghost
@testable import LimeghostShared

@MainActor
final class PageMenuTests: XCTestCase {
    /// A suite of its own, emptied afterwards, for the reason
    /// `StartSurfaceTests.makeHost()` gives: these tests run inside the app.
    private func makeHost() throws -> WorkspaceHost {
        let suiteName = "clearframe.iosPageMenu.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return WorkspaceHost.forTesting(defaults: defaults)
    }

    /// A model on a page, with nothing else true, unless a test says otherwise.
    private func model(
        hasPage: Bool = true,
        canGoForward: Bool = false,
        isBookmarked: Bool = false,
        prefersDesktopSite: Bool = false,
        isReaderOpen: Bool = false
    ) -> PageMenuModel {
        PageMenuModel(
            hasPage: hasPage,
            canGoForward: canGoForward,
            isBookmarked: isBookmarked,
            prefersDesktopSite: prefersDesktopSite,
            isReaderOpen: isReaderOpen
        )
    }

    // MARK: - What the menu offers

    /// On the AI guide there is no page to act on. Only the two rows that
    /// open a new tab work. The rest stay in place, greyed, and light up
    /// when a page opens.
    func testOnTheGuideOnlyTheNewTabRowsWork() {
        let guide = model(hasPage: false)
        XCTAssertEqual(PageMenuItem.allCases.filter(guide.isEnabled), [.newTab, .newPrivateTab])
    }

    /// On a page every row works except Forward, while there is nowhere to
    /// go forward to.
    func testOnAPageEverythingWorksButForward() {
        let page = model()
        XCTAssertEqual(PageMenuItem.allCases.filter { !page.isEnabled($0) }, [.forward])
    }

    /// Forward follows the tab: back on the guide, the page to go forward to
    /// is still there.
    func testForwardFollowsTheTab() {
        XCTAssertTrue(model(canGoForward: true).isEnabled(.forward))
        XCTAssertTrue(model(hasPage: false, canGoForward: true).isEnabled(.forward))
    }

    /// Find in Page searches the page, and Reader covers it, so a match would
    /// be highlighted where nobody can see it. Reader itself stays available,
    /// to be closed.
    func testFindWaitsWhileReaderCoversThePage() {
        let reading = model(isReaderOpen: true)
        XCTAssertFalse(reading.isEnabled(.find))
        XCTAssertTrue(reading.isEnabled(.reader))
    }

    /// The labels that change say what a tap will do next.
    func testTheLabelsSayWhatATapWillDoNext() {
        XCTAssertEqual(model().title(.bookmark), "Add Bookmark")
        XCTAssertEqual(model(isBookmarked: true).title(.bookmark), "Remove Bookmark")
        XCTAssertEqual(model(isBookmarked: true).symbol(.bookmark), "star.fill")

        XCTAssertEqual(model().title(.desktopSite), "Request Desktop Site")
        XCTAssertEqual(model(prefersDesktopSite: true).title(.desktopSite), "Request Mobile Site")
        XCTAssertEqual(model(prefersDesktopSite: true).symbol(.desktopSite), "iphone")

        XCTAssertEqual(model().title(.reader), "Reader")
        XCTAssertEqual(model(isReaderOpen: true).title(.reader), "Close Reader")
    }

    /// The model reads the tab in front, not a copy of it.
    func testTheModelReadsTheTabInFront() throws {
        let host = try makeHost()
        XCTAssertFalse(PageMenuModel(workspace: host.workspace).hasPage, "a fresh tab is on the guide, with no page")

        host.workspace.open("https://example.com/")
        host.workspace.toggleBookmarkForSelectedTab()
        let onAPage = PageMenuModel(workspace: host.workspace)

        XCTAssertTrue(onAPage.hasPage)
        XCTAssertTrue(onAPage.isBookmarked)
        XCTAssertFalse(onAPage.prefersDesktopSite)
        XCTAssertFalse(onAPage.isReaderOpen)
    }
}
```

- [ ] **Step 2: Put the test file into the project, and watch it fail**

In `project.pbxproj`, with tabs:

1. `PBXBuildFile`, after the `…2107 /* ReaderOnThePhoneTests.swift in Sources */` line:
   ```
   		AA0000000000000000002108 /* PageMenuTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000002208 /* PageMenuTests.swift */; };
   ```
2. `PBXFileReference`, after the `…2207 /* ReaderOnThePhoneTests.swift */` line:
   ```
   		AA0000000000000000002208 /* PageMenuTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PageMenuTests.swift; sourceTree = "<group>"; };
   ```
3. The `Tests` group's `children`, after `…2207 /* ReaderOnThePhoneTests.swift */,`:
   ```
   				AA0000000000000000002208 /* PageMenuTests.swift */,
   ```
4. The tests' `Sources` phase, after `…2107 /* ReaderOnThePhoneTests.swift in Sources */,`:
   ```
   				AA0000000000000000002108 /* PageMenuTests.swift in Sources */,
   ```

Run: `cd ios && xcodebuild test -scheme Limeghost -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LimeghostTests/PageMenuTests`

Expected: the build fails with `cannot find 'PageMenuModel' in scope` and `cannot find 'PageMenuItem' in scope`.

- [ ] **Step 3: Write the model**

Create `ios/Sources/PageMenu.swift`:

```swift
import LimeghostShared
import SwiftUI

/// Everything the page menu offers, in the order it shows them: the two large
/// buttons, then the two cards.
enum PageMenuItem: CaseIterable, Hashable {
    case reader, copyForAI
    case reload, forward, newTab, newPrivateTab
    case bookmark, find, share, desktopSite
}

/// What the menu shows, apart from how it draws, so a test can read it without
/// standing up SwiftUI — as `BottomBarTests` read `BottomBarModel`.
struct PageMenuModel: Equatable {
    /// A web page is open in the tab in front: not the AI guide, not an empty tab.
    var hasPage: Bool
    var canGoForward: Bool
    var isBookmarked: Bool
    var prefersDesktopSite: Bool
    var isReaderOpen: Bool

    func isEnabled(_ item: PageMenuItem) -> Bool {
        switch item {
        case .newTab, .newPrivateTab:
            return true
        case .forward:
            return canGoForward
        case .find:
            // Find searches the page, and Reader covers it: a match would be
            // highlighted where nobody can see it.
            return hasPage && !isReaderOpen
        case .reader, .copyForAI, .reload, .bookmark, .share, .desktopSite:
            return hasPage
        }
    }

    /// Title case, as Apple's guidelines give menu items, and the Mac's own
    /// menu names where it has one. The three that change say what a tap will
    /// do next.
    func title(_ item: PageMenuItem) -> String {
        switch item {
        case .reader: return isReaderOpen ? "Close Reader" : "Reader"
        case .copyForAI: return "Copy for AI"
        case .reload: return "Reload"
        case .forward: return "Forward"
        case .newTab: return "New Tab"
        case .newPrivateTab: return "New Private Tab"
        case .bookmark: return isBookmarked ? "Remove Bookmark" : "Add Bookmark"
        case .find: return "Find in Page"
        case .share: return "Share"
        case .desktopSite: return prefersDesktopSite ? "Request Mobile Site" : "Request Desktop Site"
        }
    }

    /// System symbols. Reader's is the Mac's Reader header's, and New Private
    /// Tab's is the tab switcher's Private section's.
    func symbol(_ item: PageMenuItem) -> String {
        switch item {
        case .reader: return "doc.plaintext"
        case .copyForAI: return "doc.on.doc"
        case .reload: return "arrow.clockwise"
        case .forward: return "chevron.forward"
        case .newTab: return "plus.square.on.square"
        case .newPrivateTab: return "eye.slash"
        case .bookmark: return isBookmarked ? "star.fill" : "star"
        case .find: return "magnifyingglass"
        case .share: return "square.and.arrow.up"
        case .desktopSite: return prefersDesktopSite ? "iphone" : "desktopcomputer"
        }
    }
}

extension PageMenuModel {
    /// The menu as the tab in front stands now. SwiftUI rebuilds it whenever
    /// the workspace changes, and every row closes the sheet, so it never has
    /// to follow a change of its own.
    @MainActor
    init(workspace: BrowserWorkspace) {
        let tab = workspace.selectedTab
        self.init(
            hasPage: workspace.canShareSelectedPage,
            canGoForward: workspace.canGoForwardInSelectedTab,
            isBookmarked: tab.map { workspace.dataStore.isBookmarked($0.session.currentURLString) } ?? false,
            prefersDesktopSite: tab?.session.prefersDesktopSite ?? false,
            isReaderOpen: tab?.readerArticle != nil
        )
    }
}
```

Then add it to `project.pbxproj`, with tabs:

1. `PBXBuildFile`, after the `…010B /* IOSBrandMarkArtwork.swift in Sources */` line:
   ```
   		AA000000000000000000010C /* PageMenu.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA000000000000000000020D /* PageMenu.swift */; };
   ```
2. `PBXFileReference`, after the `…020C /* IOSBrandMarkArtwork.swift */` line:
   ```
   		AA000000000000000000020D /* PageMenu.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PageMenu.swift; sourceTree = "<group>"; };
   ```
3. The `Sources` group's `children`, after `…020C /* IOSBrandMarkArtwork.swift */,`:
   ```
   				AA000000000000000000020D /* PageMenu.swift */,
   ```
4. The app's `Sources` phase, after `…010B /* IOSBrandMarkArtwork.swift in Sources */,`:
   ```
   				AA000000000000000000010C /* PageMenu.swift in Sources */,
   ```

- [ ] **Step 4: Run the tests to watch them pass**

Run the Step 2 command. Expected: 6 tests, 0 failures.

- [ ] **Step 5: Break it on purpose**

Make `.find` return `hasPage` alone. Expected: `testFindWaitsWhileReaderCoversThePage` fails. Restore it.

- [ ] **Step 6: Run the phone's suite**

Run the phone's suite. Expected: the previous count plus 6, and 0 failures.

- [ ] **Step 7: Commit**

```bash
git add ios/Sources/PageMenu.swift ios/Tests/PageMenuTests.swift ios/Limeghost.xcodeproj/project.pbxproj
git commit -m "Say what the phone's page menu offers"
```

---

### Task 4: What the rows do, and the two shared pieces they need

**Files:**
- Modify: `macos/LimeghostBrowser/Sources/LimeghostShared/ReaderArticle.swift`. Add `copyConfirmation` after `copyNotice`, which ends at line 62.
- Modify: `macos/LimeghostBrowser/Sources/LimeghostShared/BrowserWorkspace.swift`:
  - `copySelectedPageForAI()` (lines 700–720);
  - a new method after `goForwardInSelectedTab()` (1483–1486).
- Modify: `macos/LimeghostBrowser/Tests/BrowserBehaviorTests/BrowserBehaviorTests.swift`. Add one test after the one from Task 2.
- Modify: `ios/Sources/PageMenu.swift` and `ios/Tests/PageMenuTests.swift`.

**Interfaces:**
- Consumes:
  - From Task 3: `PageMenuItem`.
  - From Task 1: `BrowserSession.setPrefersDesktopSite(_:)` and `prefersDesktopSite`.
- Produces:
  - `public var ReaderArticle.copyConfirmation: String`.
  - `@discardableResult public func copySelectedPageForAI() async -> ReaderArticle?`.
  - `public func toggleDesktopSiteInSelectedTab()`.
  - `@MainActor struct PageMenuActions`, with `let workspace: BrowserWorkspace`, `func perform(_ item: PageMenuItem) async`, `func copyForAI() async` and `func toggleBookmark()`.

- [ ] **Step 1: Write the Mac's failing test**

In `BrowserBehaviorTests.swift`, after `testReadersHeaderKeepsItsOneRowOnTheMac`, add:

```swift
    /// The phone's menu closes as it copies, so the phone confirms each copy in
    /// words. A doubtful copy says exactly what the Mac's own notice says. A
    /// clean one says how much went onto the clipboard, and claims nothing
    /// about the text that it cannot back.
    func testCopyConfirmationSaysWhatWasCopied() throws {
        func page(confidence: Double?) -> PageSnapshot {
            PageSnapshot(
                title: "Title",
                url: "https://example.org/a",
                hostname: "example.org",
                scheme: "https",
                language: "en",
                text: "A sentence with enough words in it to be read as a page of prose rather than a fragment.",
                wordCount: 18,
                hasPasswordField: false,
                formActions: [],
                extractionConfidence: confidence
            )
        }

        let confident = try XCTUnwrap(ReaderArticle(page: page(confidence: 0.9)))
        XCTAssertEqual(confident.copyConfirmation, "Copied \(confident.words) words.")

        let noArticle = try XCTUnwrap(ReaderArticle(page: page(confidence: 0)))
        XCTAssertEqual(noArticle.copyConfirmation, noArticle.copyNotice)
    }
```

- [ ] **Step 2: Write the phone's failing tests**

In `ios/Tests/PageMenuTests.swift`, add these before the class's closing brace:

```swift
    // MARK: - What the rows do

    /// New Private Tab puts a private tab in front, through the workspace's
    /// own door.
    func testNewPrivateTabPutsAPrivateTabInFront() async throws {
        let host = try makeHost()
        await PageMenuActions(workspace: host.workspace).perform(.newPrivateTab)
        XCTAssertEqual(host.workspace.selectedTab?.isPrivate, true)
    }

    /// Add Bookmark saves the page and says so. The phone has no star to show it.
    func testAddBookmarkSavesThePageAndSaysSo() async throws {
        let host = try makeHost()
        host.workspace.open("https://example.com/")

        await PageMenuActions(workspace: host.workspace).perform(.bookmark)

        XCTAssertTrue(host.workspace.dataStore.isBookmarked("https://example.com/"))
        XCTAssertEqual(host.workspace.selectedTab?.session.pageNotice, "Bookmark added.")
    }

    /// The same row on a saved page removes it, and says that instead.
    func testRemoveBookmarkRemovesItAndSaysSo() async throws {
        let host = try makeHost()
        host.workspace.open("https://example.com/")
        let actions = PageMenuActions(workspace: host.workspace)

        await actions.perform(.bookmark)
        await actions.perform(.bookmark)

        XCTAssertFalse(host.workspace.dataStore.isBookmarked("https://example.com/"))
        XCTAssertEqual(host.workspace.selectedTab?.session.pageNotice, "Bookmark removed.")
    }

    /// Request Desktop Site turns the switch on in the tab in front, and the
    /// same row turns it off again.
    func testRequestDesktopSiteTurnsTheTabsSwitchOnAndOff() async throws {
        let host = try makeHost()
        host.workspace.open("https://example.com/")
        let actions = PageMenuActions(workspace: host.workspace)

        await actions.perform(.desktopSite)
        XCTAssertEqual(host.workspace.selectedTab?.session.prefersDesktopSite, true)

        await actions.perform(.desktopSite)
        XCTAssertEqual(host.workspace.selectedTab?.session.prefersDesktopSite, false)
    }

    /// Find in Page opens the find bar.
    func testFindInPageOpensTheFindBar() async throws {
        let host = try makeHost()
        host.workspace.open("https://example.com/")

        await PageMenuActions(workspace: host.workspace).perform(.find)

        XCTAssertEqual(host.workspace.selectedTab?.find.isPresented, true)
    }

    /// Nothing copied, nothing confirmed. A tab with no page cannot be copied,
    /// and `readCurrentPage` has already said why. A confirmation on top would
    /// claim a copy that never happened.
    func testACopyThatDidNotHappenIsNotConfirmed() async throws {
        let host = try makeHost()

        await PageMenuActions(workspace: host.workspace).perform(.copyForAI)

        XCTAssertEqual(
            host.workspace.selectedTab?.session.pageNotice,
            "There is no web page in this tab to copy."
        )
    }
```

- [ ] **Step 3: Run both to watch them fail**

Run: `cd macos/LimeghostBrowser && swift test --filter testCopyConfirmationSaysWhatWasCopied`

Expected: the build fails with `value of type 'ReaderArticle' has no member 'copyConfirmation'`.

Run: `cd ios && xcodebuild test -scheme Limeghost -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LimeghostTests/PageMenuTests`

Expected: the build fails with `cannot find 'PageMenuActions' in scope`.

- [ ] **Step 4: Write the shared pieces**

In `ReaderArticle.swift`, directly after the closing brace of `copyNotice` (line 62), add:

```swift
    /// What the phone says after Copy for AI from its menu. The menu closes as
    /// it copies, and iOS says nothing when an app writes to the clipboard, so
    /// without a sentence there is no sign the copy happened. A doubtful copy
    /// keeps `copyNotice`'s words. A clean one says how much was copied. The
    /// Mac shows `copyNotice` alone, and deliberately says nothing about a
    /// clean copy.
    public var copyConfirmation: String {
        copyNotice ?? "Copied \(words) words."
    }
```

In `BrowserWorkspace.swift`, replace `copySelectedPageForAI()` (lines 710–720) with the version below. Keep its doc comment (lines 700–709), and add a paragraph to that comment:

```swift
    ///
    /// Returns the article it copied, or nil when nothing was copied and
    /// `readCurrentPage` has already said why. The phone's menu uses the
    /// article to confirm the copy in words; the Mac's command discards it.
    @discardableResult
    public func copySelectedPageForAI() async -> ReaderArticle? {
        guard let tab = selectedTab else { return nil }
        let article: ReaderArticle?
        if let open = tab.readerArticle {
            article = open
        } else {
            article = await tab.readCurrentPage(verb: "copy")
        }
        guard let article else { return nil }
        tab.copyArticleForAI(article)
        return article
    }
```

In the same file, directly after `goForwardInSelectedTab()` (lines 1483–1486), add:

```swift
    /// Request Desktop Site and Request Mobile Site, from the phone's page
    /// menu. The Mac has no such command: it already gets desktop pages.
    public func toggleDesktopSiteInSelectedTab() {
        guard let session = selectedTab?.session else { return }
        session.setPrefersDesktopSite(!session.prefersDesktopSite)
    }
```

- [ ] **Step 5: Write the actions**

At the end of `ios/Sources/PageMenu.swift`, add:

```swift
/// What each row does, as named methods rather than closures in the view, so
/// a test can call them. An inline closure is invisible to tests, which is the
/// lesson `StartSurfaceScreen.openTool` recorded.
@MainActor
struct PageMenuActions {
    let workspace: BrowserWorkspace

    func perform(_ item: PageMenuItem) async {
        switch item {
        case .reader: await workspace.toggleReaderInSelectedTab()
        case .copyForAI: await copyForAI()
        case .reload: workspace.reloadSelectedTab()
        case .forward: workspace.goForwardInSelectedTab()
        case .newTab: workspace.addTab()
        case .newPrivateTab: workspace.addTab(isPrivate: true)
        case .bookmark: toggleBookmark()
        case .find: workspace.findInSelectedTab()
        case .share: workspace.shareSelectedPage()
        case .desktopSite: workspace.toggleDesktopSiteInSelectedTab()
        }
    }

    /// The menu closes as it copies, so the phone says what went onto the
    /// clipboard. A copy that did not happen has already said why, through
    /// `readCurrentPage`, and gets no confirmation on top.
    func copyForAI() async {
        guard let article = await workspace.copySelectedPageForAI() else { return }
        workspace.selectedTab?.session.showPageNotice(article.copyConfirmation)
    }

    /// The shared toggle says nothing, and the phone has no star to show the
    /// change, so the phone says it in words. It says only what actually
    /// changed, read from the store before and after: an address the store
    /// refuses changes nothing and is claimed as nothing.
    func toggleBookmark() {
        guard let tab = workspace.selectedTab else { return }
        let address = tab.session.currentURLString
        let wasSaved = workspace.dataStore.isBookmarked(address)
        workspace.toggleBookmarkForSelectedTab()
        let isSaved = workspace.dataStore.isBookmarked(address)
        guard isSaved != wasSaved else { return }
        tab.session.showPageNotice(isSaved ? "Bookmark added." : "Bookmark removed.")
    }
}
```

- [ ] **Step 6: Run both to watch them pass**

Run the two commands from Step 3. Expected:
- The Mac test passes.
- `PageMenuTests` passes 12 tests: 6 from Task 3 and 6 new.

- [ ] **Step 7: Break it on purpose**

In `toggleBookmark()`, swap the two notices. Expected: both bookmark tests fail. Restore them.

- [ ] **Step 8: Run every suite this change reaches**

The shared layer changed, so run all four commands from **Commands**. Expected:
- `swift test`: the previous count plus 1.
- `LimeghostSharedLayer`: `** TEST SUCCEEDED **` on both destinations, with an unchanged list count, since no shared test was added.
- The phone: the previous count plus 6.

- [ ] **Step 9: Commit**

```bash
git add macos/LimeghostBrowser/Sources/LimeghostShared/ReaderArticle.swift \
  macos/LimeghostBrowser/Sources/LimeghostShared/BrowserWorkspace.swift \
  macos/LimeghostBrowser/Tests/BrowserBehaviorTests/BrowserBehaviorTests.swift \
  ios/Sources/PageMenu.swift ios/Tests/PageMenuTests.swift
git commit -m "Make the page menu's rows act, and confirm a copy in words"
```

---

### Task 5: The sheet, opened from the bottom bar

**Files:**
- Modify: `ios/Sources/PageMenu.swift`. Add `PageMenuPresentation`, the `PageMenu` view, and `PageMenuHeightKey`.
- Modify: `ios/Sources/BottomBar.swift` and `ios/Sources/BrowserScreen.swift`.
- Modify: `ios/Tests/PageMenuTests.swift`.

**Interfaces:**
- Consumes: from Task 3, `PageMenuItem` and `PageMenuModel`; from Task 4, `PageMenuActions`.
- Produces:
  - `struct PageMenuPresentation`, with `var isPresented`, `private(set) var chosen: PageMenuItem?`, `mutating func open()`, `mutating func choose(_:)` and `mutating func didDismiss() -> PageMenuItem?`.
  - `struct PageMenu: View`, initialised as `PageMenu(model:choose:height:)`, where `height` is a `Binding<CGFloat>`.
  - `BottomBar(model:goBack:openAddress:openTabs:openMenu:)`.

- [ ] **Step 1: Write the failing tests**

In `PageMenuTests.swift`, before the class's closing brace, add:

```swift
    // MARK: - When a row acts

    /// A tapped row closes the sheet and waits: it runs once the sheet has
    /// gone. Share is why. It presents the system's sheet from the window's
    /// root view controller, which cannot present anything while this one is
    /// still up.
    func testARowClosesTheSheetBeforeItActs() {
        var presentation = PageMenuPresentation()
        presentation.open()
        XCTAssertTrue(presentation.isPresented)

        presentation.choose(.share)

        XCTAssertFalse(presentation.isPresented)
        XCTAssertEqual(presentation.didDismiss(), .share)
    }

    /// A row runs once. The sheet closing again later runs nothing.
    func testARowActsOnlyOnce() {
        var presentation = PageMenuPresentation()
        presentation.open()
        presentation.choose(.reload)
        _ = presentation.didDismiss()

        XCTAssertNil(presentation.didDismiss())
    }

    /// Swiping the sheet away chooses nothing, and runs nothing.
    func testSwipingTheSheetAwayRunsNothing() {
        var presentation = PageMenuPresentation()
        presentation.open()
        presentation.isPresented = false

        XCTAssertNil(presentation.didDismiss())
    }
```

- [ ] **Step 2: Run them to watch them fail**

Run the `PageMenuTests` command.

Expected: the build fails with `cannot find 'PageMenuPresentation' in scope`.

- [ ] **Step 3: Write the presentation**

In `PageMenu.swift`, after `PageMenuModel`'s extension, add:

```swift
/// The menu's one rule about timing: a row closes the sheet first, and acts
/// once the sheet has gone. `IOSPageSharing.share` presents the system's share
/// sheet from the window's root view controller, which cannot present anything
/// while this sheet is still up. The find bar's keyboard and Reader want a
/// clear screen too.
struct PageMenuPresentation {
    var isPresented = false
    private(set) var chosen: PageMenuItem?

    mutating func open() {
        chosen = nil
        isPresented = true
    }

    /// A row was tapped: remember it, and close.
    mutating func choose(_ item: PageMenuItem) {
        chosen = item
        isPresented = false
    }

    /// The sheet has gone. Hands back the row to act on, once.
    mutating func didDismiss() -> PageMenuItem? {
        defer { chosen = nil }
        return chosen
    }
}
```

- [ ] **Step 4: Run them to watch them pass, then break one**

Run the `PageMenuTests` command. Expected: 15 tests, 0 failures.

Then remove the `defer` line from `didDismiss()`. Expected: `testARowActsOnlyOnce` fails. Restore the line.

- [ ] **Step 5: Draw the menu**

At the end of `PageMenu.swift`, add:

```swift
/// The page menu: two large buttons, then two cards of rows, on the plane's
/// colour. Every row closes the sheet; `PageMenuPresentation` runs it after.
struct PageMenu: View {
    let model: PageMenuModel
    let choose: (PageMenuItem) -> Void
    /// The height the rows need, reported up so the sheet opens exactly that
    /// tall. At half height, the last rows would open below the fold.
    @Binding var height: CGFloat

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    tile(.reader)
                    tile(.copyForAI)
                }
                card([.reload, .forward, .newTab, .newPrivateTab])
                    .padding(.top, 20)
                card([.bookmark, .find, .share, .desktopSite])
                    .padding(.top, 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 16)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: PageMenuHeightKey.self, value: proxy.size.height)
                }
            )
        }
        .scrollBounceBehavior(.basedOnSize)
        .onPreferenceChange(PageMenuHeightKey.self) { height = $0 }
    }

    /// One of the two large buttons: Reader, and Copy for AI, always labelled.
    private func tile(_ item: PageMenuItem) -> some View {
        let enabled = model.isEnabled(item)
        return Button { choose(item) } label: {
            VStack(spacing: 8) {
                Image(systemName: model.symbol(item))
                    .font(.system(size: 22))
                    .foregroundStyle(enabled ? LimeghostTheme.accent : LimeghostTheme.textTertiary)
                Text(model.title(item))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(enabled ? LimeghostTheme.textPrimary : LimeghostTheme.textTertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(
                LimeghostTheme.bg2,
                in: RoundedRectangle(cornerRadius: LimeghostTheme.radius12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LimeghostTheme.radius12, style: .continuous)
                    .stroke(LimeghostTheme.hairline2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func card(_ items: [PageMenuItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(LimeghostTheme.hairline2)
                        .frame(height: 1)
                        .padding(.leading, 16)
                }
                row(item)
            }
        }
        .background(
            LimeghostTheme.bg2,
            in: RoundedRectangle(cornerRadius: LimeghostTheme.radius12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LimeghostTheme.radius12, style: .continuous)
                .stroke(LimeghostTheme.hairline2)
        )
    }

    private func row(_ item: PageMenuItem) -> some View {
        let enabled = model.isEnabled(item)
        return Button { choose(item) } label: {
            HStack(spacing: 12) {
                Text(model.title(item))
                    .font(.body)
                    .foregroundStyle(enabled ? LimeghostTheme.textPrimary : LimeghostTheme.textTertiary)
                Spacer(minLength: 12)
                Image(systemName: model.symbol(item))
                    .font(.system(size: 17))
                    .foregroundStyle(enabled ? LimeghostTheme.textSecondary : LimeghostTheme.textTertiary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// The menu's content height, carried from inside the scroll view up to the
/// sheet's detent.
private struct PageMenuHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
```

- [ ] **Step 6: Give the bar its button**

In `ios/Sources/BottomBar.swift`:

1. Change the doc comment line `/// Back, the address, the tabs and a menu — within a thumb's reach, along the` so that it reads `/// Back, the address, the tabs and the page menu — within a thumb's reach, along the`.
2. After `let openTabs: () -> Void`, add `let openMenu: () -> Void`.
3. Delete the comment block that begins `// The page menu belongs after the tab button`, which runs to `// would teach the wrong thing about where it lives.`. Keep the assistant toggle's comment above it.
4. After the tab button's `.accessibilityLabel("Tabs, \(model.tabCount) open")`, add:

```swift

            // The page menu. Its touch area is 44 points wide and as tall as
            // the address pill: the glyph alone is a target a finger misses.
            Button(action: openMenu) {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 38)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Menu")
```

- [ ] **Step 7: Present the sheet**

In `ios/Sources/BrowserScreen.swift`, replace the whole `BrowserScreen` struct (lines 4–42) with:

```swift
/// The whole browser, one screen.
struct BrowserScreen: View {
    @ObservedObject var host: WorkspaceHost
    @State private var isPresentingAddressSheet = false
    @State private var isPresentingTabSwitcher = false
    @State private var menu = PageMenuPresentation()
    /// The page menu's measured height; see `PageMenu.height`. It starts near
    /// the real value, so the first opening hardly moves.
    @State private var menuHeight: CGFloat = 540

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let tab = host.workspace.selectedTab {
                    TabSurface(tab: tab, workspace: host.workspace)
                } else {
                    Color.clear
                }
            }

            bottomBar
        }
        .sheet(isPresented: $isPresentingAddressSheet) {
            AddressSheet(workspace: host.workspace) {
                isPresentingAddressSheet = false
            }
        }
        .sheet(isPresented: $isPresentingTabSwitcher) {
            TabSwitcher(workspace: host.workspace) {
                isPresentingTabSwitcher = false
            }
        }
        .sheet(isPresented: $menu.isPresented, onDismiss: runChosenMenuItem) {
            PageMenu(
                model: PageMenuModel(workspace: host.workspace),
                choose: { menu.choose($0) },
                height: $menuHeight
            )
            .presentationDetents([.height(menuHeight)])
            .presentationDragIndicator(.visible)
            .presentationBackground(LimeghostTheme.bg1)
        }
    }

    private var bottomBar: BottomBar {
        BottomBar(
            model: BottomBarModel(
                urlString: host.workspace.selectedTab?.session.currentURLString ?? "",
                tabCount: host.workspace.visibleTabs.count,
                canGoBack: host.workspace.canGoBackInSelectedTab
            ),
            goBack: { host.workspace.goBackInSelectedTab() },
            openAddress: { isPresentingAddressSheet = true },
            openTabs: { isPresentingTabSwitcher = true },
            openMenu: { menu.open() }
        )
    }

    /// Runs the row the menu closed for, now that the sheet has gone.
    private func runChosenMenuItem() {
        guard let item = menu.didDismiss() else { return }
        let actions = PageMenuActions(workspace: host.workspace)
        Task { await actions.perform(item) }
    }
}
```

- [ ] **Step 8: Run the phone's suite**

Run the phone's suite. Expected: the previous count plus 3, and 0 failures.

The views in Steps 5–7 carry no logic of their own: what they show comes from the model, what they do comes from the actions, and when they do it comes from the presentation. Each of those is tested. How the views look is checked on the Simulator in Task 8.

- [ ] **Step 9: Commit**

```bash
git add ios/Sources/PageMenu.swift ios/Sources/BottomBar.swift ios/Sources/BrowserScreen.swift \
  ios/Tests/PageMenuTests.swift
git commit -m "Open the page menu from the bottom bar"
```

---

### Task 6: Find in Page on the phone

**Files:**
- Create: `ios/Sources/FindBar.swift`
- Create: `ios/Tests/FindBarTests.swift`
- Modify: `ios/Sources/BrowserScreen.swift` and `ios/Limeghost.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: from Task 5, `BrowserScreen.bottomBar`.
- Produces:
  - `struct FindBar: View`, initialised as `FindBar(find:)`.
  - `static func outcomeText(_ outcome: PageFindController.Outcome) -> String?` and `static func canStep(_ outcome: PageFindController.Outcome) -> Bool`.
  - `struct BottomChrome: View`, initialised as `BottomChrome(find:bar:)`.

- [ ] **Step 1: Write the failing tests**

Create `ios/Tests/FindBarTests.swift`:

```swift
import XCTest
@testable import Limeghost
@testable import LimeghostShared

/// What the find bar says, and when its arrows work. WebKit reports whether a
/// match was found and nothing else, so the bar has exactly three things to
/// say, and two of them are nothing.
@MainActor
final class FindBarTests: XCTestCase {
    func testNothingFoundSaysNoResults() {
        XCTAssertEqual(FindBar.outcomeText(.noResults), "No results")
    }

    /// On a match, the page's own highlight is the answer. The bar says
    /// nothing, and above all never a position or a count.
    func testAMatchSaysNothing() {
        XCTAssertNil(FindBar.outcomeText(.matched))
    }

    func testBeforeAnySearchItSaysNothing() {
        XCTAssertNil(FindBar.outcomeText(.idle))
    }

    /// The arrows step between matches, so they wait for one.
    func testTheArrowsWaitForAMatch() {
        XCTAssertTrue(FindBar.canStep(.matched))
        XCTAssertFalse(FindBar.canStep(.noResults))
        XCTAssertFalse(FindBar.canStep(.idle))
    }
}
```

Add it to `project.pbxproj`, with tabs:
- `PBXBuildFile`, after the `…2108` line:
  ```
  		AA0000000000000000002109 /* FindBarTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000002209 /* FindBarTests.swift */; };
  ```
- `PBXFileReference`, after the `…2208` line:
  ```
  		AA0000000000000000002209 /* FindBarTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FindBarTests.swift; sourceTree = "<group>"; };
  ```
- The `Tests` group's `children`, after `…2208 /* PageMenuTests.swift */,`: `				AA0000000000000000002209 /* FindBarTests.swift */,`
- The tests' `Sources` phase, after `…2108 /* PageMenuTests.swift in Sources */,`: `				AA0000000000000000002109 /* FindBarTests.swift in Sources */,`

- [ ] **Step 2: Run them to watch them fail**

Run: `cd ios && xcodebuild test -scheme Limeghost -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LimeghostTests/FindBarTests`

Expected: the build fails with `cannot find 'FindBar' in scope`.

- [ ] **Step 3: Write the find bar**

Create `ios/Sources/FindBar.swift`:

```swift
import LimeghostShared
import SwiftUI

/// Find in Page, in the bottom bar's place while it is open.
///
/// WebKit reports whether a match was found and nothing else — no position,
/// no total — so this bar says "No results" or says nothing at all, exactly
/// as the Mac's does. It never invents "3 of 12". It wears the bottom bar's
/// system look, because it stands where the bar stands; the two take the
/// theme together in the look step.
struct FindBar: View {
    @ObservedObject var find: PageFindController
    @FocusState private var fieldFocused: Bool

    /// "No results" when nothing matched, and nothing otherwise: not while
    /// idle, and not on a match, where the page's own highlight is the answer.
    static func outcomeText(_ outcome: PageFindController.Outcome) -> String? {
        outcome == .noResults ? "No results" : nil
    }

    /// The arrows step between matches, so they wait for one. The Mac greys
    /// them only while the field is empty; on a phone, with no count to show,
    /// greyed arrows are how the bar says there is nothing to step to.
    static func canStep(_ outcome: PageFindController.Outcome) -> Bool {
        outcome == .matched
    }

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Find in Page", text: $find.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($fieldFocused)
                    .onSubmit { find.step(backwards: false) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(.quaternary))

            if let text = Self.outcomeText(find.outcome) {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            Button { find.step(backwards: true) } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(!Self.canStep(find.outcome))
            .accessibilityLabel("Previous match")

            Button { find.step(backwards: false) } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(!Self.canStep(find.outcome))
            .accessibilityLabel("Next match")

            Button("Done") { find.close() }
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onAppear { fieldFocused = true }
        .onChange(of: find.focusRequest) { _, _ in fieldFocused = true }
        .onChange(of: find.query) { _, _ in find.queryChanged() }
    }
}
```

Add it to `project.pbxproj`, with tabs:
- `PBXBuildFile`, after the `…010C` line:
  ```
  		AA000000000000000000010D /* FindBar.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA000000000000000000020E /* FindBar.swift */; };
  ```
- `PBXFileReference`, after the `…020D` line:
  ```
  		AA000000000000000000020E /* FindBar.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FindBar.swift; sourceTree = "<group>"; };
  ```
- The `Sources` group's `children`, after `…020D /* PageMenu.swift */,`: `				AA000000000000000000020E /* FindBar.swift */,`
- The app's `Sources` phase, after `…010C /* PageMenu.swift in Sources */,`: `				AA000000000000000000010D /* FindBar.swift in Sources */,`

- [ ] **Step 4: Put it in the bar's place while finding**

In `BrowserScreen.swift`, add this struct after `BrowserScreen`:

```swift
/// The bar along the bottom, or the find bar in its place while finding.
///
/// Its own view, so it can observe the tab's find controller. `BrowserScreen`
/// observes the workspace, and a tab's `find` changes without the workspace
/// hearing of it — the same reason `TabSurface` observes its tab and session.
struct BottomChrome: View {
    @ObservedObject var find: PageFindController
    let bar: BottomBar

    var body: some View {
        if find.isPresented {
            FindBar(find: find)
        } else {
            bar
        }
    }
}
```

In `BrowserScreen.body`, replace the line `            bottomBar` (inside the `VStack`, after the `Group`) with:

```swift
            if let tab = host.workspace.selectedTab {
                BottomChrome(find: tab.find, bar: bottomBar)
            } else {
                bottomBar
            }
```

- [ ] **Step 5: Run them to watch them pass, then break one**

Run the Step 2 command. Expected: 4 tests, 0 failures.

Then make `outcomeText` return `"No results"` for `.matched` too. Expected: `testAMatchSaysNothing` fails. Restore it.

- [ ] **Step 6: Run the phone's suite and commit**

Run the phone's suite. Expected: the previous count plus 4, and 0 failures. Then commit:

```bash
git add ios/Sources/FindBar.swift ios/Tests/FindBarTests.swift ios/Sources/BrowserScreen.swift \
  ios/Limeghost.xcodeproj/project.pbxproj
git commit -m "Find in page on the phone, without a count"
```

---

### Task 7: Reader over the page, and the notice banner

**Files:**
- Create: `ios/Sources/NoticeBanner.swift`
- Modify: `ios/Sources/BrowserScreen.swift`, `ios/Tests/ReaderOnThePhoneTests.swift` and `ios/Limeghost.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: from Task 2, `ReaderView(article:copy:close:headerStyle:)`. Already there: `BrowserTab.copyArticleForAI(_:)` and `BrowserSession.pageNotice` and `dismissPageNotice()`.
- Produces: `TabSurface.showsTheReader: Bool`, `struct NoticeBanner: View` initialised as `NoticeBanner(message:dismiss:)`, and `struct NoticeLayer: View` initialised as `NoticeLayer(session:)`.

- [ ] **Step 1: Write the failing tests**

In `ios/Tests/ReaderOnThePhoneTests.swift`, add these after the `article()` helper:

```swift
    /// A suite of its own, emptied afterwards, as `StartSurfaceTests.makeHost()` does.
    private func makeHost() throws -> WorkspaceHost {
        let suiteName = "clearframe.iosReader.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return WorkspaceHost.forTesting(defaults: defaults)
    }

    // MARK: - Over the page

    /// While an article is open, Reader covers the page. The web view stays
    /// mounted underneath it.
    func testReaderCoversThePageWhileAnArticleIsOpen() throws {
        let host = try makeHost()
        let tab = try XCTUnwrap(host.workspace.selectedTab)
        host.workspace.open("https://example.com/")
        XCTAssertFalse(TabSurface(tab: tab, workspace: host.workspace).showsTheReader)

        tab.readerArticle = try article()

        XCTAssertTrue(TabSurface(tab: tab, workspace: host.workspace).showsTheReader)
    }

    /// The guide is not a page, and Reader never covers it.
    func testReaderNeverCoversTheGuide() throws {
        let host = try makeHost()
        let tab = try XCTUnwrap(host.workspace.selectedTab)

        tab.readerArticle = try article()

        XCTAssertFalse(TabSurface(tab: tab, workspace: host.workspace).showsTheReader)
    }
```

- [ ] **Step 2: Run them to watch them fail**

Run: `cd ios && xcodebuild test -scheme Limeghost -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LimeghostTests/ReaderOnThePhoneTests`

Expected: the build fails with `value of type 'TabSurface' has no member 'showsTheReader'`.

- [ ] **Step 3: Draw Reader over the page**

In `BrowserScreen.swift`, inside `TabSurface`, add this after `showsTheGuide`:

```swift
    /// Reader covers the page while an article is open. Never over the guide,
    /// which is not a page.
    var showsTheReader: Bool {
        !showsTheGuide && tab.readerArticle != nil
    }
```

Then replace `TabSurface.body` with:

```swift
    var body: some View {
        if showsTheGuide {
            StartSurfaceScreen(workspace: workspace)
        } else {
            WebViewHost(session: session)
                .id(session.instanceID)
                .ignoresSafeArea(edges: .bottom)
                // Over the page rather than instead of it: the web view stays
                // mounted, so closing Reader shows the page exactly as it was.
                .overlay {
                    if showsTheReader, let article = tab.readerArticle {
                        ReaderView(
                            article: article,
                            copy: { tab.copyArticleForAI(article) },
                            close: { tab.readerArticle = nil },
                            headerStyle: .touch
                        )
                        .transition(.opacity)
                    }
                }
        }
    }
```

- [ ] **Step 4: Run them to watch them pass, then break one**

Run the Step 2 command. Expected: 3 tests, 0 failures.

Then drop `!showsTheGuide &&` from `showsTheReader`. Expected: `testReaderNeverCoversTheGuide` fails. Restore it.

- [ ] **Step 5: Write the banner**

Create `ios/Sources/NoticeBanner.swift`:

```swift
import LimeghostShared
import SwiftUI

/// A page notice, floating just above the bottom bar: what Copy for AI
/// copied, a bookmark added or removed, or why something could not be done.
///
/// The session writes the words and clears them after eight seconds; this only
/// draws them. A tap dismisses it sooner. A rounded rectangle rather than a
/// capsule, because the longest notices run to three lines.
struct NoticeBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        Button(action: dismiss) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(LimeghostTheme.textPrimary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    LimeghostTheme.bg3,
                    in: RoundedRectangle(cornerRadius: LimeghostTheme.radius14, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LimeghostTheme.radius14, style: .continuous)
                        .stroke(LimeghostTheme.hairline3)
                )
                .shadow(color: .black.opacity(0.28), radius: 12, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Dismisses this notice")
        .padding(.horizontal, 16)
    }
}

/// The selected session's notice, if it has one. Its own view so it can
/// observe the session, whose notices the workspace never hears about.
struct NoticeLayer: View {
    @ObservedObject var session: BrowserSession

    var body: some View {
        VStack {
            if let notice = session.pageNotice {
                NoticeBanner(message: notice) { session.dismissPageNotice() }
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: session.pageNotice)
    }
}
```

Add it to `project.pbxproj`, with tabs:
- `PBXBuildFile`, after the `…010D` line:
  ```
  		AA000000000000000000010E /* NoticeBanner.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA000000000000000000020F /* NoticeBanner.swift */; };
  ```
- `PBXFileReference`, after the `…020E` line:
  ```
  		AA000000000000000000020F /* NoticeBanner.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = NoticeBanner.swift; sourceTree = "<group>"; };
  ```
- The `Sources` group's `children`, after `…020E /* FindBar.swift */,`: `				AA000000000000000000020F /* NoticeBanner.swift */,`
- The app's `Sources` phase, after `…010D /* FindBar.swift in Sources */,`: `				AA000000000000000000010E /* NoticeBanner.swift in Sources */,`

- [ ] **Step 6: Float it over the bottom of the tab's surface**

In `BrowserScreen.body`, change `TabSurface(tab: tab, workspace: host.workspace)` so that it reads:

```swift
                    TabSurface(tab: tab, workspace: host.workspace)
                        .overlay(alignment: .bottom) { NoticeLayer(session: tab.session) }
```

- [ ] **Step 7: Run the phone's suite and commit**

Run the phone's suite. Expected: the previous count plus 2, and 0 failures.

```bash
git add ios/Sources/NoticeBanner.swift ios/Sources/BrowserScreen.swift \
  ios/Tests/ReaderOnThePhoneTests.swift ios/Limeghost.xcodeproj/project.pbxproj
git commit -m "Put Reader and page notices on the phone's screen"
```

---

### Task 8: On the Simulator, then on the phone

This task writes no code. It is where the three things not verified at planning time get checked. If a check fails, fix the problem in the task it belongs to, with a failing test first wherever the problem has logic, then come back here.

- [ ] **Step 1: Run every suite and record the counts**

Run the four commands from **Commands**. Expected:
- `swift test`: the baseline plus 12. That is 10 in Task 1 and 1 each in Tasks 2 and 4.
- `LimeghostSharedLayer`: `** TEST SUCCEEDED **` on both destinations. The list count is the baseline plus 10.
- The app: the baseline plus 22, from Tasks 2 to 7.

Keep all the numbers for Task 9.

- [ ] **Step 2: Build and run it on the Simulator**

```bash
cd ios && xcodebuild build -scheme Limeghost -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/limeghost-menu-sim
xcrun simctl boot "iPhone 17 Pro"; open -a Simulator
xcrun simctl install booted /tmp/limeghost-menu-sim/Build/Products/Debug-iphonesimulator/Limeghost.app
xcrun simctl launch booted com.zincoo.limeghost
```

`simctl boot` reports an error if the device is already booted. That is harmless.

- [ ] **Step 3: Check each state against the canvas**

Do each check below by hand, or with computer use. Compare each with the spec's canvas. Take a screenshot of each with `xcrun simctl io booted screenshot /tmp/menu-<name>.png`.

1. **The menu on the guide.** On the AI guide, tap `•••`.
   - The sheet opens as tall as its rows, and nothing scrolls.
   - Reader, Copy for AI, Reload, Forward, Add Bookmark, Find in Page, Share and Request Desktop Site are greyed.
   - New Tab and New Private Tab work.
   - Screenshot name: `guide`.
2. **The menu on a page.** Open `example.com` from the address pill, then tap `•••`.
   - Everything works except Forward.
   - The last row, Request Desktop Site, ends above the home indicator.
   - This is the detent check the plan could not make in advance. Screenshot name: `page`.
3. **Share.** Tap Share. The menu closes, then the system share sheet appears.
4. **Bookmarks.**
   - Tap Add Bookmark. The banner says "Bookmark added.", above the bottom bar.
   - Open the menu again. It reads Remove Bookmark, with a filled star.
   - Tap it. The banner says "Bookmark removed.".
   - Tap a banner, and it goes.
5. **Reader.** Tap Reader.
   - Reader covers the page, with the two-row header. Screenshot name: `reader`.
   - Reader's own Copy for AI turns into "Copied" for a moment.
   - Open the menu. The tile reads Close Reader, and Find in Page is greyed.
   - ✕ closes Reader.
6. **Copy for AI.** Tap Copy for AI in the menu.
   - The banner says "Copied N words." Screenshot name: `copied`.
   - Paste into Notes: it is the page's text, with Limeghost's header.
7. **Find in Page.** Tap Find in Page.
   - The keyboard comes up with the find bar above it.
   - Type a word that is on the page. The bar says nothing, the arrows work, and the page highlights the match.
   - Type `zzqq`. The bar says "No results" and the arrows grey. Screenshot name: `find`.
   - Tap Done. The bottom bar returns.
8. **Desktop site.** Open `https://www.whatismybrowser.com/`. It names the operating system it detects.
   - Tap Request Desktop Site. After the reload, the page names a Mac rather than an iPhone, and the menu reads Request Mobile Site.
   - Tap Request Mobile Site. It names an iPhone again.
   - This is the reload check the plan could not make in advance.
9. **New Private Tab.** Tap New Private Tab.
   - A private tab opens on the guide.
   - The tab switcher lists it under Private.

- [ ] **Step 4: Install it on the founder's iPhone**

The phone must be connected by cable and unlocked. On September 10, Wi-Fi install failed with CoreDeviceError 4000.
- `TEAM` is the founder's Personal Team identifier. Read it from `defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier`, and never write it into any file in the repository.
- `DEVICE` is the identifier `xcrun devicectl list devices` prints for "iPhone LR".

```bash
xcodebuild -project ios/Limeghost.xcodeproj -scheme Limeghost -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/limeghost-device -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" PRODUCT_BUNDLE_IDENTIFIER=com.zincoo.limeghost.dev CODE_SIGN_STYLE=Automatic build
xcrun devicectl device install app --device "$DEVICE" \
  /tmp/limeghost-device/Build/Products/Debug-iphoneos/Limeghost.app
xcrun devicectl device process launch --device "$DEVICE" com.zincoo.limeghost.dev
```

Expected: `** BUILD SUCCEEDED **`, "App installed", and the app opening on the phone.

A free profile lasts seven days from this install. Note the new expiry for Task 9.

---

### Task 9: The documents say what now exists

**Files:**
- Modify: `docs/ios-browser-foundation.md`, `AGENTS.md`, `CLAUDE.md`, `CHANGELOG.md` and `docs/project-context.md`

Use the counts and the expiry date recorded in Task 8. Nothing here may call the phone validated.

- [ ] **Step 1: `docs/ios-browser-foundation.md`**

1. **Line 3.** Change `**Status: September 10, 2026.**` to the date this lands.
2. **Line 11.** In "there is no assistant panel, no Reader, no Copy for AI, no bookmark import, …", delete "no Reader, no Copy for AI, ".
3. **Line 17.** Replace "Eleven source files under `ios/Sources`, plus five Swift files and one image" with "Fourteen source files under `ios/Sources`, plus six Swift files and one image".
4. **Line 20.** In the bottom bar bullet, replace "back, the address, the tab count" with "back, the address, the tab count and the page menu".
5. **After line 20,** add these bullets:

   ```markdown
   - **A page menu** behind the bar's `•••`: Reader and Copy for AI as two large buttons, then Reload, Forward, New Tab, New Private Tab, Add Bookmark, Find in Page, Share and Request Desktop Site. It opens as tall as its rows. On the AI guide the page rows are greyed and the two new-tab rows work. A row closes the sheet before it acts (`PageMenuPresentation`), because the system share sheet cannot appear over it. The design is [docs/superpowers/specs/2026-09-12-ios-page-menu-design.md](superpowers/specs/2026-09-12-ios-page-menu-design.md).
   - **Reader**: the Mac's own `ReaderView`, over the page, with the web view still mounted underneath. The phone asks for its touch header, two rows of 44 points.
   - **Copy for AI**, from the menu or inside Reader. The menu confirms each copy in a banner: "Copied N words.", or the Mac's own warning when the copy is doubtful.
   - **Find in Page**, in the bottom bar's place. It says "No results" or nothing, never a count.
   - **Request Desktop Site**, per tab and not remembered, through `BrowserSession.prefersDesktopSite`.
   - **A banner** above the bar for the session's page notices. It goes after eight seconds, or on a tap.
   ```

6. **Line 30.** Replace "**28 tests**" with the app's count from Task 8. Add to that sentence's list: "the page menu's model, actions and close-then-act rule, the find bar's outcome text, Reader's touch header at three widths, and Reader over the page".
7. **Line 50.** Replace "**Five Mac SwiftUI files and one image compiled into the iOS app by reference**: `AIToolStartPage.swift`, `LimeghostTheme.swift`, `SiteIconView.swift`, `StartSurfaceChrome.swift` and `BrandMark.swift`," with "**Six Mac SwiftUI files and one image compiled into the iOS app by reference**: `AIToolStartPage.swift`, `LimeghostTheme.swift`, `SiteIconView.swift`, `StartSurfaceChrome.swift`, `BrandMark.swift` and `ReaderView.swift`,". Then add after that item's first sentence: "`ReaderView.swift` joined with the page menu; the phone passes `headerStyle: .touch`, and the Mac keeps its row."
8. **Build and test section.** Update the counts: the Mac's `swift test` count, the app's count, `LimeghostSharedLayer`'s count, and "`LimeghostSharedTests` (20)", which becomes 30. The difference between the two totals is `BrowserBehaviorTests`, which gained 2.
9. **"Onto a real iPhone".** Record the new install date and the profile's new expiry.

- [ ] **Step 2: `AGENTS.md` and `CLAUDE.md`**

1. **`AGENTS.md` line 79.** Replace "The phone compiles five Mac SwiftUI files by reference: `AIToolStartPage.swift`, `LimeghostTheme.swift`, `SiteIconView.swift`, `StartSurfaceChrome.swift` and `BrandMark.swift`." with "The phone compiles six Mac SwiftUI files by reference: `AIToolStartPage.swift`, `LimeghostTheme.swift`, `SiteIconView.swift`, `StartSurfaceChrome.swift`, `BrandMark.swift` and `ReaderView.swift`." Leave "Commit `c357511` put five into the iPhone target" as it is: that five counts compile errors.
2. **`CLAUDE.md` line 33.** Replace "The phone compiles five Mac SwiftUI files by reference" with "The phone compiles six Mac SwiftUI files by reference". Leave "`c357511` put five compile errors" as it is.

- [ ] **Step 3: `CHANGELOG.md`**

Under the week this lands, add:

```markdown
**The phone gets its page menu**

- A `•••` sheet in the bottom bar: Reader and Copy for AI, then Reload, Forward, New Tab, New Private Tab, Add Bookmark, Find in Page, Share and Request Desktop Site. On the AI guide the page rows are greyed. Designed with the founder on September 11–12; the spec and a design canvas are in `docs/superpowers/specs/2026-09-12-ios-page-menu-design.md`.
- Reader on the phone is the Mac's own `ReaderView`, now compiled by both apps, with a two-row header a finger can use. The Mac keeps its row, and a test holds it there.
- Copy for AI confirms each copy on the phone in words. The Mac still says nothing about a clean copy, on purpose.
- Find in Page on the phone says "No results" or nothing. The first conversation promised "3 of 12"; WebKit reports no count, so none is shown.
- The page-load hook is now `BrowserSession.decide(…)`, a pure function tested branch by branch on both platforms. Its delegate answers WebKit's `preferences:` form, which carries the phone's per-tab Request Desktop Site. The Mac never turns that on.
- Tests: the Mac <count>, `LimeghostSharedLayer` <count> on both destinations, the phone <count>.
```

Write the three counts from Task 8 into the last bullet in place of `<count>`.

- [ ] **Step 4: `docs/project-context.md`**

At the end of the "iOS pocket browser" section (line 21), add a paragraph dated the day this lands, in the style of that section's other dated notes. It records these decisions and their reasons:
- The menu takes Chrome's shape with Limeghost's contents. The founder picked the shape on September 11.
- It opens as tall as its rows rather than at half height.
- Its labels are title case, matching the Mac's menu names.
- Reader's tile reads Close Reader, and Find is greyed while Reader is open.
- The phone confirms a clean copy although the Mac does not. The menu closes as it copies, and iOS shows nothing on a clipboard write.
- The desktop switch is per tab and not remembered.
- Bookmarks, History, Settings and the look are steps 2–5.
- No observed-user session has been run.

- [ ] **Step 5: Commit**

```bash
git add docs/ios-browser-foundation.md AGENTS.md CLAUDE.md CHANGELOG.md docs/project-context.md
git commit -m "Say what the phone's page menu brought"
```

---

## Self-Review

Run on September 12, 2026, against the spec.

**1. Spec coverage**

- §2, the button and the sheet: Tasks 3–5.
- §3.2:
  - The content-height detent: Task 5, Step 5 and Step 7, checked in Task 8, Step 3.2.
  - Labels: Task 3's `title(_:)` and `testTheLabelsSayWhatATapWillDoNext`.
  - Symbols: Task 3's `symbol(_:)`.
- §3.3, states: Task 3's model tests.
- §4, item by item:
  - Close-then-act: Task 5's `PageMenuPresentation` and its three tests.
  - Reader: Tasks 2 and 7.
  - Copy for AI: Task 4.
  - Reload, Forward and the new tabs: Task 4's `perform`.
  - Bookmarks: Task 4.
  - Find: Tasks 4 and 6.
  - Share: Task 4, and Task 8, Step 3.3.
  - Desktop: Tasks 1 and 4, and Task 8, Step 3.8.
- §5, the look:
  - The sheet: Task 5's view.
  - The banner: Task 7.
  - The find bar: Task 6.
  - Reader: Task 2.
  - The bar: Task 5, Step 6.
- §6, the hook and the switch: Task 1.
- §7, architecture: the File Structure table matches it file for file.
- §8, testing: every listed test appears in a task. The by-hand checks are Task 8.
- Success criteria:
  - 1–4: Task 8.
  - 5: Task 8, Step 1, and Task 2, Steps 7–8, for the Mac.
  - 6: Task 9.

**2. Placeholder scan**

- The only `<count>` markers are in Task 9, Step 3. Each has an instruction saying where its number comes from: Task 8.
- `TEAM` and `DEVICE` in Task 8 are values that must stay out of the repository. Each has an instruction saying where to read it.
- No step says "add tests" or "handle errors" without the code.

**3. Consistency of names, checked across tasks**

- `decide(shouldPerformDownload:targetFrameIsMain:url:)`, `applyContentMode(prefersDesktopSite:to:)`, `prefersDesktopSite` and `setPrefersDesktopSite(_:)`: Tasks 1 and 4.
- `ReaderView.Header(article:style:copy:close:)` and `headerStyle: .touch`: Tasks 2 and 7.
- `PageMenuItem` cases: Tasks 3, 4 and 5.
- `PageMenuModel(workspace:)`: Tasks 3 and 5.
- `PageMenuActions(workspace:).perform(_:)`: Tasks 4 and 5.
- `PageMenuPresentation.open()`, `choose(_:)` and `didDismiss()`: Task 5.
- `FindBar.outcomeText(_:)` and `canStep(_:)`: Task 6.
- `BottomChrome(find:bar:)`: Task 6.
- `TabSurface.showsTheReader` and `NoticeLayer(session:)`: Task 7.
- `copyConfirmation` and `copySelectedPageForAI() -> ReaderArticle?`: Task 4.
- Project IDs:
  - `…020D/…010C` PageMenu, `…020E/…010D` FindBar, `…020F/…010E` NoticeBanner.
  - `…0667/…0677` ReaderView.
  - `…2207/…2107` ReaderOnThePhoneTests, `…2208/…2108` PageMenuTests, `…2209/…2109` FindBarTests.
  - None of these collides with an ID already in the file.
