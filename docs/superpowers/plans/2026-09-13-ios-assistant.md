# Limeghost for iPhone — Your Own Assistant Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A button in the phone's bottom bar opens the person's own ChatGPT, Claude, Gemini, Le Chat or Grok over the page. Sign-in windows open over it. A page iOS ended reloads its conversation. The bar hides while typing, and the copy confirmation never covers the provider's message box.

**Architecture:** The shared `AICompanion` stays the brain. It gains a popup it can hold over the assistant (chosen by the host through a new `AssistantPopupPlacement`) and automatic reopening of a page whose process ended. `BrowserSession` gains two callbacks for those. The phone adds a thin layer: `AssistantLayer` in the same `ZStack` as the page, a bar button, a keyboard observer, and pure layout rules tests can call. The Mac's panel is untouched.

**Tech Stack:** SwiftUI (iOS 17), WebKit (`WKUIDelegate.webViewDidClose`, `webViewWebContentProcessDidTerminate`), Combine, XCTest, SwiftPM (`LimeghostShared`).

**Spec:** [docs/superpowers/specs/2026-09-13-ios-assistant-design.md](../specs/2026-09-13-ios-assistant-design.md). The canvas is linked from it.

## Global Constraints

- iOS 17.0, Swift 5 mode; macOS 14 for the package.
- **No `#if os` in `LimeghostShared`.** A platform difference is a value or protocol member supplied by the host: here `AssistantPopupPlacement`.
- Limeghost **never types into, presses send in, or reads** the assistant's page. No page action goes in its header. Nothing "sends to your assistant".
- **One layer, in one place in the tree.** `AssistantLayer` sits in the same `ZStack` position whether visible or not, and a `WebViewHost` is keyed on `session.instanceID`. Never present the assistant with `.sheet` or `.fullScreenCover`.
- Colours come from `LimeghostTheme`. The unlit button takes the bar's system tint (`.tint`) until step 5.
- A door calls `makeRoomForPage()`. The assistant button is not a door. Reader (opening) and Find in Page call `aiCompanion.makeRoomForPage()` because they show the page the assistant covers.
- `DEVELOPMENT_TEAM` stays `""`; storage identifiers are untouched.
- Watch each new test fail first, and break each fix once on purpose.
- Never describe anything as validated with users.
- Commit messages end with the two attribution lines:
  ```
  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_014pJsUVUWJsmR3Xca4A1Tso
  ```
  Push after each commit.

**Commands** (from the worktree root):

- Mac: `cd macos/LimeghostBrowser && swift test 2>&1 | grep -E "Executed [0-9]+ test|error:|failed \("`
- One shared class on the Mac: `cd macos/LimeghostBrowser && swift test --filter <Class> 2>&1 | grep -E "Executed [0-9]+ test|error:|failed \("`
- Counts: `cd macos/LimeghostBrowser && swift test --list-tests 2>/dev/null | cut -d. -f1 | sort | uniq -c`
- Shared layer on the simulator: `cd macos/LimeghostBrowser && xcodebuild test -scheme LimeghostSharedLayer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error: |\*\* TEST"`
- Phone: `cd ios && xcodebuild test -scheme Limeghost -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|\*\* TEST|Executed [0-9]+ test|failed \("`. Add `-only-testing:LimeghostTests/<Class>` for one class.
- Adding a file to the Xcode project: `pbx_add.py`, exactly as in [the Bookmarks and History plan](2026-09-13-ios-bookmarks-history.md) (Global Constraints). It takes `NAME PATH FILE_REF_ID BUILD_FILE_ID AFTER_NAME`.

**Project IDs** (checked unused September 13, 2026):

| File | Reference | Build file | After |
|---|---|---|---|
| `AssistantOnThePhoneTests.swift` | `AA000000000000000000220D` | `AA000000000000000000210D` | `HistorySheetTests.swift` |
| `AssistantLayer.swift` | `AA0000000000000000000214` | `AA0000000000000000000113` | `HistorySheet.swift` |
| `KeyboardObserver.swift` | `AA0000000000000000000215` | `AA0000000000000000000114` | `AssistantLayer.swift` |

**Counts before:** Mac 517 (Core 238, Shared 30, BrowserBehavior 249); `LimeghostSharedLayer` 268; phone 73.
**After:** Mac 525 (Shared 38); `LimeghostSharedLayer` 276; phone 83.

## File Structure

| File | Responsibility |
|---|---|
| `LimeghostShared/AssistantPopupPlacement.swift` (new) | Where a window the assistant's page opens is shown |
| `LimeghostShared/BrowserSession.swift` | `onRequestClose` (via `webViewDidClose`), `onWebContentProcessTerminated` |
| `LimeghostShared/AICompanion.swift` | `popup`, `presentPopup`, `dismissPopup`; automatic reopening with an injected clock |
| `LimeghostShared/BrowserWorkspace.swift` | `assistantPopups` parameter; `openAssistantPopup(configuration:)` |
| `LimeghostShared/BrowserUserAgent.swift` | The operating-system fallback for the Safari version |
| `Tests/LimeghostSharedTests/CompanionBehaviorTests.swift`, `BrowserUserAgentTests.swift` (new) | Shared tests |
| `ios/Sources/WorkspaceHost.swift` | `.overAssistant`, forwarding the companion's changes, never sharing the screen |
| `ios/Sources/PageMenu.swift` | Reader and Find in Page uncover the page |
| `ios/Sources/BottomBar.swift` | `isAssistantOpen`, `assistantLabel`, the button |
| `ios/Sources/AssistantLayer.swift` (new) | `AssistantDismissal`, `AssistantLayer`, `AssistantHeader`, `AssistantPageView`, `AssistantPopupLayer` |
| `ios/Sources/KeyboardObserver.swift` (new) | Whether the software keyboard is up |
| `ios/Sources/BrowserScreen.swift` | `NoticePlacement`, `BottomChromeContent`, the `ZStack`, the strip |
| `ios/Sources/NoticeBanner.swift` | `NoticeLayer` takes a placement |
| `ios/Tests/AssistantOnThePhoneTests.swift` (new), `BottomBarTests.swift` | Phone tests |

---

### Task 1: Sign-in windows over the assistant (shared)

**Files:**
- Create: `macos/LimeghostBrowser/Sources/LimeghostShared/AssistantPopupPlacement.swift`
- Modify: `…/LimeghostShared/BrowserSession.swift`, `…/AICompanion.swift`, `…/BrowserWorkspace.swift`
- Test: `macos/LimeghostBrowser/Tests/LimeghostSharedTests/CompanionBehaviorTests.swift`

**Interfaces:**
- Produces:
  - `public enum AssistantPopupPlacement { case tab, overAssistant }`;
  - `BrowserWorkspace.init(…, assistantPopups: AssistantPopupPlacement = .tab)`, as the last parameter;
  - `BrowserSession.onRequestClose: (() -> Void)?` and `webViewDidClose(_:)`;
  - `AICompanion.popup: BrowserSession?` (published, read-only), `presentPopup(_:)` and `dismissPopup()`.

- [ ] **Step 1: Write the failing tests**

In `CompanionBehaviorTests.swift`, give the helper a parameter:

```swift
    private func makeSurfaceTestWorkspace(assistantPopups: AssistantPopupPlacement = .tab) throws -> BrowserWorkspace {
```

and pass `assistantPopups: assistantPopups` as its `BrowserWorkspace(…)` call's last argument. Add these tests after `testLeavingCompareKeepsTheAssistantStillOnScreen`:

```swift
    /// The Mac's behaviour, pinned: a window the assistant's page opens
    /// becomes a tab, and the companion holds nothing over itself.
    func testAWindowTheAssistantOpensIsATabByDefault() throws {
        let workspace = try makeSurfaceTestWorkspace()
        let companion = workspace.aiCompanion
        companion.show()
        let assistant = try XCTUnwrap(companion.session)
        let tabsBefore = workspace.tabs.count

        let returned = assistant.onRequestPopupWebView?(WKWebViewConfiguration())

        XCTAssertEqual(workspace.tabs.count, tabsBefore + 1)
        XCTAssertTrue(returned === workspace.tabs.last?.session.webView)
        XCTAssertNil(companion.popup)
    }

    /// Where the assistant covers the page, the window is shown over it: no
    /// tab appears behind the assistant, and WebKit drives the popup's own
    /// web view, which keeps `window.opener` connected.
    func testWhenAskedAWindowTheAssistantOpensIsShownOverIt() throws {
        let workspace = try makeSurfaceTestWorkspace(assistantPopups: .overAssistant)
        let companion = workspace.aiCompanion
        companion.show()
        let assistant = try XCTUnwrap(companion.session)
        let tabsBefore = workspace.tabs.count

        let returned = assistant.onRequestPopupWebView?(WKWebViewConfiguration())

        XCTAssertEqual(workspace.tabs.count, tabsBefore, "the sign-in opened a tab behind the assistant")
        let popup = try XCTUnwrap(companion.popup)
        XCTAssertTrue(returned === popup.webView)
    }

    /// A sign-in window that closes itself when it is done goes away.
    func testAWindowThatClosesItselfLeaves() throws {
        let workspace = try makeSurfaceTestWorkspace(assistantPopups: .overAssistant)
        let companion = workspace.aiCompanion
        companion.show()
        _ = try XCTUnwrap(companion.session).onRequestPopupWebView?(WKWebViewConfiguration())
        let popup = try XCTUnwrap(companion.popup)

        popup.webViewDidClose(popup.webView)

        XCTAssertNil(companion.popup)
    }

    /// The window belongs to the assistant, so closing the assistant closes it.
    func testClosingTheAssistantClosesItsWindow() throws {
        let workspace = try makeSurfaceTestWorkspace(assistantPopups: .overAssistant)
        let companion = workspace.aiCompanion
        companion.show()
        _ = try XCTUnwrap(companion.session).onRequestPopupWebView?(WKWebViewConfiguration())
        XCTAssertNotNil(companion.popup)

        companion.closeColumn(companion.tool)

        XCTAssertNil(companion.popup)
    }
```

- [ ] **Step 2: Watch them fail**

Run the shared class on the Mac with `--filter CompanionBehaviorTests`.
Expected: build error `cannot find type 'AssistantPopupPlacement' in scope`.

- [ ] **Step 3: Implement**

Create `AssistantPopupPlacement.swift`:

```swift
/// Where a window the assistant's page opens is shown — `window.open`, which
/// is how a provider's sign-in works.
///
/// The host decides, the way it supplies how pages are shared: a Mac window
/// has room to show the tab such a window becomes, while on a phone the
/// assistant covers the page area and that tab would sit invisibly behind it.
public enum AssistantPopupPlacement {
    /// A tab of its own, selected. The Mac's behaviour.
    case tab
    /// Over the assistant, held by the companion as `popup`. The phone's.
    case overAssistant
}
```

In `BrowserSession.swift`:
1. After `public var onCompletedVisit: ((String, String) -> Void)?`, add:

```swift
    /// A page calling `window.close()` on itself: in practice, a sign-in window
    /// that has finished. Only a host showing such windows somewhere it can
    /// take them away sets this; a tab ignores the request, as it always has.
    public var onRequestClose: (() -> Void)?
```

2. In `teardown()`, after `onCompletedVisit = nil`, add `onRequestClose = nil`.
3. In the `WKUIDelegate` extension, directly after the `createWebViewWith` method's closing brace, add:

```swift
    public func webViewDidClose(_ webView: WKWebView) {
        onRequestClose?()
    }
```

In `AICompanion.swift`:
1. After `@Published public private(set) var live: [String: BrowserSession] = [:]`, add:

```swift
    /// A window the assistant's page opened, shown over it: a provider's
    /// sign-in, in practice. Only a host asking for `.overAssistant` ever
    /// sets this; on the Mac such windows are tabs.
    @Published public private(set) var popup: BrowserSession?
```

2. Replace `hide()` with:

```swift
    /// Closed by the person. Deliberate, so widening the window later must not
    /// bring it back. Its window goes with it: a sign-in belongs to the
    /// assistant it was opened from.
    func hide() {
        hiddenBecauseThereWasNoRoom = false
        isVisible = false
        dismissPopup()
    }
```

3. In `makeRoomForPage()`, inside `guard canShareWindow else {`, add `dismissPopup()` as the branch's first line.
4. In `teardown()`, add `dismissPopup()` as its first line.
5. Before `// MARK: - Keeping two`, add:

```swift
    // MARK: - Windows the assistant opens

    /// Shows a window the assistant's page opened, over the assistant. One at
    /// a time: a second replaces the first. It goes away when it closes itself.
    public func presentPopup(_ session: BrowserSession) {
        dismissPopup()
        session.onRequestClose = { [weak self, weak session] in
            guard let self, let session, self.popup === session else { return }
            self.dismissPopup()
        }
        popup = session
    }

    public func dismissPopup() {
        popup?.teardown()
        popup = nil
    }
```

In `BrowserWorkspace.swift`:
1. After `private var aiCompanionSubscription: AnyCancellable?`, add:

```swift
    /// Where a window the assistant's page opens is shown.
    private let assistantPopups: AssistantPopupPlacement
```

2. Add the init's last parameter, after `websiteDataStore: WKWebsiteDataStore? = nil`:

```swift
        websiteDataStore: WKWebsiteDataStore? = nil,
        /// The Mac keeps the default, a tab. The phone, where the assistant
        /// covers the page, asks for `.overAssistant`.
        assistantPopups: AssistantPopupPlacement = .tab
```

3. After `self.isPrivate = isPrivate` in the init body, add `self.assistantPopups = assistantPopups`.
4. In `aiCompanionSubscription`'s sink, replace

```swift
                session.onRequestPopupWebView = { [weak self] configuration in
                    self?.adoptPopupTab(configuration: configuration, isPrivate: self?.isPrivate ?? false)
                }
```

with

```swift
                session.onRequestPopupWebView = { [weak self] configuration in
                    self?.openAssistantPopup(configuration: configuration)
                }
```

5. Directly above `private func adoptPopupTab`, add:

```swift
    /// A window the assistant's page opened: a tab where there is room to see
    /// one, or over the assistant where the assistant covers the page. Either
    /// way it adopts WebKit's configuration, which keeps `window.opener`
    /// connected so a sign-in can report back to the page that started it.
    private func openAssistantPopup(configuration: WKWebViewConfiguration) -> WKWebView {
        switch assistantPopups {
        case .tab:
            return adoptPopupTab(configuration: configuration, isPrivate: isPrivate)
        case .overAssistant:
            let popup = BrowserSession(
                platform: makeSessionPlatform(),
                downloadCenter: downloads,
                searchSettings: searchSettings,
                isPrivate: isPrivate,
                contentBlocking: contentBlocking,
                favicons: favicons,
                adoptingPopupConfiguration: configuration
            )
            // A link inside it still belongs in a tab, like any link from the
            // assistant.
            popup.onRequestNewTab = { [weak self] url in
                self?.addTab(url: url, isPrivate: self?.isPrivate ?? false)
            }
            aiCompanion.presentPopup(popup)
            return popup.webView
        }
    }
```

- [ ] **Step 4: Run them**

Run the class with `--filter CompanionBehaviorTests`. Expected: 13 tests, 0 failures (9 before, 4 new).

- [ ] **Step 5: Break it on purpose**

In `openAssistantPopup`, make `.overAssistant` return `adoptPopupTab(configuration: configuration, isPrivate: isPrivate)`. Expected: `testWhenAskedAWindowTheAssistantOpensIsShownOverIt` fails on the tab count. Restore.

- [ ] **Step 6: Run the Mac suite, then commit**

Expected: 521 executed, 0 failures.

```bash
git add macos/LimeghostBrowser/Sources/LimeghostShared/AssistantPopupPlacement.swift macos/LimeghostBrowser/Sources/LimeghostShared/BrowserSession.swift macos/LimeghostBrowser/Sources/LimeghostShared/AICompanion.swift macos/LimeghostBrowser/Sources/LimeghostShared/BrowserWorkspace.swift macos/LimeghostBrowser/Tests/LimeghostSharedTests/CompanionBehaviorTests.swift
git commit -m "Show a window the assistant opens over it when the host asks"   # plus the attribution lines
git push origin feature/ios-pocket-browser
```

---

### Task 2: Reopening a page whose process ended (shared)

**Files:**
- Modify: `…/LimeghostShared/BrowserSession.swift`, `…/AICompanion.swift`
- Test: `CompanionBehaviorTests.swift`

**Interfaces:**
- Produces:
  - `BrowserSession.onWebContentProcessTerminated: (() -> Void)?`;
  - `AICompanion.init(tool:makeSession:rememberChoice:now:)`, with `now: @escaping () -> Date = { Date() }`;
  - `AICompanion.automaticReopenInterval` (30).

- [ ] **Step 1: Write the failing tests**

Add to `CompanionBehaviorTests`:

```swift
    /// iOS ends the page process of an app in the background. An assistant on
    /// screen reopens its conversation's own address instead of going blank.
    func testAnAssistantOnScreenWhosePageEndedReopensItsConversation() throws {
        let companion = try makeCompanion()
        companion.show()
        let session = try XCTUnwrap(companion.session)
        let address = session.currentURLString

        session.webViewWebContentProcessDidTerminate(session.webView)

        XCTAssertEqual(session.loadState, .loading, "the assistant stayed on its failure")
        XCTAssertEqual(session.currentURLString, address)
    }

    /// A hidden assistant is not reloaded where nobody can see it: it reopens
    /// when it is shown, and keeps its session.
    func testAHiddenAssistantWhosePageEndedReopensWhenShown() throws {
        let companion = try makeCompanion()
        companion.show()
        let session = try XCTUnwrap(companion.session)
        companion.hide()

        session.webViewWebContentProcessDidTerminate(session.webView)
        guard case .failed = session.loadState else {
            return XCTFail("a hidden assistant was reloaded at once")
        }

        companion.show()

        XCTAssertEqual(session.loadState, .loading)
        XCTAssertTrue(companion.session === session, "showing it started a new conversation")
    }

    /// A page that ends again straight after being reopened is left showing
    /// its failure; one that ends again later is reopened again.
    func testAPageThatKeepsEndingIsNotReopenedForever() throws {
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let companion = try makeCompanion(now: { clock })
        companion.show()
        let session = try XCTUnwrap(companion.session)

        session.webViewWebContentProcessDidTerminate(session.webView)
        XCTAssertEqual(session.loadState, .loading, "the first ending was not reopened")

        clock.addTimeInterval(5)
        session.webViewWebContentProcessDidTerminate(session.webView)
        guard case .failed = session.loadState else {
            return XCTFail("a page ending again at once was reopened again")
        }

        clock.addTimeInterval(AICompanion.automaticReopenInterval)
        session.webViewWebContentProcessDidTerminate(session.webView)
        XCTAssertEqual(session.loadState, .loading, "a page that ended again much later was left on its failure")
    }

    /// A companion on its own, with sessions that load nothing real and a
    /// clock the test controls.
    private func makeCompanion(now: @escaping () -> Date = { Date() }) throws -> AICompanion {
        let suiteName = "clearframe.companionRecovery.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { TestSuiteCleanup.destroy(suiteName, defaults: defaults) }
        let search = SearchSettingsStore(defaults: defaults)
        let companion = AICompanion(
            tool: try XCTUnwrap(AICompanion.choices.first),
            makeSession: { _, url in
                BrowserSession(
                    platform: RecordingPlatform(),
                    downloadCenter: NoDownloads(),
                    searchSettings: search,
                    initialURL: url
                )
            },
            rememberChoice: { _ in },
            now: now
        )
        addTeardownBlock { companion.teardown() }
        return companion
    }
```

- [ ] **Step 2: Watch them fail**

Expected: build error `extra argument 'now' in call`.

- [ ] **Step 3: Implement**

In `BrowserSession.swift`:
1. After `onRequestClose`, add:

```swift
    /// WebKit ended this page's process. The session records the failure
    /// itself; this tells whoever can do better than show it, like the
    /// assistant, which reopens its conversation.
    public var onWebContentProcessTerminated: (() -> Void)?
```

2. In `webViewWebContentProcessDidTerminate(_:)`, after the `loadState = .failed(…)` assignment, add `onWebContentProcessTerminated?()`.
3. In `teardown()`, after `onRequestClose = nil`, add `onWebContentProcessTerminated = nil`.

In `AICompanion.swift`:
1. After `static let maximumLiveSessions = 2`, add:

```swift
    /// How soon after an automatic reopen a page that ends again is left
    /// showing its failure: a page that dies as it loads would otherwise
    /// reload forever.
    static let automaticReopenInterval: TimeInterval = 30
```

2. After `private var hiddenBecauseThereWasNoRoom = false`, add:

```swift
    /// Assistants whose page process ended while they were hidden. Each
    /// reopens its conversation when it is next shown.
    private var awaitingReopen: Set<String> = []
    private var lastAutomaticReopen: [String: Date] = [:]
    private let now: () -> Date
```

3. Replace the init with:

```swift
    public init(
        tool: AIToolListing,
        makeSession: @escaping (AIToolListing, URL) -> BrowserSession,
        rememberChoice: @escaping (String) -> Void,
        now: @escaping () -> Date = { Date() }
    ) {
        self.tool = tool
        self.makeSession = makeSession
        self.rememberChoice = rememberChoice
        self.now = now
    }
```

4. Replace `load(_:)` with:

```swift
    private func load(_ choice: AIToolListing) {
        touch(choice.id)
        if live[choice.id] == nil {
            let session = makeSession(choice, parked[choice.id] ?? choice.officialURL)
            session.onWebContentProcessTerminated = { [weak self] in
                self?.pageEnded(for: choice.id)
            }
            live[choice.id] = session
            parked[choice.id] = nil
        } else if awaitingReopen.contains(choice.id) {
            reopen(choice.id)
        }
        evictBeyondLimit()
    }

    /// WebKit ended an assistant's page, as iOS routinely does to an app in
    /// the background. On screen it reopens now; hidden, when next shown.
    private func pageEnded(for id: String) {
        if let last = lastAutomaticReopen[id], now().timeIntervalSince(last) < Self.automaticReopenInterval {
            return
        }
        if isVisible, shown.contains(id) {
            reopen(id)
        } else {
            awaitingReopen.insert(id)
        }
    }

    /// Reopens the conversation's own address, the way a parked assistant is
    /// reopened, rather than starting a new one.
    private func reopen(_ id: String) {
        awaitingReopen.remove(id)
        guard let session = live[id] else { return }
        let listing = [tool, comparisonTool].compactMap { $0 }.first(where: { $0.id == id })
            ?? Self.choices.first(where: { $0.id == id })
        let conversation = URL(string: session.currentURLString).flatMap { $0.scheme?.hasPrefix("http") == true ? $0 : nil }
        guard let address = conversation ?? listing?.officialURL else { return }
        lastAutomaticReopen[id] = now()
        session.load(address)
    }
```

5. In `evictBeyondLimit()`, after `recency.removeAll { $0 == id }`, add `awaitingReopen.remove(id)`.
6. In `teardown()`, after `recency = []`, add `awaitingReopen = []`.

- [ ] **Step 4: Run them**

Expected: `CompanionBehaviorTests` 16 tests, 0 failures.

- [ ] **Step 5: Break it on purpose**

In `pageEnded(for:)`, replace the `if isVisible, shown.contains(id) { … } else { … }` with `awaitingReopen.insert(id)`. Expected: `testAnAssistantOnScreenWhosePageEndedReopensItsConversation` and the first assertion of `testAPageThatKeepsEndingIsNotReopenedForever` fail. Restore.

- [ ] **Step 6: Run the Mac suite, then commit**

Expected: 524 executed, 0 failures.

```bash
git add macos/LimeghostBrowser/Sources/LimeghostShared/BrowserSession.swift macos/LimeghostBrowser/Sources/LimeghostShared/AICompanion.swift macos/LimeghostBrowser/Tests/LimeghostSharedTests/CompanionBehaviorTests.swift
git commit -m "Reopen an assistant's conversation when its page process ends"   # plus the attribution lines
git push origin feature/ios-pocket-browser
```

---

### Task 3: The Safari version a phone claims (shared)

**Files:**
- Modify: `macos/LimeghostBrowser/Sources/LimeghostShared/BrowserUserAgent.swift`
- Create: `macos/LimeghostBrowser/Tests/LimeghostSharedTests/BrowserUserAgentTests.swift`

**Interfaces:**
- Produces: `static func fallbackVersion(for system: OperatingSystemVersion) -> String`. `fallbackSafariVersion` becomes computed.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import XCTest
@testable import LimeghostShared

final class BrowserUserAgentTests: XCTestCase {
    /// Where there is no Safari to read, which is every iPhone, the version
    /// claimed is the operating system's own: on iOS, Safari ships with the
    /// system. It used to be a fixed "26.5" whatever the phone ran. The test
    /// hands in iOS 18.7.8 because this Mac runs macOS 26.5, where the old
    /// constant happened to be right.
    func testWithNoSafariToReadTheVersionIsTheSystemsOwn() {
        let phone = OperatingSystemVersion(majorVersion: 18, minorVersion: 7, patchVersion: 8)
        XCTAssertEqual(BrowserUserAgent.fallbackVersion(for: phone), "18.7")
        XCTAssertEqual(
            BrowserUserAgent.fallbackSafariVersion,
            BrowserUserAgent.fallbackVersion(for: ProcessInfo.processInfo.operatingSystemVersion)
        )
    }
}
```

- [ ] **Step 2: Watch it fail**

Expected: build error `type 'BrowserUserAgent' has no member 'fallbackVersion'`.

- [ ] **Step 3: Implement**

Replace

```swift
    /// Used only when Safari cannot be read — a restricted sandbox, or a Mac
    /// without it. Keep it recent when this file is touched.
    static let fallbackSafariVersion = "26.5"
```

with

```swift
    /// Used when Safari cannot be read: always on a phone, which has no
    /// Safari.app to read, and on a Mac only in a restricted sandbox. On iOS
    /// Safari ships with the system, so the system's version is Safari's; it
    /// used to be a fixed "26.5" whatever the phone ran.
    static var fallbackSafariVersion: String {
        fallbackVersion(for: ProcessInfo.processInfo.operatingSystemVersion)
    }

    static func fallbackVersion(for system: OperatingSystemVersion) -> String {
        "\(system.majorVersion).\(system.minorVersion)"
    }
```

- [ ] **Step 4: Run it**, with `--filter BrowserUserAgentTests`. Expected: 1 test, 0 failures.

- [ ] **Step 5: Break it on purpose**

Make `fallbackVersion(for:)` return `"26.5"`. Expected: the test fails, `"26.5"` against `"18.7"`. Restore.

- [ ] **Step 6: Mac suite, commit**

Expected: 525 executed, 0 failures.

```bash
git add macos/LimeghostBrowser/Sources/LimeghostShared/BrowserUserAgent.swift macos/LimeghostBrowser/Tests/LimeghostSharedTests/BrowserUserAgentTests.swift
git commit -m "Claim the Safari version the phone's own iOS carries"   # plus the attribution lines
git push origin feature/ios-pocket-browser
```

---

### Task 4: The phone's assistant model

**Files:**
- Modify: `ios/Sources/WorkspaceHost.swift`, `ios/Sources/PageMenu.swift`, `ios/Sources/BottomBar.swift` (model only)
- Create: `ios/Tests/AssistantOnThePhoneTests.swift`
- Modify: `ios/Tests/BottomBarTests.swift`, `ios/Limeghost.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: Task 1's `AssistantPopupPlacement`, `popup`; `AICompanion.toggle()`, `makeRoomForPage()`, `setCanShareWindow(_:)`.
- Produces: `BottomBarModel.isAssistantOpen: Bool` (default `false`), `BottomBarModel.assistantLabel: String`, `PageMenuActions.openOrCloseReader()`.

- [ ] **Step 1: Write the failing tests**

Create `ios/Tests/AssistantOnThePhoneTests.swift`:

```swift
import Combine
import UIKit
import WebKit
import XCTest
@testable import Limeghost
@testable import LimeghostShared

@MainActor
final class AssistantOnThePhoneTests: XCTestCase {
    private func makeHost() throws -> WorkspaceHost {
        let suiteName = "clearframe.iosAssistant.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return WorkspaceHost.forTesting(defaults: defaults)
    }

    // MARK: - The assistant and the page

    /// A phone never has room for the page and the assistant at once, so
    /// asking for a page makes the assistant leave rather than shrink, and
    /// the conversation stays loaded.
    func testAskingForAPageMakesTheAssistantLeave() throws {
        let host = try makeHost()
        let companion = host.workspace.aiCompanion
        companion.toggle()
        XCTAssertTrue(companion.isVisible)

        host.workspace.open("https://example.com/")

        XCTAssertFalse(companion.isVisible, "the page opened behind the assistant")
        XCTAssertNotNil(companion.session, "leaving threw the conversation away")
    }

    /// The host hears the assistant open; otherwise the bar's button never lights.
    func testTheHostHearsTheAssistantOpen() throws {
        let host = try makeHost()
        var heard = false
        let subscription = host.objectWillChange.sink { _ in heard = true }
        defer { subscription.cancel() }

        host.workspace.aiCompanion.toggle()

        XCTAssertTrue(heard)
    }

    /// Reader shows the page the assistant covers, so opening it uncovers the page.
    func testReaderFromTheMenuUncoversThePage() async throws {
        let host = try makeHost()
        let companion = host.workspace.aiCompanion
        companion.toggle()

        await PageMenuActions(workspace: host.workspace).perform(.reader)

        XCTAssertFalse(companion.isVisible)
    }

    /// Find in Page likewise: a match highlighted under the assistant helps nobody.
    func testFindInPageFromTheMenuUncoversThePage() async throws {
        let host = try makeHost()
        let companion = host.workspace.aiCompanion
        companion.toggle()

        await PageMenuActions(workspace: host.workspace).perform(.find)

        XCTAssertFalse(companion.isVisible)
    }

    /// On the phone a sign-in window opens over the assistant, not as a tab
    /// hidden behind it.
    func testThePhoneShowsSignInWindowsOverTheAssistant() throws {
        let host = try makeHost()
        let companion = host.workspace.aiCompanion
        companion.toggle()
        let tabsBefore = host.workspace.visibleTabs.count

        _ = try XCTUnwrap(companion.session).onRequestPopupWebView?(WKWebViewConfiguration())

        XCTAssertNotNil(companion.popup)
        XCTAssertEqual(host.workspace.visibleTabs.count, tabsBefore)
    }
}
```

Add to `BottomBarTests`:

```swift
    /// The assistant button says what a tap will do next, as the menu's labels do.
    func testTheAssistantButtonSaysWhatATapWillDo() {
        XCTAssertEqual(BottomBarModel(urlString: "", tabCount: 1, canGoBack: false).assistantLabel, "Show Assistant")
        XCTAssertEqual(
            BottomBarModel(urlString: "", tabCount: 1, canGoBack: false, isAssistantOpen: true).assistantLabel,
            "Hide Assistant"
        )
    }
```

Add the test file to the project: `python3 "$TMPDIR/pbx_add.py" AssistantOnThePhoneTests.swift AssistantOnThePhoneTests.swift AA000000000000000000220D AA000000000000000000210D HistorySheetTests.swift`.

- [ ] **Step 2: Watch them fail**

Run the phone suite with `-only-testing:LimeghostTests/AssistantOnThePhoneTests -only-testing:LimeghostTests/BottomBarTests`.
Expected: build error `value of type 'BottomBarModel' has no member 'assistantLabel'`.

- [ ] **Step 3: Implement**

`BottomBarModel` — after `let canGoBack: Bool`, add:

```swift
    /// Lit while the assistant is open, as the Mac's toolbar button is.
    var isAssistantOpen: Bool = false

    /// What the button does next, for VoiceOver, as the menu's labels say.
    var assistantLabel: String { isAssistantOpen ? "Hide Assistant" : "Show Assistant" }
```

`WorkspaceHost` — replace `private var cancellable: AnyCancellable?` and the private init with:

```swift
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
```

In both `live()` and `forTesting(defaults:)`, add `assistantPopups: .overAssistant` as the last argument to `BrowserWorkspace(…)`, and document it in `live()`'s comment: "sign-in windows open over the assistant, which covers the page".

`PageMenuActions.perform` — replace `case .reader: await workspace.toggleReaderInSelectedTab()` with `case .reader: await openOrCloseReader()`, and `case .find: workspace.findInSelectedTab()` with:

```swift
        case .find:
            // Find highlights a match on the page, which the assistant covers.
            workspace.aiCompanion.makeRoomForPage()
            workspace.findInSelectedTab()
```

and add below `perform`:

```swift
    /// Reader shows the page's text, which the assistant would be covering,
    /// so opening it uncovers the page first. Closing it asks for nothing.
    func openOrCloseReader() async {
        if workspace.selectedTab?.readerArticle == nil {
            workspace.aiCompanion.makeRoomForPage()
        }
        await workspace.toggleReaderInSelectedTab()
    }
```

- [ ] **Step 4: Run them**

Expected: `AssistantOnThePhoneTests` 5 tests and `BottomBarTests` 4 tests, 0 failures.

- [ ] **Step 5: Break it on purpose**

Remove the `setCanShareWindow(false)` line. Expected: `testAskingForAPageMakesTheAssistantLeave` fails. The assistant only un-expands and stays covering the page. Restore.

- [ ] **Step 6: Whole phone suite, commit**

Expected: 79 executed, 0 failures.

```bash
git add ios/Sources/WorkspaceHost.swift ios/Sources/PageMenu.swift ios/Sources/BottomBar.swift ios/Tests/AssistantOnThePhoneTests.swift ios/Tests/BottomBarTests.swift ios/Limeghost.xcodeproj/project.pbxproj
git commit -m "Give the phone's assistant its model: never beside the page, sign-in over it"   # plus the attribution lines
git push origin feature/ios-pocket-browser
```

---

### Task 5: Layout rules and the keyboard

**Files:**
- Create: `ios/Sources/AssistantLayer.swift` (the pure rule only, for now) and `ios/Sources/KeyboardObserver.swift`
- Modify: `ios/Sources/BrowserScreen.swift` (two pure enums), `ios/Tests/AssistantOnThePhoneTests.swift`, `project.pbxproj`

**Interfaces:**
- Produces:
  - `enum AssistantDismissal { static func closes(translation: CGFloat, predictedEnd: CGFloat) -> Bool }`;
  - `enum NoticePlacement { case overThePage, aboveTheBar; static func forAssistant(isOpen: Bool) -> NoticePlacement }`;
  - `enum BottomChromeContent { case findBar, bar, nothing; static func showing(isFinding: Bool, keyboardIsUp: Bool) -> BottomChromeContent }`;
  - `@MainActor final class KeyboardObserver: ObservableObject { @Published private(set) var isUp: Bool; init(center: NotificationCenter = .default) }`.

- [ ] **Step 1: Write the failing tests**

Append to `AssistantOnThePhoneTests`:

```swift
    // MARK: - Layout rules

    /// A small drag leaves the assistant where it is; a long or a flung one
    /// closes it; dragging up never does.
    func testSwipingDownFarOrFastClosesTheAssistant() {
        XCTAssertFalse(AssistantDismissal.closes(translation: 40, predictedEnd: 90))
        XCTAssertTrue(AssistantDismissal.closes(translation: 130, predictedEnd: 140))
        XCTAssertTrue(AssistantDismissal.closes(translation: 60, predictedEnd: 320))
        XCTAssertFalse(AssistantDismissal.closes(translation: -50, predictedEnd: -200))
    }

    /// While the assistant is open, a notice gets its own strip above the bar.
    /// Floating over the assistant, it landed on the provider's message box.
    func testANoticeNeverCoversTheAssistant() {
        XCTAssertEqual(NoticePlacement.forAssistant(isOpen: false), .overThePage)
        XCTAssertEqual(NoticePlacement.forAssistant(isOpen: true), .aboveTheBar)
    }

    /// The find bar stays while finding, because it needs the keyboard. The
    /// bar steps aside while anything else is typed, as Safari's does.
    func testTheBarStepsAsideWhileTyping() {
        XCTAssertEqual(BottomChromeContent.showing(isFinding: false, keyboardIsUp: false), .bar)
        XCTAssertEqual(BottomChromeContent.showing(isFinding: false, keyboardIsUp: true), .nothing)
        XCTAssertEqual(BottomChromeContent.showing(isFinding: true, keyboardIsUp: true), .findBar)
    }

    /// The observer follows the system's own keyboard notifications.
    func testTheKeyboardObserverFollowsTheSystem() {
        let center = NotificationCenter()
        let keyboard = KeyboardObserver(center: center)
        XCTAssertFalse(keyboard.isUp)

        center.post(name: UIResponder.keyboardWillShowNotification, object: nil)
        XCTAssertTrue(keyboard.isUp)

        center.post(name: UIResponder.keyboardWillHideNotification, object: nil)
        XCTAssertFalse(keyboard.isUp)
    }
```

Add the two source files to the project:

```bash
touch ios/Sources/AssistantLayer.swift ios/Sources/KeyboardObserver.swift
python3 "$TMPDIR/pbx_add.py" AssistantLayer.swift AssistantLayer.swift AA0000000000000000000214 AA0000000000000000000113 HistorySheet.swift
python3 "$TMPDIR/pbx_add.py" KeyboardObserver.swift KeyboardObserver.swift AA0000000000000000000215 AA0000000000000000000114 AssistantLayer.swift
```

- [ ] **Step 2: Watch them fail**

Expected: build error `cannot find 'AssistantDismissal' in scope`.

- [ ] **Step 3: Implement**

`ios/Sources/AssistantLayer.swift`:

```swift
import LimeghostCore
import LimeghostShared
import SwiftUI

/// Whether a drag down on the assistant's header closes it: far enough that
/// it was meant, or fast enough that it was flung.
enum AssistantDismissal {
    static let distance: CGFloat = 120
    static let flung: CGFloat = 300

    static func closes(translation: CGFloat, predictedEnd: CGFloat) -> Bool {
        translation >= distance || predictedEnd >= flung
    }
}
```

`ios/Sources/KeyboardObserver.swift`:

```swift
import Combine
import UIKit

/// Whether the software keyboard is on screen, from the system's own
/// notifications. The bar steps out of its way while it is.
@MainActor
final class KeyboardObserver: ObservableObject {
    @Published private(set) var isUp = false
    private var subscriptions: Set<AnyCancellable> = []

    init(center: NotificationCenter = .default) {
        center.publisher(for: UIResponder.keyboardWillShowNotification)
            .sink { [weak self] _ in self?.isUp = true }
            .store(in: &subscriptions)
        center.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] _ in self?.isUp = false }
            .store(in: &subscriptions)
    }
}
```

In `BrowserScreen.swift`, above `struct BottomChrome`, add:

```swift
/// Where a page notice goes. Over the page while the assistant is closed, as
/// always. While it is open, in its own strip above the bar: floating over the
/// assistant, the banner landed exactly on the provider's message box, the one
/// place a person taps to paste. It is never put under the provider's header,
/// where "Copied 812 words." could read as the provider having received them.
enum NoticePlacement: Equatable {
    case overThePage, aboveTheBar

    static func forAssistant(isOpen: Bool) -> NoticePlacement {
        isOpen ? .aboveTheBar : .overThePage
    }
}

/// What sits along the bottom: the find bar while finding, which needs the
/// keyboard; nothing while anything else is typed, as Safari's bar steps
/// aside, so a conversation keeps the room; the bar the rest of the time.
enum BottomChromeContent: Equatable {
    case findBar, bar, nothing

    static func showing(isFinding: Bool, keyboardIsUp: Bool) -> BottomChromeContent {
        if isFinding { return .findBar }
        return keyboardIsUp ? .nothing : .bar
    }
}
```

- [ ] **Step 4: Run them.** Expected: `AssistantOnThePhoneTests` 9 tests, 0 failures.

- [ ] **Step 5: Break it on purpose**

In `BottomChromeContent.showing`, check `keyboardIsUp` before `isFinding`. Expected: `testTheBarStepsAsideWhileTyping` fails on the third assertion. Restore.

- [ ] **Step 6: Whole phone suite, commit**

Expected: 83 executed, 0 failures.

```bash
git add ios/Sources/AssistantLayer.swift ios/Sources/KeyboardObserver.swift ios/Sources/BrowserScreen.swift ios/Tests/AssistantOnThePhoneTests.swift ios/Limeghost.xcodeproj/project.pbxproj
git commit -m "Add the phone assistant's layout rules and a keyboard observer"   # plus the attribution lines
git push origin feature/ios-pocket-browser
```

---

### Task 6: The assistant layer and the bar button

**Files:**
- Modify: `ios/Sources/AssistantLayer.swift` (append the views), `ios/Sources/BottomBar.swift` (the button), `ios/Sources/NoticeBanner.swift` (placement), `ios/Sources/BrowserScreen.swift` (layout)

No new unit tests: these are views over tested rules. Task 7 checks them by eye.

- [ ] **Step 1: Append the views to `AssistantLayer.swift`**

```swift
/// Your own assistant, over the page. It is always in the same place in the
/// view tree and draws nothing while hidden: one layer in one place, never a
/// sheet. A sheet hosts its content in a separate hierarchy, which moves the
/// provider's web view between hosts, the destroy-and-rebuild `CLAUDE.md`
/// records.
struct AssistantLayer: View {
    @ObservedObject var companion: AICompanion
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            if companion.isVisible {
                Color.black.opacity(0.45)
                    .transition(.opacity)
                panel
                    .padding(.top, 10)
                    .offset(y: dragOffset)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeOut(duration: 0.22), value: companion.isVisible)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            AssistantHeader(companion: companion)
                .gesture(dismissDrag)
            Rectangle()
                .fill(LimeghostTheme.hairline2)
                .frame(height: 1)
            if let session = companion.session(for: companion.tool) {
                AssistantPageView(session: session)
                    .id(session.instanceID)
            } else {
                LimeghostTheme.bg1
            }
        }
        .background(LimeghostTheme.bg1)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: LimeghostTheme.radius14,
                topTrailingRadius: LimeghostTheme.radius14,
                style: .continuous
            )
        )
        .overlay {
            if let popup = companion.popup {
                AssistantPopupLayer(session: popup) { companion.dismissPopup() }
                    .id(popup.instanceID)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeOut(duration: 0.22), value: companion.popup?.instanceID)
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                if AssistantDismissal.closes(
                    translation: value.translation.height,
                    predictedEnd: value.predictedEndTranslation.height
                ) {
                    companion.closeColumn(companion.tool)
                }
                withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
            }
    }
}

/// Which assistant, whose account, and a way to close, in Reader's touch
/// header's anatomy. Never a page action: a Copy button here would read as
/// "send this to ChatGPT" (`CLAUDE.md`).
struct AssistantHeader: View {
    @ObservedObject var companion: AICompanion

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.28))
                .frame(width: 36, height: 5)
                .padding(.top, 6)
                .accessibilityHidden(true)
            HStack(spacing: 10) {
                SiteIconView(urlString: companion.tool.officialURL.absoluteString)
                Menu {
                    ForEach(AICompanion.choices) { choice in
                        Button {
                            companion.select(choice)
                        } label: {
                            if choice.id == companion.tool.id {
                                Label(choice.name, systemImage: "checkmark")
                            } else {
                                Text(choice.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(companion.tool.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(LimeghostTheme.textPrimary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(LimeghostTheme.textTertiary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Choose your assistant")
                .accessibilityValue(companion.tool.name)
                Spacer(minLength: 12)
                Text("your own account")
                    .font(.system(size: 13))
                    .foregroundStyle(LimeghostTheme.textTertiary)
                    .lineLimit(1)
                Button {
                    companion.closeColumn(companion.tool)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LimeghostTheme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(LimeghostTheme.bg3, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close the assistant")
            }
            .padding(.leading, 16)
            .padding(.trailing, 4)
        }
        .padding(.bottom, 4)
        .background(LimeghostTheme.bg2)
    }
}

/// The provider's own website, with a failure drawn over it rather than in
/// its place, so the web view stays mounted and a reload keeps it.
struct AssistantPageView: View {
    @ObservedObject var session: BrowserSession

    var body: some View {
        WebViewHost(session: session)
            .overlay {
                if case .failed(let failure) = session.loadState {
                    AssistantFailure(failure: failure) { session.reload() }
                }
            }
    }
}

/// What the session says went wrong, in its own words, with Reload where a
/// retry can help.
private struct AssistantFailure: View {
    let failure: BrowserFailure
    let reload: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.bubble")
                .font(.system(size: 28))
                .foregroundStyle(LimeghostTheme.textTertiary)
            Text(failure.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LimeghostTheme.textPrimary)
                .multilineTextAlignment(.center)
            Text(failure.message)
                .font(.system(size: 15))
                .foregroundStyle(LimeghostTheme.textSecondary)
                .multilineTextAlignment(.center)
            if failure.retryable {
                Button(action: reload) {
                    Label {
                        Text("Reload").foregroundStyle(LimeghostTheme.textPrimary)
                    } icon: {
                        Image(systemName: "arrow.clockwise").foregroundStyle(LimeghostTheme.accent)
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
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LimeghostTheme.bg1)
    }
}

/// A window the assistant's page opened (a sign-in, in practice) over the
/// assistant: its own page's title and host, and a way to close.
struct AssistantPopupLayer: View {
    @ObservedObject var session: BrowserSession
    let close: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.5)
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: 36, height: 5)
                        .padding(.top, 6)
                        .accessibilityHidden(true)
                    HStack(spacing: 10) {
                        SiteIconView(urlString: session.currentURLString)
                        Text(session.pageTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(LimeghostTheme.textPrimary)
                            .lineLimit(1)
                        Text(URL(string: session.currentURLString)?.host ?? "")
                            .font(.system(size: 13))
                            .foregroundStyle(LimeghostTheme.textSecondary)
                            .lineLimit(1)
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
                        .accessibilityLabel("Close this window")
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 4)
                }
                .padding(.bottom, 4)
                .background(LimeghostTheme.bg2)
                Rectangle()
                    .fill(LimeghostTheme.hairline2)
                    .frame(height: 1)
                WebViewHost(session: session)
            }
            .background(LimeghostTheme.bg1)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: LimeghostTheme.radius14,
                    topTrailingRadius: LimeghostTheme.radius14,
                    style: .continuous
                )
            )
            .padding(.top, 26)
        }
    }
}
```

- [ ] **Step 2: The button**

In `BottomBar`, add `let toggleAssistant: () -> Void` directly after `let openAddress: () -> Void`. Replace the reserved-place comment block (`// The assistant toggle belongs here, …`) with:

```swift
            // Your own assistant, lit while it is open, as the Mac's toolbar
            // button is. Unlit it takes the bar's tint, like its neighbours,
            // until the phone's look is designed.
            Button(action: toggleAssistant) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 17))
                    .foregroundStyle(
                        model.isAssistantOpen ? AnyShapeStyle(LimeghostTheme.onAccent) : AnyShapeStyle(TintShapeStyle())
                    )
                    .frame(width: 38, height: 38)
                    .background(
                        model.isAssistantOpen ? LimeghostTheme.accent : Color.clear,
                        in: RoundedRectangle(cornerRadius: LimeghostTheme.radius8)
                    )
                    .frame(width: 44, height: 38)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(model.assistantLabel)
```

Change the view's doc comment to "Back, the address, your assistant, the tabs and the page menu".

- [ ] **Step 3: The notice's placement**

In `NoticeBanner.swift`, give `NoticeLayer` a placement:

```swift
struct NoticeLayer: View {
    @ObservedObject var session: BrowserSession
    var placement: NoticePlacement = .overThePage

    var body: some View {
        VStack {
            if let notice = session.pageNotice {
                NoticeBanner(message: notice) { session.dismissPageNotice() }
                    .padding(.top, placement == .aboveTheBar ? 8 : 0)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: session.pageNotice)
    }
}
```

- [ ] **Step 4: The screen**

In `BrowserScreen`, add `@StateObject private var keyboard = KeyboardObserver()`. Replace the body's `VStack(spacing: 0) { … }` (everything before the first `.sheet`) with:

```swift
        VStack(spacing: 0) {
            // The page and the assistant share one place: the assistant layer
            // is always here, drawing nothing while hidden, never in a sheet.
            ZStack {
                Group {
                    if let tab = host.workspace.selectedTab {
                        TabSurface(tab: tab, workspace: host.workspace)
                    } else {
                        Color.clear
                    }
                }
                AssistantLayer(companion: host.workspace.aiCompanion)
            }
            .overlay(alignment: .bottom) {
                if noticePlacement == .overThePage, let tab = host.workspace.selectedTab {
                    NoticeLayer(session: tab.session)
                }
            }

            if noticePlacement == .aboveTheBar, let tab = host.workspace.selectedTab {
                NoticeLayer(session: tab.session, placement: .aboveTheBar)
            }

            if let tab = host.workspace.selectedTab {
                BottomChrome(find: tab.find, keyboard: keyboard, bar: bottomBar)
            } else if !keyboard.isUp {
                bottomBar
            }
        }
```

Add after `bottomBar`:

```swift
    private var noticePlacement: NoticePlacement {
        .forAssistant(isOpen: host.workspace.aiCompanion.isVisible)
    }
```

In `bottomBar`, add `isAssistantOpen: host.workspace.aiCompanion.isVisible` to the model and `toggleAssistant: { host.workspace.aiCompanion.toggle() },` after `openAddress`. Replace `BottomChrome` with:

```swift
/// The find bar, the bar, or nothing while typing (`BottomChromeContent`).
///
/// Its own view, so it can observe the tab's find controller and the
/// keyboard. `BrowserScreen` observes the workspace, and a tab's `find`
/// changes without the workspace hearing of it — the same reason `TabSurface`
/// observes its tab and session.
struct BottomChrome: View {
    @ObservedObject var find: PageFindController
    @ObservedObject var keyboard: KeyboardObserver
    let bar: BottomBar

    var body: some View {
        switch BottomChromeContent.showing(isFinding: find.isPresented, keyboardIsUp: keyboard.isUp) {
        case .findBar: FindBar(find: find)
        case .bar: bar
        case .nothing: EmptyView()
        }
    }
}
```

- [ ] **Step 5: Build and run the whole phone suite**

Expected: `** TEST SUCCEEDED **`, 83 executed, no new warnings from `ios/Sources`.

- [ ] **Step 6: Commit**

```bash
git add ios/Sources/AssistantLayer.swift ios/Sources/BottomBar.swift ios/Sources/NoticeBanner.swift ios/Sources/BrowserScreen.swift
git commit -m "Draw your own assistant over the page, with its button in the bar"   # plus the attribution lines
git push origin feature/ios-pocket-browser
```

---

### Task 7: Look at it

Nothing here is committed.

- [ ] **Step 1: Draw the real screen (throwaway)**

This follows the Bookmarks plan's Task 7 harness. It presents `BrowserScreen(host:)` in its own window from a `forTesting` host, draws the window after a pause, and writes PNGs to `TEST_RUNNER_LOOK_DIR`. Draw four states:

1. After `host.workspace.aiCompanion.toggle()` and a 4-second wait: the assistant open, with the provider's page loaded over the network.
2. After `session.webViewWebContentProcessDidTerminate(session.webView)` twice, so the second ending is left showing: the failure over the assistant.
3. After `_ = session.onRequestPopupWebView?(WKWebViewConfiguration())`: the popup layer.
4. After `host.workspace.selectedTab?.session.showPageNotice("Copied 812 words.")` with the assistant open: the strip.

Look for:
- the lit button;
- the header layout;
- the rounded top;
- the failure overlay;
- the popup offset;
- the strip pushing the assistant up.

- [ ] **Step 2: Remove the harness** and restore the project file (`git checkout -- ios/Limeghost.xcodeproj/project.pbxproj`). `git status` must be clean.

- [ ] **Step 3: On the founder's iPhone**

Build and install as `docs/ios-browser-foundation.md` records. Hand over the spec §6 by-hand list, and record only what was actually seen.

---

### Task 8: Documents, and CI

- [ ] **Step 1: Re-run every suite and take the counts.** Expected:
  - Mac 525 (Core 238, Shared 38, BrowserBehavior 249);
  - `LimeghostSharedLayer` `** TEST SUCCEEDED **` on the simulator, 276 by the list;
  - phone 83.
- [ ] **Step 2: Update the documents**
  - `docs/ios-browser-foundation.md`:
    - drop "no assistant panel" from the does-not-exist sentence, and the sentence saying nothing on screen reaches `AICompanion`;
    - add an **Your own assistant** bullet (button, layer, sign-in over it, recovery, the bar stepping aside while typing, the copy strip);
    - source files eighteen → twenty;
    - tests 73 → 83 with what they cover;
    - counts 517 → 525, 268 → 276 (238 + 38), 249 unchanged.
  - `AGENTS.md`: counts 268 → 276, 73 → 83, 517 → 525, the 30 `LimeghostSharedTests` → 38.
  - `CHANGELOG.md`: "**The phone gets your own assistant**", covering what was built, the shared additions and the counts.
  - `docs/project-context.md`: a dated note giving:
    - the four approved decisions and the three calls;
    - that the Mac's assistant gains the automatic reopen;
    - that sign-in inside the phone's web view is untested.
  - `docs/superpowers/specs/2026-09-03-ios-pocket-browser-design.md`: one amendment line under §5, pointing to the new spec's §8.
- [ ] **Step 3: Commit, push, open the pull request, watch CI.** Merging waits for the founder's word.
