# Limeghost for iPhone — design

**Status:** approved design, September 3, 2026. Written from a six-section brainstorm with the founder on September 2–3, 2026, after an audit of every decision against `CLAUDE.md`, `docs/limeghost-strategy.md`, `docs/project-context.md`, `docs/product-foundation.md`, `docs/privacy-and-safety.md`, `docs/go-to-market.md` and `docs/ip-and-ownership.md`. The implementation plan that follows it lives in `docs/superpowers/plans/`.

**Read with:** `docs/project-context.md` (durable decisions), `docs/macos-browser-foundation.md` (the Mac architecture this extends), and `docs/ip-and-ownership.md` (licensing).

## 1. Decisions

Four decisions and two amendments, in the order they were made.

1. **Scope — a pocket browser.** A real iOS browser that owns navigation: tabs, address bar, bookmarks, history, Reader, Copy for AI, tracker blocking, and the assistant on the person's own account. Not a companion app and not a share-sheet extension.
2. **The assistant fills the screen.** On a phone there is no "beside the page"; the assistant covers the page and the page stays loaded behind it. Compare answers does not exist on a phone.
3. **Continuity — iCloud private sync, bookmarks only, never history.** CloudKit's private database, in the person's own iCloud; Limeghost runs no server and holds nothing. *Amended:* designed now, **built after Apple Developer Program enrolment**, because CloudKit is not available under free provisioning and the founder has said the enrolment fee is not available now. v1 is an island with an export/import bridge.
4. **Licensing — dual-license.** The repository stays AGPL-3.0; the App Store binary ships under the copyright holder's separate terms. This is the principle `docs/ip-and-ownership.md` already records, applied to the founder's own distribution.
5. *Amendment:* **bookmark import is in v1**, because it is the only continuity that costs nothing and needs no Apple money.
6. **Approach — one repository, one Core, a new shared layer, an Xcode project under `ios/`.** Not a separate repository (the shared contract would drift), and not a whole-repo Xcode conversion now (it would collide with live desktop work).

### 1.1 What this reverses, and why

`docs/product-foundation.md` lists "a mobile browser" among explicit non-goals, and `docs/limeghost-strategy.md` says the next differentiated features should not start "before an outside tester can install the app at all." This design is a conscious exception to both, decided by the founder on September 2, 2026:

- The non-goal was written against the cost of a **second engine**: "maintaining Chromium would add security updates, packaging, sync, profiles, password migration, mobile support…". iOS mandates WebKit, which is Limeghost's engine. It is the one platform where the WebKit + SwiftUI + `LimeghostCore` bet is native rather than a compromise, and the roadmap's platform-expansion gate — written about CEF — does not fire.
- The sequencing rule stays true for the two features it names. The iOS app sits beside the founder's August 24 decision to dogfood rather than recruit: it is buildable and dogfoodable at no cost, and validatable by nobody else until enrolment — the same position the Mac app is in. **It is unvalidated by anyone but the founder, and no document may say otherwise.**

### 1.2 What does not carry from the Mac, stated once

Website logins are cookies in WebKit's data store, which has no export API; no browser carries sessions between devices. The person signs in again on the phone. Limeghost stores no passwords, so there is nothing to transfer; on iPhone the system's Password AutoFill offers iCloud Keychain or the person's password manager inside `WKWebView`, which the Mac app cannot do today. Assistant conversations live in the provider's account and appear after one sign-in. History never travels (a documented non-goal). Bookmarks travel by export → AirDrop → import in v1, and by iCloud in v1.1.

## 2. Scope

| In v1 | Deferred to v1.1+ | Not on a phone |
|---|---|---|
| AI guide as every new tab and Home (`AIToolCatalog`, Core) | Profile switcher — v1 runs the default profile; the model stays per-profile | Bookmarks bar |
| Tabs, private tabs, session restore, reopen closed | Downloads (Files integration, `WKDownload`, a list — a subsystem; PDFs and images already render inline) | Compare answers |
| Address bar with local-only completion (`AddressCompletion`, Core); search-provider choice | Voice dictation (`VoiceInputController` moves to the shared layer; permissions and UI wait) | Tear-off windows |
| Bookmarks home, folders with the icon catalogue, history home | Pin / group *creation* UI — `BrowserTab` already carries `isPinned` and `groupID`; the switcher honours them | Print |
| **Bookmark import and export** (the island bridge) | Share extension (receive a page from Safari) | Password manager, a sync *service* |
| Reader; Copy for AI in the menu and inside Reader, labelled, no toolbar glyph | CloudKit bookmark sync (§6.6) | |
| Tracker blocking with the shield and per-site exceptions | Handoff; default-browser registration; passkeys (all need the paid program) | |
| Find in page (`PageFindController`) | | |
| Site information / connection state | | |
| The introduction, minus Compare | | |
| Settings: General, Search, Tabs, Privacy, Blocking, Bookmarks, About | | |

Two calls made deliberately: **one profile in v1** (a phone is usually one person; Safari only grew profiles in iOS 17; the default profile keeps the shared model honest so the switcher is a later view, not a later migration) and **no downloads in v1** (a subsystem, not a button, and not in the first minute).

## 3. Architecture — targets and the sharing boundary

### 3.1 Measured portability

**Corrected September 3, 2026, after nine implementation tasks.** This table originally grouped files by whether they imported AppKit. That test is not evidence: **`import SwiftUI` re-exports AppKit on macOS**, so a file can use an AppKit type — `NSViewRepresentable`, `NSEvent`, `NSApplicationDelegateAdaptor` — while importing nothing named AppKit, and a file that does write `import AppKit` can go on to use none of it. Nine tasks of building `LimeghostShared` hit this repeatedly, in both directions. **Portability is a compiler question, never a grep question.** The check that held up, run per target with a `LimeghostCore` module emitted for iOS first (it is the one thing `LimeghostShared` imports): `xcrun --sdk iphonesimulator swiftc -typecheck -swift-version 5 -target arm64-apple-ios17.0-simulator` — see [`docs/ios-browser-foundation.md`](../../ios-browser-foundation.md) for the exact commands used throughout. The rows below are corrected against that measurement, not against an import search.

| Layer | Lines | Fate | Evidence |
|---|---|---|---|
| `LimeghostCore` | 8,691 | Unchanged; compiles for iOS as-is | Foundation + CoreGraphics only; no `#if os`; no resources |
| Models, stores, session, companion | ~3,700 | Moved to a new **`LimeghostShared`** target — no AppKit, UIKit or SwiftUI; typechecks against the iOS 17 SDK | `AICompanion`, `BrowserDataStore`, `BrowserPreferences`, `BrowserSession`, `BrowserWorkspace`, `ContentRuleListProvider`, `ContentBlockingSettingsStore`, `SearchSettingsStore`, `WebFeatureSettingsStore`, `PageFindController`, `OnboardingController`, `BrowserUserAgent`, `SiteDataInventory`, `VoiceInputController`, `FaviconStore` (after §6.4), `IdentityColor` (`FaviconStore`'s hard dependency; this row did not originally name it), `ReaderArticle` (split out of `ReaderView.swift`) — 23 files in `LimeghostShared` today. `BookmarkImportSources` was named in this row originally and is **removed from it**: see the note below the table |
| Platform-neutral SwiftUI surfaces | ~2,700 | Compile on iOS after layout review; **referenced by path in v1, not moved** | `LimeghostTheme`, `AIToolStartPage`, `BookmarksHomePage`, `HistoryHomePage`, `ReaderView`, `LimeghostIconView`, `LimeghostIconPicker`, `ChromeIcons`, `ContentBlockingViews`, `AddressSuggestionsView` — no AppKit import; every idiom they use exists on iOS 17. **Not compiler-verified**: no task in this plan ran the iOS typecheck against this row, so it still rests on the same absence-of-import reasoning just shown incomplete for the row below it — confirm it with the same command before Plan 2 relies on it |
| Mac chrome | ~5,800 | Stays in `LimeghostBrowser`; iOS writes its own | Tab strip, address field, window support, settings window, onboarding view, profile prompts, torn-window drag, `BrowserServices`, app lifecycle, downloads, page file commands — plus five files that import no AppKit at all, which the old grep-based method would have called portable: `WebView.swift` (`NSViewRepresentable`), `TabStripViews.swift` (`NSEvent`), `LimeghostBrowserApp.swift` (`NSApplicationDelegateAdaptor`), `SiteInformationViews.swift` (`\.openSettings`, unavailable on iOS), `BookmarkImportSources.swift` (`homeDirectoryForCurrentUser`, unavailable on iOS — see the note below) |

`BookmarkImportSources.swift` is the file that matters beyond this table. It imports only `Foundation` — no AppKit, no SwiftUI — so the original table placed it in the row above, moving whole to `LimeghostShared`. It cannot move as-is: `fileManager.homeDirectoryForCurrentUser`, used to locate Safari's bookmarks export for the import picker, is `API_UNAVAILABLE(ios, watchos, tvos)` — confirmed with the same typecheck command (`error: 'homeDirectoryForCurrentUser' is unavailable in iOS`). The rest of the file — parsing a Netscape bookmark `.html` document and building the placement preview §6.5 describes — has no such dependency. It needs the same treatment §3.2 gives `BrowserSession`: a small platform seam for "locate this platform's known bookmark files," which the Mac implements with its home-directory lookup and iOS does not implement at all, since §6.5's phone import path receives its file directly through the system's Open-in handoff rather than searching for one. **§6.5 did not anticipate this seam; it needs one before Plan 3 builds the bridge.**

### 3.2 `BrowserSession` moves behind one protocol

Its AppKit contact is six edges in the UI delegate: opening an external scheme (already an injected closure), mirroring `NSApp.effectiveAppearance`, printing, the `<input type=file>` panel, and JS alert/confirm/prompt. `NSURLError*` codes are Foundation. So:

```swift
protocol BrowserSessionPlatform {
    func openExternal(_ url: URL)
    func present(alert message: String, from webView: WKWebView) async
    func present(confirm message: String, from webView: WKWebView) async -> Bool
    func present(prompt message: String, default: String?, from webView: WKWebView) async -> String?
    func chooseFiles(allowsMultiple: Bool, from webView: WKWebView) async -> [URL]?   // Mac only; iOS returns nil and WebKit presents its own picker
    func print(_ webView: WKWebView)
    func observeAppearance(_ apply: @escaping () -> Void) -> AnyCancellable?       // Mac only; iOS follows the trait collection
}
```

The Mac implementation is the existing code moved into a conforming type; behaviour does not change. `AICompanion` needs `BrowserSession` only as a stored type plus its injected `makeSession` factory, so it moves untouched.

### 3.3 `BrowserWorkspace` is shared, not rewritten

It contains `BrowserTab`, every door, `makeRoomForPage`, and the behaviour `testEveryWayOfAskingForAPageUncoversIt` guards. `CLAUDE.md` records the one rule half-shipping once — "⌘T stepped aside and nine other doors did not" — and an iOS rewrite is precisely how that recurs. It moves behind protocols for the three AppKit collaborators it composes and its two edges:

- `DownloadCoordinating` (today `DownloadCenter`), `SiteIconProviding` (today `FaviconStore`, until §6.4 makes it shared), `PageSharing` (today `PageFileCommands`);
- a clipboard writer (`NSPasteboard` at one call site) and a share presenter.

The existing Mac classes conform unchanged. **The implementation plan opens with a spike that counts the window-specific seams** (torn windows, per-window profiles, `BrowserServices` visibility bookkeeping). If they are more than a handful, the fallback is an iOS `MobileWorkspace` that ports the doors and duplicates the door test — accepted as worse, and only if the spike says so.

### 3.4 Package, project, CI

- `Package.swift`: `.iOS(.v17)` joins `platforms` (17 for `WKWebsiteDataStore(forIdentifier:)`, `.focusable`, `onChange(of:initial:)`); `LimeghostShared` and `LimeghostSharedTests` are added; `LimeghostBrowser` depends on Shared. `swiftLanguageModes: [.v5]` stays. Nothing about the Mac build changes.
- `ios/Limeghost.xcodeproj` — the only Xcode project in the repository. One app target, one unit-test target, one UI-test target; links `LimeghostCore` and `LimeghostShared` as local package products. SwiftPM cannot produce an iOS app, so this is not optional.
- The platform-neutral surfaces are **referenced by path** from the iOS target in v1. The desktop branch is editing several of them; a `git mv` under a live edit is a guaranteed conflict. Promoting them to a `LimeghostSurfaces` target is a named follow-up once that branch lands. Until then, AppKit creeping into one of those files fails the iOS CI job — the boundary being enforced, not a bug.
- `ci.yml` gains one job beside the `macos-15` one: `xcodebuild … -destination 'platform=iOS Simulator'` build and test. The Mac job is untouched.
- The only files this design moves are ones the desktop branch does not have open. Both sessions keep their own worktree and `.build`.

### 3.5 Constraints on the shared layer

- **No `#if os(iOS)` in `LimeghostShared`.** Platform differences enter through the protocols in §3.2 and §3.3, never through conditionals in the model.
- **Preference keys stay `clearframe.*` on both platforms** (§6.2).
- **The bookmark, folder, profile and session records are Core types** and remain the only wire format on both platforms.

## 4. The shell

One scene, one `BrowserWorkspace`, the selected tab's web view filling the screen. A bottom bar — thumb reach, and it leaves the page's own top alone — carrying back, the address pill, the assistant toggle, tabs, and a menu. The menu does the Page menu's job: Reader, Copy for AI, bookmark this page, find, share, site information, settings. Reader and the assistant toggle keep their accent ring (`LimeghostTheme.groupOutline`) wherever they land; the grouping is a rule, not a Mac detail. The tab switcher is a full-screen grid with private tabs as their own section and "reopen closed tab" at the bottom. New tabs and Home open the AI guide; the bookmarks home opens from the menu.

**The doors are the Mac's doors** — new tab, new tab beside, a link in a tab, a link from another app, an address or bookmark, a bookmark in a new tab, reopen closed, bookmarks home, history home, back, forward, and the AI home's own closures. The iOS shell adds no door the Mac lacks. If one is ever added, it gets a row in `testEveryWayOfAskingForAPageUncoversIt` on the same day.

**How it looks is not decided here.** The Mac chrome was chosen from a design canvas of twelve directions; the phone chrome gets the same treatment after this spec. Nothing in this document fixes a pixel.

## 5. The assistant on a phone

### 5.1 "Sheet" is the look, not the implementation

A SwiftUI `.sheet` presents its content in a separate hosting hierarchy, which re-parents the `WebView` — the destroy-and-rebuild `CLAUDE.md` records shipping Compare as a header above a blank rectangle. So the phone assistant is the Mac's own overlay: the one `AICompanionPanel` in the one `ZStack`, rendered at full width, with a grabber, rounded top and a swipe-down gesture. It is `fillsWindow` drawn on a compact width.

### 5.2 One rule, no second layout mode

`companionWidth` (500) and `minimumReadableWidth` (600) move from the Mac view into a small pure `AssistantLayout` in `LimeghostShared`, with the two predicates: *fits beside the page* (≥ 1,100) and *fits two assistants* (≥ 1,000). Both views read the same numbers. Every iPhone is under 1,100 points, so `setCanShareWindow(false)` fires on the initial pass and the assistant only ever fills the screen. Current iPads in landscape are 1,133–1,366 points, so there the docked panel returns by the same rule; in portrait (744–1,024) and on older 1,024-point models an iPad fills the screen exactly like a phone, and Split View narrowing the scene triggers the "leaves and returns when the room does" behaviour that is already tested. Between 1,000 and 1,100 points — an older iPad in landscape — Compare is offered while the page is not, which is the band the Mac already has. **v1 QA targets iPhone; iPad works because nothing was special-cased for it.** Compare follows the same gate — an iPad in landscape qualifies, an iPhone never does — and the gate is one existing line if it ever needs to change.

### 5.3 Header, way back, closing

On a compact width the header is the provider menu, "your own account", and close. Compare and Fill the window fold away because neither has a job — the same reason they fold while comparing today. Close hides the assistant. Page actions stay out of this header; Copy for AI lives in the menu and inside Reader.

The way back is the lit toggle in the bottom bar and nothing else — there are no shortcuts to not know. Swipe-down or × is `hide()`: deliberate, stays closed. A door is `makeRoomForPage()`: on a phone it leaves and, since room never appears, waits for the button. On an iPad, rotating to landscape can bring it back by itself.

### 5.4 Links and sign-in popups

A link tapped inside the assistant goes through `onRequestNewTab` → `addTab`, a door, so the page comes forward. A provider's sign-in popup goes through `onRequestPopupWebView`, adopting WebKit's configuration so the opener relationship holds — but a tab opened *behind* a full-screen assistant is invisible. So on iOS the popup is presented as a second overlay **over** the assistant, in the same `ZStack`, and stays "not a door": the assistant does not leave. The shared session gains `webViewDidClose` → `onRequestClose`, so a popup that closes itself after sign-in dismisses. The Mac does not handle that today and may adopt it or not.

*Observation for the desktop session, outside this design's scope:* `adoptPopupTab` selects the popup tab without making room, so with the panel filling a Mac window a sign-in lands behind it.

### 5.5 Memory and lifecycle

`maximumLiveSessions = 2` was chosen on a Mac where content processes never exit; iOS kills them under pressure. The number is not trusted on iOS until the instrument in §9.5 has run on a device. A memory warning evicts the hidden assistant through the existing path — park its URL, tear it down. A companion whose process is terminated parks and reloads on next show, recovering the thread rather than showing "This page stopped responding" inside a provider's frame. The parked URL for the chosen tool is persisted so an app relaunch resumes the thread; drafts and temporary chats still do not survive, and the interface must not imply they do.

### 5.6 Unchanged, and one addition

Never type into it, never press its send button, never read what it says; rank assistants by which stayed on screen, never by what was read; the clipboard is the deliberate gap between this app and a service it has no agreement with. iOS makes that gap tempting to close — a Shortcuts action, a share-sheet target that "sends to your assistant" — and the rule forbids every one of them.

## 6. Data, storage, identity

### 6.1 Bundle identifier

The Mac stays `com.clearframe.browser` — `CLAUDE.md`'s rule, untouched. The phone takes **`com.zincoo.limeghost`**. A CloudKit container is named independently of bundle identifiers, so this does not constrain §6.6. If the Mac ever migrates for App Store submission, it joins that family in the all-at-once move the rule describes.

### 6.2 Preference keys stay `clearframe.*` on both platforms

`BrowserDataStore` and `BrowserPreferences` move to the shared target reading the keys they read today. They land in the phone's own defaults domain and are invisible to anyone. Renaming them for iOS would fork the code the Mac depends on. Do not tidy them.

### 6.3 One profile, the default stores

iOS v1 runs the default profile, which on the Mac keeps the application's original stores: default `UserDefaults`, default `WKWebsiteDataStore`. Private tabs use the non-persistent store through the same session code. Settings → Site data reads `SiteDataInventory`. The browsing-data reset keeps the Mac's exact semantics minus downloads.

### 6.4 Site icons: refactor, not rewrite

`FaviconStore` has six AppKit lines — an `NSCache` of `NSImage`, two `NSImage(data:)` decodes, one `NSBitmapImageRep` PNG encode — and already imports ImageIO. Replacing those with `CGImage` + `CGImageSource`/`CGImageDestination` makes it platform-neutral and it moves to the shared target. The policy then exists once: fetched only during a visit, only from the page's own origin or a host that page already loaded something from, never a third-party service, memory-only in private tabs, wiped by the reset. The cache path already uses `.applicationSupportDirectory`, which works in the iOS sandbox.

### 6.5 The bridge, both directions

Export on the phone is the Mac's 32 lines with a `ShareLink` in place of `NSSavePanel`, calling the same `NetscapeBookmarkExporter` in Core. Import registers the bookmarks `.html` document type so an AirDropped file offers *Open in Limeghost*, then runs `BookmarkImportSources` into a compact placement preview — "into your bookmarks" or "into one folder named after the file"; the Mac's bar-merge option has no bar to merge into.

### 6.6 CloudKit — designed now, built after enrolment

One v1 change serves it: `BookmarkRecord` and `BookmarkFolderRecord` carry `id` and `createdAt` but no `modifiedAt`. **v1 adds `modifiedAt: Date?`** — optional, so every record stored before decodes untouched (the profile-face precedent), set on every write from v1 on — and a decode test proves the old JSON still reads.

```
container    iCloud.com.zincoo.limeghost      shared by Mac and iOS; the Mac needs real signing first
database     private only                     Limeghost holds nothing; Apple holds keys unless Advanced Data Protection is on
zones        one per profile: profile-<uuid>  default profile = profile-default
records      Bookmark, BookmarkFolder         mirroring the Core records field for field
scope        bookmarks, folders, icon and colour IDs; never history, session, exceptions, site icons
conflicts    per-record last-writer-wins on modifiedAt; a delete loses to a newer edit; cycles resolved by the existing Core normalisation
truth        the device store stays authoritative; CloudKit mirrors it; lastKnownGood untouched
control      Settings → Bookmarks → "Keep bookmarks in iCloud", OFF by default
```

Off by default keeps the "stay local" sentences in the privacy documents true until a person chooses otherwise. When v1.1 lands, those sentences gain "…unless you turn on iCloud bookmarks in Settings," the toggle's own text says where the keys are, and the introduction gets a guard test like the one that already fails on a false privacy claim.

### 6.7 Privacy manifest

The Mac's `PrivacyInfo.xcprivacy` (no tracking; `CA92.1` for UserDefaults) is reused by the iOS target. The implementation plan checks whether the favicon cache's file-date reads need a file-timestamp reason added.

## 7. Distribution, licensing, documents

### 7.1 The $0 path — v1's whole distribution

Xcode, the founder's personal team, free provisioning, the founder's iPhone. The certificate lasts seven days; the build is reinstalled weekly, over Wi-Fi once paired. The Simulator carries daily work and CI. Free provisioning does **not** grant TestFlight, default-browser registration, passkeys, CloudKit, or Handoff. Nobody but the founder can install it. The documents say so.

### 7.2 After enrolment

TestFlight for the creator testers `docs/go-to-market.md` describes, then the App Store. Three entitlements, each verified against Apple's current documentation before it is promised: iCloud/CloudKit (self-serve); `com.apple.developer.web-browser` for default browser (Apple-approved); `com.apple.developer.web-browser.public-key-credential` for passkeys (iOS 17.4+, Apple-approved).

### 7.3 App Store facts for a browser

Guideline 2.5.6 requires WebKit — met natively. Unrestricted web access rates the app **17+**; that is Apple's questionnaire, not a choice. The App Privacy label answers "Data Not Collected" — true of the app; what a provider's site collects inside its own web view is that provider's disclosure. A public privacy policy URL is required at submission (`docs/privacy-and-safety.md`, production requirement 1).

### 7.4 Licensing

The repository stays AGPL-3.0 with no per-file headers. The store binary ships under the copyright holder's separate terms; Apple's standard EULA suffices unless the founder wants his own. `docs/ip-and-ownership.md` gains three sentences: store distribution is under separate terms and does not alter the repository licence; the two `WIP: Claude Code rate-limit checkpoint` commits are auto-checkpoints of founder-directed work, not contributions; the iOS bundle identifier is `com.zincoo.limeghost`. Outside patches stay closed until the contributor-agreement decision; the store build now depends on that. Stickies (CC BY 4.0) and EmojiOne (CC BY-SA 4.0) attribution reaches iOS inside `LimeghostIconPicker`, which is platform-neutral; Settings → About repeats it.

### 7.5 Documents that change — nothing rewritten, everything dated

| File | Change |
|---|---|
| `docs/product-foundation.md` | "mobile browser" leaves the non-goals; a dated note records the reversal and §1.1's reasoning |
| `docs/limeghost-strategy.md` | "macOS first" becomes "macOS first, iOS second, one Core and model layer"; the roadmap gains the iOS line; the sentence "neither should start before an outside tester can install" **stays**, with a dated paragraph recording the conscious exception |
| `docs/project-context.md` | one dated entry: the decisions in §1, sync designed for v1.1, dual-license for the store build |
| `docs/privacy-and-safety.md` | "local Mac user profile" → "local profile on this device" where the sentence covers both; a line that Password AutoFill is the system's and Limeghost stores no credentials; the sync sentence only when v1.1 ships |
| `docs/ios-browser-foundation.md` | **new**, sibling of the macOS foundation document: targets, build and run commands, what is shared, what is iOS-only, what waits on enrolment, the device-only checklist |
| `CLAUDE.md`, `AGENTS.md` | build commands; the constraints agents would otherwise break: the shared-target boundary, no `#if os` in the shared model, overlay-not-sheet, keys stay `clearframe.*`, the phone assistant rules |
| `README.md`, `CHANGELOG.md` | platform section, limits list, documentation index, entry |
| `docs/go-to-market.md` | one dated paragraph: iOS exists for the founder only until enrolment; it is not marketed; the wedge is unchanged |

No document claims signing, notarization, TestFlight, or App Store readiness for either platform.

## 8. Success criteria for v1

1. `xcodebuild test` on an iOS Simulator is green in CI, and the Mac job is unchanged and green.
2. The shared contract (`LimeghostCoreTests`) and every test that moved to `LimeghostSharedTests` — the door tests, the two narrow-window tests, the compare tests, data-store recovery, session tests — pass on the Simulator **and** on the Mac.
3. The app installs on the founder's iPhone under free provisioning and survives the seven-day reinstall.
4. The first minute works on the phone without coaching: a new tab opens the AI guide; a task chip shows a small set of paths; a page can be read, extracted in Reader, and copied for AI with the payload and size shown first.
5. The assistant opens on the founder's own account, covers the page, leaves when a page is asked for, comes back from the toolbar button, and a provider's sign-in popup completes over it.
6. Bookmarks exported from the Mac import on the phone by AirDrop, and back.
7. Every document in §7.5 is updated in the same branch, and none claims validation.

## 9. Testing

### 9.1 Runs on the Simulator with no new test written

`LimeghostCoreTests` — the shared contract, `segmentationCases`, `boilerplateCases`, every fixture — builds for any destination the package declares. It is the most valuable test on the phone and costs nothing.

### 9.2 Moves with the code

Every test whose subject moves to `LimeghostShared` moves to `LimeghostSharedTests` and runs on both platforms as the same test. `makeSurfaceTestWorkspace()` builds from a throwaway defaults suite, a two-domain rule list, and `DownloadCenter()` — the one Mac-bound piece — so it moves with a `NoDownloads` stub in that slot.

### 9.3 `AssistantLayout` unit test

Asserts that 390 and 430 (iPhones), 744 (iPad portrait), 1,024 (an older iPad in landscape: Compare offered, page not) and 1,133 (a current iPad in landscape: docked) resolve as §5.2 says, without standing up a view.

### 9.4 The iOS target's own tests, XCTest only

`docs/ip-and-ownership.md` records no third-party code dependencies; that stays true for tests — no snapshot library, no BDD framework. Unit tests cover the bottom-bar model, the tab-switcher model, and import placement. A small XCUITest set walks the doors on a Simulator and checks the overlay leaves and the popup lands over it; it runs locally, not in CI.

### 9.5 The iOS memory instrument

The Mac harness attributes WebContent processes by pid; an iOS app cannot see them. The phone instrument measures **how many tabs and assistants survive a background cycle**: open N, background, foreground, count `webViewWebContentProcessDidTerminate`. Env-gated like `LIMEGHOST_TAB_MEMORY`, kept as an instrument, run on a device before `maximumLiveSessions` is trusted at 2.

### 9.6 Guards that carry

The introduction's copy moves to the shared layer so `testTheIntroductionNeverClaimsAPageIsSentToAProvider` reads one source for both platforms. The theme luminance test stays on the Mac and still governs the phone, which compiles the same file. The smoke suite stays a Mac suite; the session-level fixture checks run on the Simulator through shared tests against the same `run-browser-smoke.sh` fixture server.

### 9.7 Process rules

Every new behaviour test is watched red before the change that turns it green. Automated coverage is not validation.

### 9.8 Device-only checks

Listed in `docs/ios-browser-foundation.md` as a manual checklist: the swipe gesture, AutoFill inside a provider's sign-in, sign-in popups that report back, real memory-pressure behaviour, the seven-day reinstall.

## 10. What waits on enrolment

CloudKit sync (§6.6) · TestFlight and any installer but the founder · default-browser registration · passkeys · Handoff · the App Store itself. One purchase unblocks the cluster; the documents treat it as one decision, and never rank it above work that can be done without it.

## 11. Open questions, deliberately left

- **iPad as a QA target** — works by construction (§5.2); whether v1.x QAs it is a later call.
- **Downloads design** — `WKDownload` + Files; not designed here.
- **Share extension** — receiving a page from Safari; needs an App Group; not designed here.
- **`LimeghostSurfaces` target** — promotion of the path-referenced views after the desktop branch lands.
- **Whether the Mac adopts `onRequestClose`** for self-closing popups — the desktop session's call.
