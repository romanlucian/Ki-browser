# Limeghost iOS App Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an iOS app you can actually browse with — tabs, an address bar, a bottom bar, a tab switcher and the AI guide — and get it onto a real iPhone.

**Architecture:** `ios/Limeghost.xcodeproj` consumes the existing Swift package by relative path. One SwiftUI scene hosts one `BrowserWorkspace` — the same workspace the Mac drives, so every door already calls `makeRoomForPage()` and the door test already passes on a phone. iOS supplies only what `BrowserSessionPlatform` asks for. No browser logic is rewritten.

**Tech Stack:** Swift 6 toolchain in language mode 5, SwiftUI, WebKit, UIKit (only behind the platform protocol), XCTest. Xcode 26.6, iOS 26.5 simulator runtime, deployment target iOS 17.0. No third-party dependencies.

**Spec:** [docs/superpowers/specs/2026-09-03-ios-pocket-browser-design.md](../specs/2026-09-03-ios-pocket-browser-design.md) — §2 (scope), §4 (the shell), §6 (data and identity), §7.1 (distribution)

**Plan 2 of 3.** Plan 1 is complete and merged. Plan 3 adds the assistant overlay, Reader, Copy for AI and the bookmark bridge.

## Read this before Task 3: why this plan starts at Task 3

The first version of this plan had Tasks 1 and 2 create the Xcode project and the iOS platform implementation. An independent review predicted, and running it confirmed, that **the test target as described could not compile a single test — and the error it produced was the same "cannot find in scope" the plan told an executor to expect as its healthy red signal.** A broken target and real progress would have looked identical.

So Tasks 1 and 2 were **built rather than described**, and are already committed (`2731926`). What exists now:

```
ios/Limeghost.xcodeproj/project.pbxproj   app target + test target, verified
ios/Sources/LimeghostApp.swift            @main, currently shows a placeholder
ios/Sources/IOSSessionPlatform.swift      all 8 BrowserSessionPlatform members
ios/Sources/IOSCollaborators.swift        IOSClipboard, IOSPageSharing, NoDownloads
ios/Sources/Info.plist                    real plist, carries the ATS key
ios/Tests/IOSSessionPlatformTests.swift   3 tests, passing on a simulator
```

Four settings in that project are load-bearing and were absent from the description: `ENABLE_TESTABILITY = YES` on the app, `TEST_HOST` and `BUNDLE_LOADER` on the tests, and `@testable import Limeghost` in the test file. `LimeghostCore` also had to be a **second** package product dependency; the app does not get it transitively. Do not remove any of these.

**The rule this plan follows, learned the expensive way: a plan may assert only what its author performed.** Everything under "Verified" below was run. Nothing else is asserted about the codebase.

## Global Constraints

- **Deployment target iOS 17.0**, Swift language mode 5, `TARGETED_DEVICE_FAMILY = "1,2"`.
- **Bundle identifier `com.zincoo.limeghost`** for iOS; the Mac's `com.clearframe.browser` is untouched.
- **Preference keys stay `clearframe.*`** on both platforms.
- **No `#if os(...)` in `Sources/LimeghostShared/`.** Platform differences enter through protocols; iOS-only code lives in `ios/`.
- **No third-party dependencies**, including in tests and including project generators.
- **No browser logic is rewritten.** If iOS seems to need different behaviour, that is a protocol member or a shared method, not a fork.
- **Never type into an assistant, never press its send button, never read its answers.** No assistant work happens in this plan.
- **v1 runs one profile and has no downloads.**
- **Claim nothing about signing, notarization, TestFlight, App Store readiness or user validation.**
- **A test count is a check, not a target.** If correct work changes it, change it and say so.
- **Task 4 deliberately changes `LimeghostShared`.** Every other task must leave the Mac suite at whatever Task 4 sets it to, with zero failures.

## Verified before this plan was written

Measured on September 3, 2026 in this worktree. Do not re-derive.

**The app builds and its tests run.** `xcodebuild test -scheme Limeghost -destination 'platform=iOS Simulator,id=…'` → `** TEST SUCCEEDED **`, 3 tests.

**`BrowserWorkspace`'s real initializer** (`Sources/LimeghostShared/BrowserWorkspace.swift:372`):

```swift
public init(
    dataStore: BrowserDataStore? = nil,
    downloads: DownloadTracking,
    pageSharing: PageSharing.Type,
    clipboard: ClipboardWriting,
    makeSessionPlatform: @escaping () -> BrowserSessionPlatform,
    searchSettings: SearchSettingsStore? = nil,
    contentBlocking: ContentRuleListProvider? = nil,
    favicons: FaviconStore? = nil,
    webFeatures: WebFeatureSettingsStore? = nil,
    restoresSession: Bool = true,
    adopting: BrowserTab? = nil,
    isPrivate: Bool = false,
    profileID: UUID = BrowserProfileRecord.defaultID,
    websiteDataStore: WKWebsiteDataStore? = nil
)
```

`pageSharing` has **no default** — omitting it does not compile. `restoresSession` defaults to **`true`**, which rebuilds every persisted tab as a live `WKWebView`; a test that leaves it on inherits the previous run's tabs and writes its own back.

**The address bar is not `workspace.open()`.** `open(_:inNewTab:)` (`:1253`) guards on `WebURLPolicy.validatedURL`, which requires an `http`/`https` scheme — so `open("example.com")` silently does nothing. The Mac's address field (`Sources/LimeghostBrowser/BrowserView.swift:836` `submitAddress`) instead calls `workspace.makeRoomForPage()` and then `session.navigate(destination)` — the door rule applied **by hand, in a view**. `BrowserSession.navigate(_:)` (`:289`) resolves bare hosts and search terms. Task 4 fixes this.

**Completion always offers a search row.** `AddressCompletion.suggestions(for:in:)` (`Sources/LimeghostCore/AddressCompletion.swift:181`) returns `[search]` when nothing matches, and `[best, search] + rest` when something does. That is deliberate — "the search row sits behind the best place and ahead of the rest". A test asserting an empty result is wrong.

**The AI home reuses exactly three files.** `AIToolStartPage.swift` + `LimeghostTheme.swift` + `SiteIconView.swift` typecheck together for `arm64-apple-ios17.0-simulator` with **exit 0, zero errors**. `AIToolStartPage` is:

```swift
struct AIToolStartPage: View {
    @ObservedObject var store: BrowserDataStore
    let openTool: (AIToolListing) -> Void
    let openSource: (AIToolListing, URL) -> Void
}
```

`AIToolCatalog` exposes `release`, `tools`, and `filtered(category:query:)`. **There is no `tasks` accessor.** `AIToolListing` carries `officialURL: URL`.

**Correct stub conformances already exist** at `Tests/LimeghostSharedTests/WorkspaceDoorTests.swift:10-38` (`NoDownloads`, `NoPageSharing`, `NoClipboard`) and the throwaway-suite test workspace at `:97-120`. Copy those rather than writing new ones.

**Real members, confirmed:** `BrowserSession.instanceID` (`:78`), `.canGoBack` (`:89`), `.currentURLString` (`:87`), `.navigate(_:)` (`:289`); `BrowserWorkspace.goBackInSelectedTab()` (`:1464`), `.addTab(url:select:isPrivate:)`, `.closeTab(_:)` (`:796`, which makes a replacement when the last tab closes), `.canReopenClosedTab`, `.reopenClosedTab()`, `.selectTab(_:)`, `.selectedTabID`, `.visibleTabs`, `.makeRoomForPage()`; `BrowserTab.startSurface` with case `.aiHome` (`:26`); `ClipboardWriting.setString(_:)`.

## Commands

```bash
# The iOS app and its tests
cd ios && xcodebuild test -scheme Limeghost \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro"

# The shared layer on a simulator
cd macos/LimeghostBrowser && xcodebuild test -scheme LimeghostSharedLayer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# The Mac
cd macos/LimeghostBrowser && swift test
```

Mac baseline entering Task 3: **492 executed, 0 failures.** The skipped count varies 2–4 between runs on environment conditions; judge by the executed count and zero failures.

---

### Task 3: One tab, one web view, a page on screen

**Files:**
- Create: `ios/Sources/WorkspaceHost.swift`, `ios/Sources/WebViewHost.swift`, `ios/Sources/BrowserScreen.swift`
- Create: `ios/Tests/WorkspaceHostTests.swift`
- Modify: `ios/Sources/LimeghostApp.swift`, `ios/Limeghost.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `IOSSessionPlatform`, `IOSClipboard`, `IOSPageSharing`, `NoDownloads` (already in `ios/Sources/`).
- Produces: `WorkspaceHost` (`ObservableObject`, `.live()` and `.forTesting(defaults:)`), `WebViewHost` (`UIViewRepresentable`), `BrowserScreen`.

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/WorkspaceHostTests.swift`. Note it builds its own throwaway defaults suite and passes `restoresSession: false` — without both, the test inherits the app's real session and writes tabs back into it.

```swift
import XCTest
@testable import Limeghost
@testable import LimeghostShared

@MainActor
final class WorkspaceHostTests: XCTestCase {
    /// A suite of its own, emptied afterwards. The workspace persists tabs and
    /// restores them, so a test on the standard defaults would inherit the
    /// previous run's tabs and leave its own behind — in the simulator the app
    /// itself uses, because these tests run inside the app.
    private func makeHost() throws -> WorkspaceHost {
        let suiteName = "clearframe.iosHost.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return WorkspaceHost.forTesting(defaults: defaults)
    }

    /// The app opens on the AI guide, not a blank page. The first minute is a
    /// product acceptance criterion, not a default.
    func testTheAppOpensOnTheAIGuide() throws {
        let host = try makeHost()
        let tab = try XCTUnwrap(host.workspace.selectedTab)
        XCTAssertEqual(tab.startSurface, .aiHome)
    }

    /// Opening an address goes through the workspace, which is what makes it a
    /// door. If this ever bypasses the workspace, the rule that asking for a
    /// page uncovers the page stops applying to the phone.
    func testOpeningAnAddressAddsATabThroughTheWorkspace() throws {
        let host = try makeHost()
        let before = host.workspace.visibleTabs.count

        host.workspace.addTab(url: URL(string: "https://example.com/")!)

        XCTAssertEqual(host.workspace.visibleTabs.count, before + 1)
        XCTAssertEqual(host.workspace.selectedTab?.session.currentURLString, "https://example.com/")
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd ios && xcodebuild test -scheme Limeghost -destination "platform=iOS Simulator,name=iPhone 17 Pro" 2>&1 | grep -E "error:|^\*\* TEST" | head -5
```

Expected: `cannot find 'WorkspaceHost' in scope`.

- [ ] **Step 3: Write the host**

Create `ios/Sources/WorkspaceHost.swift`:

```swift
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
```

- [ ] **Step 4: Write the web view host and the screen**

Create `ios/Sources/WebViewHost.swift`:

```swift
import SwiftUI
import WebKit
import LimeghostShared

/// Hands SwiftUI a `BrowserSession`'s existing web view.
///
/// There is nothing to do in `updateUIView`: the web view is owned by the
/// session, not built here, and a representable cannot swap the view it already
/// returned. **Key this on `session.instanceID`** where different sessions
/// appear in the same place — never on the object's address, which is reused
/// after a free. This is the iOS twin of the Mac's `WebView`, which is an
/// `NSViewRepresentable` and so could not be shared; it is the whole of the
/// difference between the two platforms' page display.
struct WebViewHost: UIViewRepresentable {
    let session: BrowserSession

    func makeUIView(context: Context) -> WKWebView { session.webView }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
```

Create `ios/Sources/BrowserScreen.swift`:

```swift
import SwiftUI
import LimeghostShared

/// The whole browser, one screen. Task 5 adds the bottom bar beneath.
struct BrowserScreen: View {
    @ObservedObject var host: WorkspaceHost

    var body: some View {
        Group {
            if let tab = host.workspace.selectedTab {
                WebViewHost(session: tab.session)
                    .id(tab.session.instanceID)
            } else {
                Color.clear
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}
```

Change `ios/Sources/LimeghostApp.swift` to:

```swift
import SwiftUI
import LimeghostShared

@main
struct LimeghostApp: App {
    @StateObject private var host = WorkspaceHost.live()

    var body: some Scene {
        WindowGroup {
            BrowserScreen(host: host)
        }
    }
}
```

Add the three new sources to the app target's `PBXSourcesBuildPhase` and the test file to the test target's, following the existing entries exactly. Continue the `AA00000000000000000000NN` identifier scheme.

- [ ] **Step 5: Run the tests and watch them pass**

Expected: `** TEST SUCCEEDED **`, 5 tests.

- [ ] **Step 6: Run it and look at it**

```bash
cd ios
SIM=$(xcrun simctl list devices available | grep -m1 'iPhone 17 Pro' | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
xcrun simctl boot "$SIM" 2>/dev/null || true
open -a Simulator
xcodebuild build -scheme Limeghost -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath .build 2>&1 | tail -2
xcrun simctl install "$SIM" .build/Build/Products/Debug-iphonesimulator/Limeghost.app
xcrun simctl launch "$SIM" com.zincoo.limeghost
```

**Look at the simulator.** The AI guide has no view yet (Task 8), so a blank area is expected — but the app must launch and stay up. A crash or an immediate exit is a finding; report it rather than continuing.

- [ ] **Step 7: Confirm the Mac, then commit**

```bash
cd macos/LimeghostBrowser && swift test 2>&1 | tail -3
```

Expected: **492 executed, 0 failures** — no shared code changed.

```bash
git add ios
git commit -m "Put a page on the phone, driven by the Mac's own workspace

The workspace holds every door, so it moves here as code rather than being
written a second time. The one piece that could not travel is the web view
wrapper: the Mac's is an NSViewRepresentable and this is its UIView twin,
which is the whole of the difference."
```

---

### Task 4: Make the address bar a door

**Files:**
- Modify: `macos/LimeghostBrowser/Sources/LimeghostShared/BrowserWorkspace.swift`
- Modify: `macos/LimeghostBrowser/Tests/LimeghostSharedTests/WorkspaceDoorTests.swift`
- Modify: `macos/LimeghostBrowser/Sources/LimeghostBrowser/BrowserView.swift:836-857`

**Interfaces:**
- Produces: `BrowserWorkspace.navigate(_ input: String)` — a door.

**This is the one task that changes shared code, and it improves the Mac too.** Typing an address is a door: `CLAUDE.md` names "the address bar" among the ways of asking for a page that must call `makeRoomForPage()`. But there is no workspace method for it — `open(_:)` rejects bare hostnames, so the Mac's address field applies the rule *by hand in a view*: `workspace.makeRoomForPage()` then `session.navigate(destination)` (`BrowserView.swift:851-852`). A rule applied by hand in one view is a rule the next view forgets, and iOS is about to be the next view.

- [ ] **Step 1: Add the row to the door test first**

In `Tests/LimeghostSharedTests/WorkspaceDoorTests.swift`, add to the `doors` array:

```swift
            ("a typed address", { $0.navigate("example.com") }),
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd macos/LimeghostBrowser && swift test --filter WorkspaceDoorTests 2>&1 | tail -5
```

Expected: `value of type 'BrowserWorkspace' has no member 'navigate'`.

- [ ] **Step 3: Write it**

Add to `BrowserWorkspace`, beside `open(_:inNewTab:)`:

```swift
    /// Somebody typed something and pressed Return. Unlike `open(_:)` this
    /// accepts what a person actually types — a bare host, or search terms —
    /// because resolving that is `BrowserSession.navigate`'s job.
    ///
    /// It exists so that typing an address is a door like every other. The Mac
    /// applied that rule inline in its address field for as long as it was the
    /// only address field; a second platform is exactly when an inline rule
    /// gets forgotten.
    public func navigate(_ input: String) {
        makeRoomForPage()
        if selectedTab == nil { addTab() }
        selectedTab?.session.navigate(input)
    }
```

- [ ] **Step 4: Run it and watch it pass**

Expected: `WorkspaceDoorTests` green, now covering twelve doors.

- [ ] **Step 5: Move the Mac's address field onto it**

In `BrowserView.swift`'s `submitAddress()`, replace:

```swift
        workspace.makeRoomForPage()
        session.navigate(destination)
```

with:

```swift
        workspace.navigate(destination)
```

Leave everything else in that method alone — the suggestion-row branch, the voice input teardown, the focus handling and the `makeFirstResponder` call are unrelated.

- [ ] **Step 6: Run the whole Mac suite**

```bash
cd macos/LimeghostBrowser && swift test 2>&1 | tail -3
```

Expected: **493 executed, 0 failures** — 492 plus nothing new, except the door test now runs one more door inside its existing test, so the count may stay 492. **Report the number you actually get.** Any failure means the Mac's address behaviour changed; that is a finding, not something to work around.

- [ ] **Step 7: Commit**

```bash
git add macos
git commit -m "Make typing an address a door, instead of a rule applied by hand

CLAUDE.md lists the address bar among the ways of asking for a page that must
uncover it, but no workspace method accepted what a person types -- open()
requires a scheme -- so the Mac's address field called makeRoomForPage and
navigate itself, inline. That worked while there was one address field. A
second platform is exactly when an inline rule gets forgotten, so it becomes
a workspace method with a row in the door test, and the Mac's field now calls
it rather than repeating it."
```

---

### Task 5: The bottom bar

**Files:**
- Create: `ios/Sources/BottomBar.swift`, `ios/Tests/BottomBarTests.swift`
- Modify: `ios/Sources/BrowserScreen.swift`, `ios/Limeghost.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `BottomBarModel(urlString:tabCount:canGoBack:)` with `addressLabel: String`; `BottomBar` view.

Spec §4: back, the address pill, the assistant toggle, tabs, a menu — at the bottom, within a thumb's reach, leaving the page's own top alone. **The assistant toggle is Plan 3's.** Leave its place empty with a comment rather than a dead button.

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/BottomBarTests.swift`:

```swift
import XCTest
@testable import Limeghost

final class BottomBarTests: XCTestCase {
    /// The pill shows the host. A phone has no room for a query string, and the
    /// host is the part that answers "where am I".
    func testTheAddressPillShowsTheHost() {
        let model = BottomBarModel(urlString: "https://www.example.com/a/long/path?q=1", tabCount: 1, canGoBack: false)
        XCTAssertEqual(model.addressLabel, "example.com")
    }

    /// An empty tab has nothing to show, and this is what invites the first tap.
    func testAnEmptyAddressInvitesTyping() {
        let model = BottomBarModel(urlString: "", tabCount: 1, canGoBack: false)
        XCTAssertEqual(model.addressLabel, "Search or enter a website")
    }

    /// The tab button carries the count, because on a phone the tabs are not
    /// otherwise visible.
    func testTheTabButtonCountsTheTabs() {
        let model = BottomBarModel(urlString: "https://example.com/", tabCount: 4, canGoBack: true)
        XCTAssertEqual(model.tabCount, 4)
        XCTAssertTrue(model.canGoBack)
    }
}
```

- [ ] **Step 2: Run it and watch it fail.** Expected: `cannot find 'BottomBarModel' in scope`.

- [ ] **Step 3: Write it**

Create `ios/Sources/BottomBar.swift`:

```swift
import SwiftUI

/// What the bar shows, separate from how it draws, so a test can assert it
/// without standing up SwiftUI.
struct BottomBarModel {
    let urlString: String
    let tabCount: Int
    let canGoBack: Bool

    /// The host, or an invitation.
    var addressLabel: String {
        guard let host = URL(string: urlString)?.host else {
            return urlString.isEmpty ? "Search or enter a website" : urlString
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// Back, the address, the tabs and a menu — within a thumb's reach, along the
/// bottom so the page's own top is left alone.
struct BottomBar: View {
    let model: BottomBarModel
    let goBack: () -> Void
    let openAddress: () -> Void
    let openTabs: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: goBack) { Image(systemName: "chevron.backward") }
                .disabled(!model.canGoBack)
                .accessibilityLabel("Back")

            Button(action: openAddress) {
                Text(model.addressLabel)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.quaternary))
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel("Address")

            // The assistant toggle belongs here, immediately left of the tab
            // button, and arrives with the assistant in Plan 3. A button that
            // did nothing would teach the wrong thing about where it lives.

            Button(action: openTabs) {
                Text("\(model.tabCount)")
                    .font(.footnote.weight(.semibold))
                    .frame(minWidth: 24, minHeight: 24)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(lineWidth: 1.5))
            }
            .accessibilityLabel("Tabs, \(model.tabCount) open")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
```

- [ ] **Step 4: Put it on the screen.** In `BrowserScreen`, wrap the page in a `VStack(spacing: 0)` with the bar below it, `goBack: { host.workspace.goBackInSelectedTab() }`, and empty closures for `openAddress` (Task 6) and `openTabs` (Task 7). Move `.ignoresSafeArea(edges: .bottom)` onto the web view only, or the bar will sit under the home indicator.

- [ ] **Step 5: Run the tests.** Expected: `** TEST SUCCEEDED **`, 8 tests.

- [ ] **Step 6: Run it and look at it.** Task 3 Step 6 commands. The bar sits above the home indicator, back is disabled on a fresh tab, the tab button reads `1`.

- [ ] **Step 7: Confirm the Mac, then commit.** Mac unchanged from Task 4's number.

```bash
git add ios
git commit -m "Put the controls where a thumb reaches

The address pill shows the host rather than the URL, because a phone has no
room for a query string and the host is what answers where you are. The
assistant's toggle has a place reserved beside the tab button and nothing in
it yet."
```

---

### Task 6: The address sheet

**Files:**
- Create: `ios/Sources/AddressSheet.swift`, `ios/Tests/AddressSheetTests.swift`
- Modify: `ios/Sources/BrowserScreen.swift`, `ios/Limeghost.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `BrowserWorkspace.navigate(_:)` (Task 4); `AddressCompletion`, `AddressSuggestion` from `LimeghostCore`; `BrowserDataStore.addressCandidates`.
- Produces: `AddressSheetModel(workspace:)` with `submit(_:)` and `suggestions(for:) -> [AddressSuggestion]`; `AddressSheet` view.

**Completion is local only** — this profile's own history and bookmarks, no request while typing, no suggestion service. That is a deliberate difference from Chrome and it is written into the privacy documents.

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/AddressSheetTests.swift`. Note the second test asserts the **search row**, not emptiness — `AddressCompletion` always offers one, by design.

```swift
import XCTest
import LimeghostCore
@testable import Limeghost
@testable import LimeghostShared

@MainActor
final class AddressSheetTests: XCTestCase {
    private func makeHost() throws -> WorkspaceHost {
        let suiteName = "clearframe.iosAddress.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return WorkspaceHost.forTesting(defaults: defaults)
    }

    /// A bare host navigates. `workspace.open` would refuse this — it requires
    /// a scheme — which is why typing goes through `navigate`.
    func testABareHostNavigates() throws {
        let host = try makeHost()
        let model = AddressSheetModel(workspace: host.workspace)

        model.submit("example.com")

        let url = try XCTUnwrap(host.workspace.selectedTab?.session.currentURLString)
        XCTAssertTrue(url.contains("example.com"), url)
    }

    /// Completion offers a search row for anything typed, and nothing else when
    /// this profile has never visited or saved a match. It contacts no
    /// suggestion service and makes no request while typing.
    func testAnUnknownPrefixOffersOnlyTheSearchRow() throws {
        let host = try makeHost()
        let model = AddressSheetModel(workspace: host.workspace)

        let rows = model.suggestions(for: "zzzzznotahost")

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.kind, .search)
    }
}
```

- [ ] **Step 2: Run it and watch it fail.** Expected: `cannot find 'AddressSheetModel' in scope`.

- [ ] **Step 3: Read the completion API, then write the model**

```bash
grep -n "public static func suggestions" -A 6 macos/LimeghostBrowser/Sources/LimeghostCore/AddressCompletion.swift
grep -n "public var addressCandidates" -A 4 macos/LimeghostBrowser/Sources/LimeghostShared/BrowserDataStore.swift
```

Write `AddressSheetModel` with `submit(_ text: String)` calling `workspace.navigate(text)` — **not** `open`, and not `session.navigate` directly — and `suggestions(for:)` calling `AddressCompletion` with the store's candidates. Then `AddressSheet`: a focused `TextField` submitting on Return, a `List` of suggestions where tapping one submits its URL, and a Cancel button. Present it from `BottomBar`'s `openAddress` as a `.sheet`.

- [ ] **Step 4: Run the tests.** Expected: `** TEST SUCCEEDED **`, 10 tests.

- [ ] **Step 5: Run it and look at it.** Type `example.com`, press Return, confirm the page loads and the pill updates. Type a few letters of a site you visited and confirm a suggestion appears.

- [ ] **Step 6: Confirm the Mac, then commit.**

```bash
git add ios
git commit -m "Let somebody type an address, through the door Task 4 opened

Completion reads this profile's own history and bookmarks and nothing else --
no request while typing, no suggestion service. A prefix matching nothing
still offers to search for it, which is the completion's own deliberate
design rather than a gap."
```

---

### Task 7: The tab switcher

**Files:**
- Create: `ios/Sources/TabSwitcher.swift`, `ios/Tests/TabSwitcherTests.swift`
- Modify: `ios/Sources/BrowserScreen.swift`, `ios/Limeghost.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `TabRow(id:title:host:isPrivate:)`, `TabSwitcherModel(workspace:)` with `rows`, `privateRows`, `canReopenClosed`; `TabSwitcher` view.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Limeghost
@testable import LimeghostShared

@MainActor
final class TabSwitcherTests: XCTestCase {
    private func makeHost() throws -> WorkspaceHost {
        let suiteName = "clearframe.iosTabs.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return WorkspaceHost.forTesting(defaults: defaults)
    }

    /// Private tabs are their own section. They are ephemeral and excluded from
    /// history; one list would blur a line the product draws on purpose.
    func testPrivateTabsAreTheirOwnSection() throws {
        let host = try makeHost()
        host.workspace.addTab(url: URL(string: "https://example.com/")!, isPrivate: false)
        host.workspace.addTab(url: URL(string: "https://example.org/")!, isPrivate: true)

        let model = TabSwitcherModel(workspace: host.workspace)

        XCTAssertTrue(model.rows.allSatisfy { !$0.isPrivate })
        XCTAssertEqual(model.privateRows.count, 1)
    }

    /// Closing every tab must not leave an empty browser with nothing to tap.
    /// `closeTab` makes a replacement when the last one goes.
    func testClosingEveryTabLeavesOneToLookAt() throws {
        let host = try makeHost()
        for tab in host.workspace.visibleTabs { host.workspace.closeTab(tab.id) }

        XCTAssertFalse(host.workspace.visibleTabs.isEmpty)
    }

    /// A closed tab can come back.
    func testAClosedTabCanBeReopened() throws {
        let host = try makeHost()
        host.workspace.addTab(url: URL(string: "https://example.com/")!)
        let id = try XCTUnwrap(host.workspace.selectedTabID)
        host.workspace.closeTab(id)

        XCTAssertTrue(host.workspace.canReopenClosedTab)
    }
}
```

- [ ] **Step 2: Run it and watch it fail.**

- [ ] **Step 3: Write it.** A `LazyVGrid` of cards, a private section below when non-empty, a `+` that calls `workspace.addTab()`, a `+` in the private section that calls `workspace.addTab(isPrivate: true)` — spec §2 has private tabs in v1, so there must be a way to make one — a close control per card, and "Reopen closed tab" when `canReopenClosed`.

**Selecting an existing tab is deliberately not a door** — it is not a request for a *different* page — so it calls `workspace.selectTab(_:)` and must not call `makeRoomForPage()`. Adding and reopening are doors and already handle it.

- [ ] **Step 4: Run the tests.** Expected: `** TEST SUCCEEDED **`, 13 tests.

- [ ] **Step 5: Run it and look at it.** Open three tabs, switch, close one, reopen it, open a private tab and confirm its own section.

- [ ] **Step 6: Confirm the Mac, then commit.**

```bash
git add ios
git commit -m "Show the tabs, and keep the private ones apart

A grid, because a phone cannot show a strip. Private tabs get their own
section rather than being mixed in. Selecting a tab that already exists is not
a request for a different page, so it moves nothing."
```

---

### Task 8: The AI guide

**Files:**
- Create: `ios/Sources/StartSurfaceScreen.swift`, `ios/Tests/StartSurfaceTests.swift`
- Modify: `ios/Sources/BrowserScreen.swift`, `ios/Limeghost.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `AIToolStartPage`, `LimeghostTheme`, `SiteIconView` — added to the iOS target by path; `AIToolCatalog`, `AIToolListing` from `LimeghostCore`.
- Produces: `StartSurfaceScreen`.

**The reuse set is exactly three files, measured.** `AIToolStartPage.swift`, `LimeghostTheme.swift` and `SiteIconView.swift` typecheck together for `arm64-apple-ios17.0-simulator` with exit 0 and zero errors. Add all three to the iOS app target's `PBXSourcesBuildPhase` by relative path (`../macos/LimeghostBrowser/Sources/LimeghostBrowser/…`) with `PBXFileReference` entries whose `path` is relative to the group. Do not modify the Mac's copies — making them portable is a shared-surfaces refactor and is not this task.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import LimeghostCore
@testable import Limeghost
@testable import LimeghostShared

@MainActor
final class StartSurfaceTests: XCTestCase {
    /// A new tab opens the guide, not a blank page.
    func testANewTabOpensTheGuide() throws {
        let suiteName = "clearframe.iosStart.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let host = WorkspaceHost.forTesting(defaults: defaults)

        host.workspace.addTab()

        XCTAssertEqual(host.workspace.selectedTab?.startSurface, .aiHome)
    }

    /// The catalogue is bundled, not fetched: showing the guide makes no
    /// request. `filtered` with no category and no query is what the guide
    /// shows before anybody types.
    func testTheCatalogueIsLocalAndNonEmpty() {
        XCTAssertFalse(AIToolCatalog.filtered(category: nil, query: "").isEmpty)
    }
}
```

- [ ] **Step 2: Run it and watch it fail.**

- [ ] **Step 3: Add the three files and write the wrapper**

`AIToolStartPage`'s stored properties are exactly:

```swift
    @ObservedObject var store: BrowserDataStore
    let openTool: (AIToolListing) -> Void
    let openSource: (AIToolListing, URL) -> Void
```

Write `StartSurfaceScreen` supplying them from the workspace. **Both closures are doors** — `CLAUDE.md` names an AI-guide card among the ways of asking for a page — so both must route through a workspace method that calls `makeRoomForPage()`:

```swift
            openTool: { tool in host.workspace.open(tool.officialURL.absoluteString) },
            openSource: { _, url in host.workspace.open(url.absoluteString) }
```

`open(_:)` accepts these because both are already absolute `https` URLs. Show `StartSurfaceScreen` in `BrowserScreen` when the selected tab's `startSurface == .aiHome`.

**The guide is a curated local directory of official links.** It must not gain live rankings, prices, availability claims, or any implication that Limeghost tested these tools or is paid by them. Opening a card attaches no page content and no prompt.

- [ ] **Step 4: Run the tests.** Expected: `** TEST SUCCEEDED **`, 15 tests.

- [ ] **Step 5: Run it and look at it — this is the first minute**

Launch fresh and read the screen as somebody who has never seen it. Does it say what to do next? Report anything confusing; that observation is worth more than the test count, and it is the only kind of evidence this project does not already have.

- [ ] **Step 6: Confirm the Mac, then commit.**

```bash
git add ios
git commit -m "Open on the guide, so the first minute starts with a task

Three files reach the phone unchanged -- the start page, the theme and the
site icon view -- measured against the iOS SDK rather than assumed. The
catalogue is bundled, so showing it makes no request, and opening a card is
ordinary navigation through a door that attaches no page and no prompt."
```

---

### Task 9: Onto a real iPhone, into CI, into the documents

**Files:**
- Modify: `ios/Limeghost.xcodeproj/project.pbxproj`, `.github/workflows/ci.yml`
- Modify: `docs/ios-browser-foundation.md`, `README.md`, `CHANGELOG.md`, `docs/project-context.md`

**This task is what makes the goal true.** Everything before it runs on a Simulator; the spec's deliverable (§7.1) is the app on the founder's own iPhone under free provisioning.

- [ ] **Step 1: Turn signing on for a device build**

The project currently sets `CODE_SIGNING_ALLOWED = NO`, which is right for the Simulator and cannot install on hardware. Add automatic signing to the app target's configuration:

```
CODE_SIGN_STYLE = Automatic;
DEVELOPMENT_TEAM = "";
```

Leave `DEVELOPMENT_TEAM` empty in the committed file — a team identifier is personal to its holder and does not belong in a shared repository. Xcode fills it from the signed-in Apple ID.

- [ ] **Step 2: Hand the device step to the founder**

This part cannot be automated and must not be claimed as done. Write it into `docs/ios-browser-foundation.md` as a numbered procedure: open `ios/Limeghost.xcodeproj` in Xcode, sign in with a personal Apple ID under Settings → Accounts, select the Limeghost target → Signing & Capabilities → Automatically manage signing, choose the personal team, connect the iPhone, select it as the run destination, and Run. Then on the phone, Settings → General → VPN & Device Management → trust the developer.

State plainly that free provisioning issues a **seven-day** certificate, so the app stops launching after a week and is reinstalled by running it from Xcode again — and that this is why nobody but the founder can install it until Developer Program enrolment.

- [ ] **Step 3: Add the app to CI**

Extend the existing `ios-simulator` job — do not add a second one, and do not touch `macos-browser`. It already discovers a simulator UDID at runtime:

```yaml
      - name: Build and test the iOS app
        working-directory: ios
        run: |
          xcodebuild test -scheme Limeghost \
            -destination "platform=iOS Simulator,id=$SIM_UDID"
```

- [ ] **Step 4: Update the documents to what is now true**

`docs/ios-browser-foundation.md` describes a shared layer with no app. There is now an app: tabs, an address bar, a bottom bar, a tab switcher, the AI guide. Say what exists and — unchanged — that nothing is signed for distribution or notarized, that nobody but the founder can install it, and that **no observed-user session has been run**. **Do not describe Plan 3's features as present:** there is no assistant, no Reader, no Copy for AI and no bookmark import in this app.

Update `README.md`'s limits entry, add a `CHANGELOG.md` entry, and one dated paragraph in `docs/project-context.md`.

- [ ] **Step 5: Verify all three suites, then commit**

```bash
cd macos/LimeghostBrowser && swift test 2>&1 | tail -3
cd macos/LimeghostBrowser && xcodebuild test -scheme LimeghostSharedLayer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep "^\*\* TEST"
cd ios && xcodebuild test -scheme Limeghost -destination "platform=iOS Simulator,name=iPhone 17 Pro" 2>&1 | grep "^\*\* TEST"
```

```bash
git add -A
git commit -m "Make it installable, run it in CI, and write down what it is

Signing is automatic with an empty team, because a team identifier is
personal to its holder. The device steps are a procedure for the founder
rather than something claimed as done, and the seven-day certificate is
stated: the app stops launching after a week until it is run from Xcode
again, which is also why nobody else can install it yet."
```

---

## Self-Review

**Spec coverage.** §2 in-v1 → Tasks 3, 5–8 (tabs, private tabs, address bar with local completion, switcher, AI guide); deferred items correctly absent. §4 the shell → Tasks 3, 5, 7, 8, assistant toggle's place reserved and empty. §6.1 bundle identifier, §6.3 one profile → already delivered. §7.1 free-provisioning distribution → Task 9. The door rule → Task 4, which closes a gap the Mac had.

**Not covered, by design:** §5 the assistant, Reader and Copy for AI (§2), the bookmark bridge (§6.5), the privacy manifest (§6.7), CloudKit (§6.6, blocked on enrolment). All Plan 3.

**Placeholder scan.** No "TBD"/"TODO"/"similar to Task N". Two steps tell the implementer to read an API before writing against it (Task 6 Step 3's completion signature, Task 8's file references); both name the exact command and neither substitutes for a signature this plan could have stated. Every other signature in this plan was read from source and is quoted.

**Type consistency.** `WorkspaceHost.forTesting(defaults:)` is defined in Task 3 and used identically in Tasks 6, 7, 8. `BottomBarModel(urlString:tabCount:canGoBack:)` matches between its test and implementation. `BrowserWorkspace.navigate(_:)` is produced in Task 4 and consumed in Task 6. `TabRow.isPrivate`, `TabSwitcherModel(workspace:)`, `AddressSheetModel(workspace:)` are consistent.

**What changed from the first version of this plan, and why.** An independent review predicted six failures and running them confirmed all six. Tasks 1–2 were built rather than described, and are committed. The test-target wiring, the three real protocol conformances, the second package product, and the real `Info.plist` are in that commit. In this rewrite: `forTesting` now takes a throwaway defaults suite and `restoresSession: false` (it would otherwise have written into the app's real session); the address bar became its own task because `workspace.open` rejects bare hostnames and the Mac applied the door rule inline; the completion test now asserts the search row the completion deliberately always returns; the AI-guide reuse set is named as three measured files rather than left as a fork; and Task 9 gets the app onto a phone, which the previous version claimed and did not do.
