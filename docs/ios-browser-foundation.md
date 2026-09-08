# iOS pocket browser foundation

**Status: September 9, 2026.** This is the sibling of [docs/macos-browser-foundation.md](macos-browser-foundation.md) for the phone, and it still describes far less, because far less exists. The design is [docs/superpowers/specs/2026-09-03-ios-pocket-browser-design.md](superpowers/specs/2026-09-03-ios-pocket-browser-design.md); the decision record is [docs/project-context.md](project-context.md); the plan that built the boundary this document describes is [docs/superpowers/plans/2026-09-03-limeghost-shared-layer.md](superpowers/plans/2026-09-03-limeghost-shared-layer.md). Read those for the *why*; this file is the *what*, meant to stay current as later plans build on it.

## What exists, and what does not

There is now an app, and there was not one on September 3. `ios/Limeghost.xcodeproj` builds `Limeghost.app`, a SwiftUI iOS application whose entire browsing model is the Mac's own — the same `BrowserWorkspace`, the same `BrowserSession`, the same stores. It runs on a Simulator, and it compiles for the device SDK — a device *build* stops at signing until a team is selected, so no device build has been produced. Nobody has installed it on a phone yet; see **Onto a real iPhone** below, which is a procedure written for the founder rather than a record of something performed.

Underneath it, unchanged, is the boundary the previous plan built: `macos/LimeghostBrowser/Package.swift` declares a `LimeghostShared` target holding platform-neutral code that needs more than `LimeghostCore`'s Foundation-only layer — `@MainActor`, `WKWebView` types, `ObservableObject` — but none of AppKit, UIKit, or SwiftUI. It holds `BrowserSession` and `BrowserWorkspace` behind platform-seam protocols, the assistant (`AICompanion`), the bookmark/history/preference stores, site icons, connection security, content-blocking and search settings, page find, onboarding, and more: 23 files, moved out of `LimeghostBrowser` rather than rewritten, each carrying its git history forward (`git log --follow` confirms it file by file).

What does **not** exist in the phone app, and must not be described as if it does: there is no assistant panel, no Reader, no Copy for AI, no bookmark import, no downloads, no settings screen, no bookmarks or history surface, no tracker-blocking control, no CloudKit sync. `AICompanion` is compiled into the app because it lives in `LimeghostShared`, but nothing on screen reaches it. Those are a later plan's work, and spec §5 onward describes them as design, not as delivery.

**"No downloads" on the phone means no feedback either, not merely no file.** `IOSCollaborators`' `NoDownloads.track` is a no-op, and `BrowserSession.isDownloadTransitionError` (`BrowserSession.swift:754`–`:757`) deliberately swallows WebKit's error 102 as an expected handoff to `WKDownload` rather than reporting it as a page failure — a handoff that reaches `DownloadCenter` on the Mac and reaches nothing here, so tapping a link to a file type WebKit cannot render does nothing at all: no page, no error, no message, no sign that anything was asked for. Downloads being out of v1 is a deliberate scope decision (spec §2 puts them in v1.1+ because on iOS they are Files integration, resumability and a list — a subsystem, not a button); the silence is not, and it is written down here so the plan that eventually builds them knows it is closing a hole rather than only adding a feature.

## The phone app

Ten source files under `ios/Sources`, plus three compiled in by reference from the Mac target (below). What a person can do with it:

- **Tabs**, held by `BrowserWorkspace` — the Mac's, not a phone-shaped copy of it. `WorkspaceHost` owns the one workspace the scene drives and republishes its changes, because SwiftUI observes the host and the workspace's own `objectWillChange` has to reach it or nothing redraws when a tab opens.
- **A bottom bar** — back, the address, the tab count — placed along the bottom because that is where a thumb reaches and because the page's own top is worth leaving alone. It shows the host with `www.` trimmed, or "Search or enter a website" when there is nothing to show.
- **An address sheet** with local-only completion, drawn from bookmarks and history. It submits through `BrowserWorkspace.navigate(_:)` — the door opened in this plan's Task 4 — rather than `open(_:)`, which guards on `WebURLPolicy.validatedURL` and silently refuses a bare host like `example.com`, the commonest thing anybody types. Nothing is sent anywhere while typing; there are no live query suggestions, on this platform or the Mac. **It completes nothing at all in a private tab**, matching `BrowserView.addressSuggestions` on the Mac and the promise `docs/privacy-and-safety.md` already makes: nothing is written in a private tab either way, but reading a saved history back onto the screen would work against what a private tab is for. That guard was missing for as long as the phone had private tabs — the sheet's own comment had left it as a note for whichever task added private browsing, the tab switcher added them, and the note was not a guard. It was found and closed while writing this document, with a test that fails when the guard is removed. **Submitting an empty field does nothing**, for a reason peculiar to this platform: the Mac's address field arrives holding the address already on screen, so a bare Return there reloads the page, while the phone's is always empty by design, so the same keypress handed `navigate` an empty string, `resolve` returned no URL, and the session landed on `.failed` — which is not `.startPage`, so `showsGuide` stopped being true. With no Home button and nothing that resets `startSurface`, one stray tap of Go destroyed that tab's AI guide permanently. A test submits an empty field and a whitespace one and asserts the guide survives both.
- **A tab switcher** with ordinary and private tabs kept visibly apart, a new-tab and new-private-tab control per section, per-tab close, and Reopen closed tab.
- **The AI guide** as the start surface: every new tab opens on it. It is `AIToolStartPage` — the Mac's own view, its own copy, its own catalog — added to the iOS target unchanged. **It does not fit a phone screen; see the release gate below.**
- **Page display** through `WebViewHost`, a `UIViewRepresentable` that hands SwiftUI the web view its `BrowserSession` already owns, keyed on `session.instanceID`. It is the iOS twin of the Mac's `WebView.swift`, and it is very nearly the whole of the difference between the two platforms' page display.

`IOSSessionPlatform` and `IOSCollaborators` implement the platform seams: opening an external scheme, the three JavaScript dialogs, the file picker, printing, appearance, one-time web view setup; the pasteboard; and sharing. Three of `BrowserSessionPlatform`'s eight members do nothing on a phone, and that is the protocol working rather than failing — a platform difference shows up as an implementation that answers "nothing to do", never as a conditional inside the browser.

`ios/Sources/Info.plist` carries `NSAllowsArbitraryLoadsInWebContent` (a browser renders addresses the person chooses, and plenty of the web is still plain `http`; the app's own connections stay under App Transport Security, and it makes almost none), and camera/microphone usage strings for WebKit's own permission prompts. `UIApplicationSupportsMultipleScenes` is **false**, which matters on iPad since `TARGETED_DEVICE_FAMILY` is `"1,2"`: `LimeghostApp` holds one `@StateObject` workspace for the whole process, so a second scene would draw `WebViewHost` for the same `WKWebView` — a view that cannot be in two places at once — and one of the two windows would go blank. Tear-off windows are under "Not on a phone" in spec §2; the key now says so rather than advertising them. The bundle identifier is `com.zincoo.limeghost` — a new identifier for a new app, unrelated to the Mac's deliberately-preserved `com.clearframe.browser`, which must not be tidied for the reasons in `CLAUDE.md`.

**24 tests** run against the app on a Simulator, covering the session platform, the workspace host, the bottom bar's model, the address sheet's submit, its refusal to submit an empty field, its completion and its refusal to complete a private tab, the switcher's private split, and the start surface's two doors.

## Targets

`macos/LimeghostBrowser/Package.swift` declares four build targets and three test targets:

- **`LimeghostCore`** — unchanged by this work. Foundation and CoreGraphics only, no `#if os`, no resources. Confirmed to compile for iOS by emitting a real iOS module from it (below), not by reading its imports.
- **`LimeghostShared`** — depends only on `LimeghostCore`. Links `WebKit`, `AVFoundation`, and `Speech`, because `BrowserSession` and the voice controller need those types even though nothing in this target draws UI. No `#if os(...)` anywhere in it — a platform difference is a protocol member, never a conditional (see **Code boundaries**).
- **`LimeghostBrowser`** — the existing macOS app executable. Depends on both `LimeghostCore` and `LimeghostShared`. What remains in it is SwiftUI chrome, AppKit-specific code, and the platform-neutral SwiftUI surfaces described below that have not moved.
- **`LimeghostCoreTests`**, **`LimeghostSharedTests`**, **`BrowserBehaviorTests`** — one test target per build target's own layer, plus `BrowserBehaviorTests` for everything that still needs the app target (it depends on all three).

`ios/Limeghost.xcodeproj` adds two more, outside the package: **`Limeghost`** (the iOS app, which consumes `LimeghostShared` and `LimeghostCore` as products of the local package at `../macos/LimeghostBrowser`) and **`LimeghostTests`**. The project carries no checked-in scheme; `xcodebuild` autocreates one per target, which was verified from a tracked-files-only copy of the repository rather than assumed, because a missing scheme is a failure with nothing in the diff to explain it.

`Package.swift`'s `platforms` list carries `.iOS(.v17)` alongside `.macOS(.v14)` — iOS 17 is the floor because `WKWebsiteDataStore(forIdentifier:)`, `.focusable` on iOS, and `onChange(of:initial:)` all arrive there. `IPHONEOS_DEPLOYMENT_TARGET` in the Xcode project matches. `swiftLanguageModes: [.v5]` is unchanged, and no third-party dependency was added anywhere in this work.

## Code boundaries

- **`LimeghostCore`** — reusable models, deterministic local analysis, risk heuristics, the AI-tool catalog, the tracker-domain list and rule-list generator. Independent of SwiftUI and WebKit; this was already true before this plan and remains the easiest layer to reason about.
- **`LimeghostShared`** — `BrowserSession` behind `BrowserSessionPlatform` (opening an external scheme, the three JS dialogs, the file picker, printing, following the system's appearance, and the one-time web view setup a platform needs to do); `BrowserWorkspace` behind the collaborator protocols in `WorkspaceCollaborators.swift` (`PageSharing`, `ClipboardWriting` — saving, exporting, sharing, and the clipboard stay app-target concerns the workspace only calls through a seam); `AICompanion`; `AssistantLayout` (the pure width thresholds — `companionWidth`, `minimumReadableWidth`, and the "fits beside the page" / "fits two assistants" predicates — extracted so both platforms read the same numbers); the bookmark/history/AI-tool-shelf store (`BrowserDataStore`) and `BrowserPreferences`; `BookmarkDragPayload`; `ContentRuleListProvider` and `ContentBlockingSettingsStore`; `SearchSettingsStore` and `WebFeatureSettingsStore`; `PageFindController`; `OnboardingController`; `BrowserUserAgent`; `SiteDataInventory`; `VoiceInputController`; `FaviconStore` (rebuilt on `CGImage` rather than `NSImage`, so it no longer needs AppKit) and `IdentityColor`; `ConnectionSecurity`; `ReaderArticle`.
- **`LimeghostBrowser`** — SwiftUI windows and chrome, AppKit-specific code (`MacSessionPlatform`; `PageFileCommands`), the tab strip, the settings window, `BrowserServices`, app lifecycle, downloads — and, notably, **five files that use an AppKit type while importing none of it**, which is exactly the failure mode this whole boundary was scoped around: `WebView.swift` (`NSViewRepresentable`), `TabStripViews.swift` (`NSEvent`), `LimeghostBrowserApp.swift` (`NSApplicationDelegateAdaptor`), `SiteInformationViews.swift` (`\.openSettings`, unavailable on iOS), and `BookmarkImportSources.swift` (`fileManager.homeDirectoryForCurrentUser`, unavailable on iOS — the one Foundation-only gap in this set, not an AppKit one at all). A search for `import AppKit` would have called every one of these five portable. See the corrected table in [the design spec's §3.1](superpowers/specs/2026-09-03-ios-pocket-browser-design.md) for the full accounting, including why `BookmarkImportSources.swift` needs its own platform seam before an iOS bookmark-import bridge can be built.
- **Three Mac SwiftUI files compiled into the iOS app by reference** — `AIToolStartPage.swift`, `LimeghostTheme.swift`, `SiteIconView.swift`. They are not copied and not moved: `ios/Limeghost.xcodeproj` lists them under a "Reused from macOS" group with relative paths into `macos/LimeghostBrowser/Sources/LimeghostBrowser/`, so there is one copy of each and the Mac's build is untouched. **They were chosen by measuring that these three, and only these three, typecheck together against the iOS SDK.** That is a real measurement and it is not enough — see the release gate immediately below.
- **Platform-neutral SwiftUI surfaces, still not moved and still unchecked** — `BookmarksHomePage`, `HistoryHomePage`, `ReaderView`, `LimeghostIconView`, `LimeghostIconPicker`, `ChromeIcons`, `ContentBlockingViews`, `AddressSuggestionsView`. These are *believed* to compile for iOS, and that belief has not been checked with the compiler. Run the typecheck below against this row before a later plan relies on it — and then read the result on a phone-sized screen, which is the lesson of the next section.

## The blocking release gate: the AI guide does not fit a phone

**Typechecking is not fitness, and this is the entry that records the difference.** The three reused files were chosen because the compiler accepted them for iOS. The compiler has no opinion about a 402-point-wide screen, and running the app is what uncovered that the guide is unusable there. Nothing about this was visible in a green suite.

Measured at 402pt wide (iPhone 17 Pro, 874pt tall):

- **The headline occupies eight lines, from roughly y≈300 to y≈1100** — that is, past the bottom of the screen. "Choose the right AI for the job." breaks mid-word into "Choo / se". The site is `AIToolStartPage.swift:73-104`: a 38pt serif headline with `tracking(-1.2)` inside an `HStack` whose other child is a `Label(...)` capsule badge that does not shrink, so the text column is squeezed to a width no headline of that size can use.
- **The catalog status wraps to three lines**, reading "Catalog / 2026.08. / 24.1". The site is `AIToolStartPage.swift:50-68`: an `HStack` of five items sized at 10.5pt with a `Spacer(minLength: 8)` and a trailing button, laid out for a Mac window's width.
- **Nothing actionable is above the fold.** The search field and the first task chips sit at the very bottom edge of the screen. A start surface whose whole job is to begin the first minute with a task presents no task.

A container-level fix was investigated and none is clean: the header's shape, not its container, is what fails. This needs either the file edited — which means giving `AIToolStartPage` a width-aware layout that both platforms share — or a seam added so the phone can supply its own header while reusing the catalog below it. **Until that is done, the AI guide is not shippable at phone width**, and since it is the start surface every new tab opens on, that makes the app not shippable to anyone at phone width either. This is the named blocking item, not a polish note.

Two smaller findings belong beside it, so they are not lost:

- **The shelf grid overflows arithmetically.** `AIToolStartPage.swift:190` builds a fixed six-column `LazyVGrid` with 12pt spacing; at 402pt minus padding, each column is about 40.3pt, and the marks inside are hard-framed at 44pt (`:475`, `:537`). This is arithmetic, not observation — the grid sits below the fold, so nobody has yet seen what it does there.
- **History records "Loading…" as the title of every visited page**, so every address-completion row reads "Loading…". The chain: `BrowserSession.refreshState()` (`BrowserSession.swift:712`) falls back to that placeholder when `webView.title` is empty; `didFinish` (`:1040`–`:1056`) calls `refreshState()` and passes `pageTitle` straight to `onCompletedVisit`; and `BrowserDataStore.recordVisit` (`BrowserDataStore.swift:355`–`:358`) drops a repeat of the same URL inside 30 seconds, so a later correction carrying the real title never lands and the placeholder is permanent. **Nothing in that chain is iOS-specific** — it is a WebKit timing race, observed on iOS, in code both platforms share. A follow-up must measure it on both platforms before anyone decides where the fix belongs; assuming it is a phone bug is how it gets fixed in the wrong place.

## Build and test

From `macos/LimeghostBrowser`, for the shared layer and the Mac app:

```bash
swift build   # streams progress; run this before `swift test` on a change that
              # touches LimeghostCore, since every other target rebuilds from it
              # and the silence otherwise looks like a hang
swift test    # 492 executed, 0 failures as of this document (skips vary 2-4
              # by environment and are not a regression — see AGENTS.md)
```

From `ios`, for the phone app:

```bash
xcodebuild test -scheme Limeghost \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'   # 24 executed, 0 failures
```

Read those counts by grepping (`grep -E "^\*\* TEST|Executed [0-9]+ tests"`), never by tailing: the swift-testing banner interleaves after the XCTest summary, so a `tail` can show a passing run's last line as something else entirely.

Nothing iOS-specific runs through `swift test`; SwiftPM cannot target iOS directly. Portability of a file that has *not* yet been added to the iOS target is checked with the compiler instead, never with a search for `import AppKit`, because **`import SwiftUI` re-exports AppKit on macOS**: a file can use `NSViewRepresentable` or `NSEvent` while importing nothing called AppKit, and a file that writes `import AppKit` can go on to use none of it. The check that holds up:

```bash
cd macos/LimeghostBrowser/Sources

# LimeghostShared imports LimeghostCore, so emit a real iOS module for it first.
xcrun --sdk iphonesimulator swiftc -emit-module -module-name LimeghostCore \
  -swift-version 5 -target arm64-apple-ios17.0-simulator \
  -emit-module-path /tmp/limeghost-ios/LimeghostCore.swiftmodule LimeghostCore/*.swift

xcrun --sdk iphonesimulator swiftc -typecheck -swift-version 5 \
  -target arm64-apple-ios17.0-simulator -I /tmp/limeghost-ios LimeghostShared/*.swift
```

Both exit 0 with no diagnostics. This is a typecheck, not a build: it proves the code is legal Swift against the real iOS 17 SDK headers, and — as the release gate above records at length — it proves nothing whatever about whether the result is usable on a phone.

A dedicated scheme, `LimeghostSharedLayer`, is committed at `.swiftpm/xcode/xcshareddata/xcschemes/LimeghostSharedLayer.xcscheme` — necessarily committed, because SwiftPM's own auto-generated per-*product* schemes (the `LimeghostCore` and `LimeghostShared` entries `xcodebuild -list` shows) carry **no test action at all**; only the whole-*package* scheme does, and that one's build action also covers the AppKit-heavy `LimeghostBrowser` executable and `BrowserBehaviorTests`, neither of which can compile for iOS. `LimeghostSharedLayer`'s own build action names exactly `LimeghostCore`, `LimeghostShared`, and their two test targets — confirmed both by reading the checked-in scheme XML and by reading `xcodebuild`'s own "Target dependency graph" output from a real run, which has zero hits for `BrowserBehaviorTests`, `LimeghostBrowser`, `AppKit`, or `Sources/LimeghostBrowser/`. `.gitignore`'s blanket `**/.swiftpm/` rule carries explicit exceptions down to `xcshareddata/xcschemes/` so this file stays tracked; without them the scheme silently disappears from the repository and CI fails on a missing scheme with nothing in the diff to explain why.

That scheme runs on both destinations:

```bash
xcodebuild test -scheme LimeghostSharedLayer -destination 'platform=macOS'
xcodebuild test -scheme LimeghostSharedLayer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Both report `** TEST SUCCEEDED **`, and both run **249 tests** — `LimeghostCoreTests` (229) plus `LimeghostSharedTests` (20), the portable half of the 492-test suite; the remaining 243 are `BrowserBehaviorTests`, which is the whole of the difference. **Take that number from `swift test --list-tests` and never from a run's own log.** xcodebuild runs this scheme across parallel workers on both destinations — simulator clones on one, `My Mac - xctest` processes on the other — which suppresses the `Executed N tests` summary entirely and interleaves the per-case lines. An interleaved line can be cut mid-name, so counting distinct names in the log comes up one short; that is how a correct 249 in this file was briefly "corrected" to 248. A count taken from the test *list* cannot be truncated by interleaving, which is the same reason the section above says to grep rather than tail. The iOS Simulator destination was first observed passing here on September 3, 2026, with `WorkspaceDoorTests.testEveryWayOfAskingForAPageUncoversIt`, all six `AssistantLayoutTests`, `BrowserSessionPlatformTests` and `FaviconImageCodingTests` each passing on the device. That is the evidence that the shared layer's rules hold on a phone rather than merely compiling for one.

## Onto a real iPhone

**None of what follows has been performed.** It cannot be automated: it needs an Apple ID signed in to Xcode and a physical phone connected to the Mac. It is written down here so the founder can do it, and so nobody reading this file mistakes a procedure for a record.

Signing is arranged in the project so that both destinations work without editing anything. `ios/Limeghost.xcodeproj` sets, on both the app and the test target:

```
"CODE_SIGNING_ALLOWED[sdk=iphonesimulator*]" = NO;
"CODE_SIGNING_REQUIRED[sdk=iphonesimulator*]" = NO;
CODE_SIGN_STYLE = Automatic;
DEVELOPMENT_TEAM = "";
```

The `[sdk=iphonesimulator*]` condition is the whole point. Signing stays off for the Simulator, which is what CI needs — GitHub's runner has no signing identity, and an unconditional `CODE_SIGNING_ALLOWED = NO` was correct there. But an unsigned bundle has nothing for iOS to trust, so the same unconditional setting could never install on hardware. Conditioning it leaves the Simulator path exactly as it was and lets a device build sign normally. `DEVELOPMENT_TEAM` is deliberately empty in the committed file: a team identifier belongs to the person holding the Apple ID and does not belong in a shared repository. **Nothing enforces that, so it is a habit with a check rather than a guarantee.** Picking a team in step 3 makes Xcode write `DEVELOPMENT_TEAM = XXXXXXXXXX;` straight back into the tracked `project.pbxproj`, where a `git add -A` stages it like any other change and the next commit carries it. Before committing, look and put it back:

```bash
git diff -- ios/Limeghost.xcodeproj/project.pbxproj      # expect no DEVELOPMENT_TEAM line
git checkout -- ios/Limeghost.xcodeproj/project.pbxproj  # if one appeared
```

The second command discards *every* change to that file, so make any deliberate project edit in its own step rather than alongside a signing session.

The obvious structural fix does not work: moving the setting into a gitignored `.xcconfig` does not stop Xcode's Signing & Capabilities editor, which writes the pbxproj wherever the value came from. A pre-commit hook would catch it, but a clone installs no hooks. This is stated as what actually happens rather than as an outcome the repository can promise.

That the condition works in both directions was measured, not assumed. The Simulator suite still passes with no identity present, and `xcodebuild build -scheme Limeghost -destination 'generic/platform=iOS'` on this machine now stops with:

```
error: Signing for "Limeghost" requires a development team.
Select a development team in the Signing & Capabilities editor.
```

That failure is the evidence: before this change the device SDK would have skipped signing altogether and produced a bundle no phone would install. It is also exactly what the founder will see if step 3 below is skipped — the fix is to pick the personal team, not to change the project.

The steps, in order:

1. Open `ios/Limeghost.xcodeproj` in Xcode.
2. Sign in with a personal Apple ID: **Xcode → Settings → Accounts**, then **+ → Apple ID**. A free account is enough; Developer Program enrolment is not needed for this.
3. Select the **Limeghost** target → **Signing & Capabilities**, tick **Automatically manage signing**, and choose the personal team from the **Team** menu (it appears as *"<Your Name> (Personal Team)"*).
4. Connect the iPhone to the Mac with a cable and unlock it. Trust the Mac on the phone if it asks.
5. Choose the phone as the run destination in Xcode's toolbar.
6. Press **Run** (⌘R). Xcode builds, signs with the personal team, installs and launches.
7. The first launch will be refused by iOS. On the phone: **Settings → General → VPN & Device Management**, pick the developer entry under *Developer App*, and trust it. Then launch Limeghost from the Home screen.

**Free provisioning issues a seven-day certificate.** After a week the app stops launching, and the way to bring it back is to connect the phone and run it from Xcode again — there is no other way to renew it. That is also why nobody but the founder can install this: free provisioning signs for the devices attached to one Apple ID and nothing else. There is no ad-hoc distribution, no TestFlight, no App Store presence, and nothing here is notarized or signed for distribution in any sense. **Apple Developer Program enrolment ($99/year) is the single thing that changes that**, and it has not been purchased.

## Continuous integration

`.github/workflows/ci.yml`'s `ios-simulator` job now runs two things against one simulator it discovers at runtime — never a hard-coded OS version, since the runner's image drifts independently of any developer's machine:

```bash
xcodebuild test -scheme LimeghostSharedLayer -destination "platform=iOS Simulator,id=$SIM_UDID"   # from macos/LimeghostBrowser
xcodebuild test -scheme Limeghost            -destination "platform=iOS Simulator,id=$SIM_UDID"   # from ios/
```

The second is new. It builds and tests the app itself, so a change that satisfies the shared layer and breaks the phone shell fails here rather than on somebody's device. Its step overrides the job's `working-directory`, because the Xcode project lives at `ios/` while the rest of the job runs from the package. No second job was added and `macos-browser` is untouched.

Both commands have been observed passing locally, on this machine, against a real iPhone 17 Pro simulator. **The CI job itself has still never run**, because `ci.yml` triggers only on push to `main` and on `pull_request` — a branch push runs nothing, so the job's runtime simulator discovery and its YAML remain unexercised until the first pull request. Treat the commands as proven and the job as expected. And a passing simulator run is not a passing *device* run: the simulator shares the Mac's own libraries and file system, so it cannot show a sandbox, entitlement, or memory-pressure difference.

## What waits on Apple Developer Program enrolment

Nothing built so far needed it — the shared layer, the app, and both test suites run under free provisioning and in CI with no paid entitlement. Enrolment ($99/year) gates:

- **Installing on any device but the founder's**, and any certificate that outlives seven days.
- **TestFlight**, and therefore any observed-user session with somebody who is not the founder.
- **CloudKit private-database bookmark sync** (spec §6.6) — designed, not built. CloudKit is unavailable under free provisioning.
- **Default-browser registration** (`com.apple.developer.web-browser`) and **passkeys** (`com.apple.developer.web-browser.public-key-credential`, iOS 17.4+) — both Apple-approved entitlements, neither available unsigned.
- **Handoff**, and the **App Store** itself.

One purchase unblocks this whole cluster. Nothing here ranks it above work that does not need it — and the release gate above is the more urgent blocker of the two, since it costs nothing to fix and no amount of Apple money would make an eight-line headline fit.

## Device-only checklist, for later plans

There is an app now, so this list is finally runnable — but none of it has been run, because nothing has been installed on a phone. From spec §9.8:

- **The swipe-down-to-dismiss gesture** on the full-screen assistant overlay (spec §5.1/§5.3) — a Simulator does not reproduce a real swipe convincingly. The assistant does not exist in the app yet, so this waits on the later plan that builds it.
- **Password AutoFill inside a provider's sign-in**, offering iCloud Keychain or the person's password manager inside `WKWebView` — something the Mac app cannot do today at all (spec §1.2), and behavior the Simulator's own AutoFill state does not always mirror a device's.
- **Sign-in popups that report back to the assistant** after completing (`webViewDidClose` → `onRequestClose`, spec §5.4) — timing-sensitive WebKit behavior worth confirming on a device.
- **Real memory-pressure behavior.** The Mac harness attributes WebKit content processes by pid; an iOS app cannot see them the same way, and `AICompanion.maximumLiveSessions` (2) was chosen on macOS, where content processes do not exit under memory pressure the way iOS's do. Spec §9.5's instrument — open N tabs and assistants, background, foreground, count `webViewWebContentProcessDidTerminate` — needs a real device before that number is trusted on iOS.
- **The seven-day reinstall**, free provisioning's certificate lifetime (spec §7.1) — whether the app, its data, and any parked assistant state survive a real week and a real reinstall.
- **The AI guide at real phone width**, added by this plan — the measurements in the release gate above were taken in a Simulator, and the fix, when it comes, needs looking at on a phone in a hand rather than in a window on a desk.

## Honesty

No document may describe iOS activation, retention, or usability as validated. **No observed-user session has been run for this project on either platform**, and on iOS nobody at all — including the founder — has yet used the app on a phone. No claim is made of iOS signing for distribution, notarization, TestFlight participation, or App Store readiness; free provisioning is the entire distribution story, it reaches exactly one device, the founder's own, and its certificate lasts a week. The `ios-simulator` CI job's two commands pass locally against a real Simulator; the job itself has never executed, for the reason given above. The app's start surface does not fit a phone screen, which is written down above as a blocking release gate rather than left as a defect somebody might discover twice. If the repository's eventual store build ships under separate commercial terms ([docs/ip-and-ownership.md](ip-and-ownership.md)), that changes distribution terms only; the repository itself stays AGPL-3.0.
