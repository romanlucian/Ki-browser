# iOS pocket browser foundation

**Status: September 3, 2026.** This is the sibling of [docs/macos-browser-foundation.md](macos-browser-foundation.md) for the phone, and it describes far less, because far less exists. The design is [docs/superpowers/specs/2026-09-03-ios-pocket-browser-design.md](superpowers/specs/2026-09-03-ios-pocket-browser-design.md); the decision record is [docs/project-context.md](project-context.md); the plan that built the boundary this document describes is [docs/superpowers/plans/2026-09-03-limeghost-shared-layer.md](superpowers/plans/2026-09-03-limeghost-shared-layer.md). Read those for the *why*; this file is the *what*, meant to stay current as later plans build on it.

## What exists, and what does not

What exists is a boundary, not an app. `macos/LimeghostBrowser/Package.swift` now declares a `LimeghostShared` target: platform-neutral code that needs more than `LimeghostCore`'s Foundation-only layer — `@MainActor`, `WKWebView` types, `ObservableObject` — but none of AppKit, UIKit, or SwiftUI. It holds `BrowserSession` and `BrowserWorkspace` behind platform-seam protocols, the assistant (`AICompanion`), the bookmark/history/preference stores, site icons, connection security, content-blocking and search settings, page find, onboarding, and more: 23 files, moved out of `LimeghostBrowser` rather than rewritten, each carrying its git history forward (`git log --follow` confirms it file by file). It typechecks against the iOS 17 SDK — see **Build and test** below for the exact command, because there is no way yet to build an app with it.

What does not exist is everything spec §4 onward describes. There is no `ios/` directory, no Xcode project, no app target, no phone shell, no bottom bar, no tab switcher, no bookmark-import share-sheet integration, nothing installed on a device. This document is worth writing now because the ground the phone app will stand on is real and worth recording precisely before more gets built on it — not because there is a phone app yet to describe.

## Targets

`macos/LimeghostBrowser/Package.swift` declares four build targets and three test targets:

- **`LimeghostCore`** — unchanged by this work. Foundation and CoreGraphics only, no `#if os`, no resources. Confirmed to compile for iOS by emitting a real iOS module from it (below), not by reading its imports.
- **`LimeghostShared`** — new. Depends only on `LimeghostCore`. Links `WebKit`, `AVFoundation`, and `Speech`, because `BrowserSession` and the voice controller need those types even though nothing in this target draws UI. No `#if os(...)` anywhere in it — a platform difference is a protocol member, never a conditional (see **Code boundaries**).
- **`LimeghostBrowser`** — the existing macOS app executable. Now depends on both `LimeghostCore` and `LimeghostShared`. What remains in it is SwiftUI chrome, AppKit-specific code, and the platform-neutral SwiftUI surfaces described below that have not moved yet.
- **`LimeghostCoreTests`**, **`LimeghostSharedTests`**, **`BrowserBehaviorTests`** — one test target per build target's own layer, plus `BrowserBehaviorTests` for everything that still needs the app target (it depends on all three).

`Package.swift`'s `platforms` list carries `.iOS(.v17)` alongside `.macOS(.v14)` — iOS 17 is the floor because `WKWebsiteDataStore(forIdentifier:)`, `.focusable` on iOS, and `onChange(of:initial:)` all arrive there. `swiftLanguageModes: [.v5]` is unchanged, and no third-party dependency was added anywhere in this work.

## Code boundaries

- **`LimeghostCore`** — reusable models, deterministic local analysis, risk heuristics, the AI-tool catalog, the tracker-domain list and rule-list generator. Independent of SwiftUI and WebKit; this was already true before this plan and remains the easiest layer to reason about.
- **`LimeghostShared`** — `BrowserSession` behind `BrowserSessionPlatform` (opening an external scheme, the three JS dialogs, the file picker, printing, following the system's appearance, and the one-time web view setup a platform needs to do); `BrowserWorkspace` behind the collaborator protocols in `WorkspaceCollaborators.swift` (`PageSharing`, `ClipboardWriting` — saving, exporting, sharing, and the clipboard stay app-target concerns the workspace only calls through a seam); `AICompanion`; `AssistantLayout` (the pure width thresholds — `companionWidth`, `minimumReadableWidth`, and the "fits beside the page" / "fits two assistants" predicates — extracted so both platforms read the same numbers); the bookmark/history/AI-tool-shelf store (`BrowserDataStore`) and `BrowserPreferences`; `BookmarkDragPayload` (how a bookmark folder describes itself mid-drag); `ContentRuleListProvider` and `ContentBlockingSettingsStore`; `SearchSettingsStore` and `WebFeatureSettingsStore`; `PageFindController`; `OnboardingController`; `BrowserUserAgent`; `SiteDataInventory`; `VoiceInputController`; `FaviconStore` (rebuilt on `CGImage` rather than `NSImage`, so it no longer needs AppKit) and `IdentityColor` (its hard dependency for the unvisited-host fallback square); `ConnectionSecurity` (the cases and `.make(...)`, split from the chrome-facing presentation that stayed behind in `SiteInformationViews.swift`); `ReaderArticle` (split out of `ReaderView.swift`, so what Reader shows and what Copy for AI copies stay provably one value on both platforms).
- **`LimeghostBrowser`** — SwiftUI windows and chrome, AppKit-specific code (`MacSessionPlatform`, the macOS conformer of `BrowserSessionPlatform`; `PageFileCommands`, the macOS conformer of `PageSharing`), the tab strip, the settings window, `BrowserServices`, app lifecycle, downloads — and, notably, **five files that use an AppKit type while importing none of it**, which is exactly the failure mode this whole boundary was scoped around: `WebView.swift` (`NSViewRepresentable`), `TabStripViews.swift` (`NSEvent`), `LimeghostBrowserApp.swift` (`NSApplicationDelegateAdaptor`), `SiteInformationViews.swift` (`\.openSettings`, unavailable on iOS), and `BookmarkImportSources.swift` (`fileManager.homeDirectoryForCurrentUser`, unavailable on iOS — the one Foundation-only gap in this set, not an AppKit one at all). A search for `import AppKit` would have called every one of these five portable. See the corrected table in [the design spec's §3.1](superpowers/specs/2026-09-03-ios-pocket-browser-design.md) for the full accounting, including why `BookmarkImportSources.swift` needs its own platform seam before an iOS bookmark-import bridge can be built.
- **Platform-neutral SwiftUI surfaces, not yet moved** — `LimeghostTheme`, `AIToolStartPage`, `BookmarksHomePage`, `HistoryHomePage`, `ReaderView`, `LimeghostIconView`, `LimeghostIconPicker`, `ChromeIcons`, `ContentBlockingViews`, `AddressSuggestionsView`. These are believed to compile for iOS — none imports AppKit, and every SwiftUI idiom they use exists on iOS 17 — but **that belief has not been checked with the compiler by this plan**, and this plan's central lesson is that an unchecked belief of exactly that shape is how five other files were miscounted. Run the same typecheck against this row before a later plan relies on it.

## Build and test

From `macos/LimeghostBrowser`:

```bash
swift build   # streams progress; run this before `swift test` on a change that
              # touches LimeghostCore, since every other target rebuilds from it
              # and the silence otherwise looks like a hang
swift test    # 492 executed, 0 failures as of this document (skips vary 2-4
              # by environment and are not a regression — see AGENTS.md)
```

Nothing iOS-specific runs through `swift test`; SwiftPM cannot target iOS directly. Portability is checked with the compiler instead, never with a search for `import AppKit`, because **`import SwiftUI` re-exports AppKit on macOS**: a file can use `NSViewRepresentable` or `NSEvent` while importing nothing called AppKit, and a file that writes `import AppKit` can go on to use none of it. The check that holds up:

```bash
cd macos/LimeghostBrowser/Sources

# LimeghostShared imports LimeghostCore, so emit a real iOS module for it first.
xcrun --sdk iphonesimulator swiftc -emit-module -module-name LimeghostCore \
  -swift-version 5 -target arm64-apple-ios17.0-simulator \
  -emit-module-path /tmp/limeghost-ios/LimeghostCore.swiftmodule LimeghostCore/*.swift

xcrun --sdk iphonesimulator swiftc -typecheck -swift-version 5 \
  -target arm64-apple-ios17.0-simulator -I /tmp/limeghost-ios LimeghostShared/*.swift
```

Both exit 0 with no diagnostics today. This is a typecheck, not a build: it proves the code is legal Swift against the real iOS 17 SDK headers, not that an app built from it would run. It stands in for `xcodebuild` here because this machine has no iOS platform component installed — `xcodebuild -showdestinations` lists iOS under "Ineligible destinations" with the error `iOS 26.5 is not installed. Please download and install the platform from Xcode > Settings > Components.`, and a leftover iOS 26.2 Simulator runtime does not satisfy Xcode 26.6's expected 26.5 platform. Installing the platform is roughly 7–10 GB against 15 GiB free at last check, and has not been requested.

A dedicated scheme, `LimeghostSharedLayer`, is committed at `.swiftpm/xcode/xcshareddata/xcschemes/LimeghostSharedLayer.xcscheme` — necessarily committed, because SwiftPM's own auto-generated per-*product* schemes (the `LimeghostCore` and `LimeghostShared` entries `xcodebuild -list` shows) carry **no test action at all**; only the whole-*package* scheme does, and that one's build action also covers the AppKit-heavy `LimeghostBrowser` executable and `BrowserBehaviorTests`, neither of which can compile for iOS. `LimeghostSharedLayer`'s own build action names exactly `LimeghostCore`, `LimeghostShared`, and their two test targets — confirmed both by reading the checked-in scheme XML and by reading `xcodebuild`'s own "Target dependency graph" output from a real run, which has zero hits for `BrowserBehaviorTests`, `LimeghostBrowser`, `AppKit`, or `Sources/LimeghostBrowser/`. `.gitignore`'s blanket `**/.swiftpm/` rule carries explicit exceptions down to `xcshareddata/xcschemes/` so this file stays tracked; without them the scheme silently disappears from the repository and CI fails on a missing scheme with nothing in the diff to explain why.

That scheme runs today, on this machine, against macOS:

```bash
xcodebuild test -scheme LimeghostSharedLayer -destination 'platform=macOS'
```

249 tests pass — `LimeghostCoreTests` plus `LimeghostSharedTests`, the portable half of the 492-test suite. This does not prove the iOS Simulator destination works; only the `ios-simulator` CI job does that, and only on a machine that has the platform installed.

## Continuous integration

`.github/workflows/ci.yml` gained one job, `ios-simulator`, beside the existing `macos-browser` job. It discovers an available iPhone Simulator at runtime — never a hard-coded OS version, since the runner's image drifts independently of any developer's machine — and runs:

```bash
xcodebuild test -scheme LimeghostSharedLayer -destination "platform=iOS Simulator,id=$SIM_UDID"
```

**This job has never been observed to run, let alone pass, against a real iOS Simulator.** This machine has no iOS platform component installed, so it could not be executed here — see **Build and test** above. What was actually verified, and all that was verified: the scheme resolves and is checked into the repository correctly, it passes when run locally against `platform=macOS`, and its own build graph names only the four portable targets. GitHub's `macos-15` runner image ships the iOS platform this machine lacks, which is why the job is *expected* to work there — expected, not confirmed. Treat it as unverified until its first real run is observed, never as known-green.

## What waits on Apple Developer Program enrolment

Nothing in this layer needed it — `LimeghostShared` typechecks and its tests run under free provisioning and in CI with no paid entitlement. Enrolment ($99/year) gates work later plans will build on this boundary:

- **CloudKit private-database bookmark sync** (spec §6.6) — designed, not built. CloudKit is unavailable under free provisioning.
- **TestFlight**, and any installer besides the founder's own device under free provisioning's seven-day certificate.
- **Default-browser registration** (`com.apple.developer.web-browser`) and **passkeys** (`com.apple.developer.web-browser.public-key-credential`, iOS 17.4+) — both Apple-approved entitlements, neither available unsigned.
- **Handoff**, and the **App Store** itself.

One purchase unblocks this whole cluster. Nothing here ranks it above work that does not need it.

## Device-only checklist, for later plans

None of this can run yet — there is no `ios/` project and nothing installed on a device. Recorded here now, from spec §9.8, so the checklist exists before the app that needs it does:

- **The swipe-down-to-dismiss gesture** on the full-screen assistant overlay (spec §5.1/§5.3) — a Simulator does not reproduce a real swipe convincingly.
- **Password AutoFill inside a provider's sign-in**, offering iCloud Keychain or the person's password manager inside `WKWebView` — something the Mac app cannot do today at all (spec §1.2), and behavior the Simulator's own AutoFill state does not always mirror a device's.
- **Sign-in popups that report back to the assistant** after completing (`webViewDidClose` → `onRequestClose`, spec §5.4) — timing-sensitive WebKit behavior worth confirming on a device.
- **Real memory-pressure behavior.** The Mac harness attributes WebKit content processes by pid; an iOS app cannot see them the same way, and `AICompanion.maximumLiveSessions` (2) was chosen on macOS, where content processes do not exit under memory pressure the way iOS's do. Spec §9.5's instrument — open N tabs and assistants, background, foreground, count `webViewWebContentProcessDidTerminate` — needs a real device before that number is trusted on iOS.
- **The seven-day reinstall**, free provisioning's certificate lifetime (spec §7.1) — whether the app, its data, and any parked assistant state survive a real week and a real reinstall.

## Honesty

No document may describe iOS activation, retention, or usability as validated. No observed-user session has run for this project on either platform, and the iOS side does not yet have an app to observe anyone using. No claim is made of iOS signing, notarization, TestFlight participation, or App Store readiness; free provisioning is the entire distribution story so far, and it reaches exactly one device, the founder's own. The `ios-simulator` CI job is unverified in the specific sense described above — resolves and passes on `platform=macOS`, never yet observed against a real Simulator. If the repository's eventual store build ships under separate commercial terms ([docs/ip-and-ownership.md](ip-and-ownership.md)), that changes distribution terms only; the repository itself stays AGPL-3.0.
