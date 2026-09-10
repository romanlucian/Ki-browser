# Limeghost development instructions

Read both [docs/limeghost-strategy.md](docs/limeghost-strategy.md) and [docs/project-context.md](docs/project-context.md) before changing product direction. This repository’s primary product is a real, standalone macOS browser for ordinary users—not a Chrome extension, programmer-only tool, or generic Chrome clone. The current installed app remains WebKit. Do not begin a Chromium switch; the isolated CEF work is only a future cross-platform/extension-compatibility gate.

## Architecture

- `macos/LimeghostBrowser/Sources/LimeghostCore`: reusable models, deterministic local analysis, risk heuristics, source comparison, and the optional-provider contract. Keep this layer independent of SwiftUI and WebKit where practical.
- `macos/LimeghostBrowser/Sources/LimeghostShared`: added September 3, 2026 for the iOS pocket-browser design (`docs/superpowers/specs/2026-09-03-ios-pocket-browser-design.md`). Platform-neutral code that needs more than `LimeghostCore` can hold — `@MainActor`, `WKWebView` types, `ObservableObject` — but none of AppKit, UIKit, or SwiftUI: `BrowserSession`, `BrowserWorkspace`, `AICompanion`, the bookmark/history/preference stores, `FaviconStore`, and more. See [docs/ios-browser-foundation.md](docs/ios-browser-foundation.md) for the full boundary and how it is verified. **Takes no `#if os(...)`** — a platform difference is a protocol member (`BrowserSessionPlatform`; `WorkspaceCollaborators.swift`'s `PageSharing`/`ClipboardWriting`), never a conditional.
- `macos/LimeghostBrowser/Sources/LimeghostBrowser`: macOS-specific SwiftUI window/UI, AppKit-specific code, tabs, persistence UI, downloads, Keychain settings, and app lifecycle. `BrowserSession`'s WebKit plumbing and the data stores it used to hold directly now live in `LimeghostShared`; this target keeps their macOS conformers (`MacSessionPlatform`, `PageFileCommands`) and everything that draws chrome.
- `chromium/cef-spike`: isolated CEF dependency/build validation and the Swift-facing bridge contract. It is not linked into the current app. Keep CEF C++ types behind Objective-C++ and do not commit downloaded runtimes or generated builds.
- Root Manifest V3 files: earlier extension validation artifact only. Do not present the extension as the primary browser.
- `docs/page-intelligence-contract.md`: conceptual boundary a later Windows implementation can reproduce; native UI code is platform-specific.

## Product and privacy constraints

- Preserve local-first page understanding. Extract and analyze visible page text only after an explicit user action.
- Analyze Page is multilingual by requirement. It extracts the page's rendered reading text, keeps it in the page's own language, and prepares it for the person to copy. It does not summarize or rank, and Limeghost now has no AI of its own at all. Deterministic coverage for risk phrases and sentence segmentation is English, Romanian, French, and Simplified Chinese; do not claim equal quality across all languages.
- Optional provider use must be explicit and visible. Never upload pages merely because they were opened.
- Never sell browsing history, add hidden advertising, claim nonexistent partnerships, or silently bias analysis for a commercial partner.
- Treat the AI home as a curated local directory of official destinations. Task badges are sparse, documented editorial shortcuts based on official product descriptions—not universal/live rankings, Limeghost testing, partnerships, affiliate ordering, exact pricing, or automatic page/prompt sharing. Preserve the visible catalog version/checked date and the policy in `docs/ai-catalog-editorial.md`.
- Voice input must remain user-triggered and visibly active. Do not add background listening, hidden recording, silent cloud fallback, or autonomous transactions.
- Treat page content as untrusted. Keep AI read-only unless a separate threat model, approval flow, and security review exist.
- Risk indicators are explainable signals, not malware, scam, truth, or safety verdicts.
- Text-based risk phrases have narrower language coverage than page extraction. Document that limit instead of implying multilingual security parity.
- Keep history, bookmarks/folder hierarchy/bar visibility, and tab restoration local with clear controls. Preserve legacy bookmarks in Unfiled, the address page-link drag handle, duplicate-safe drops onto bar/visible folders, the accessible Move menu, native secondary-click actions, Page-menu alternatives, and organizer backed by the same records. Accept only safe web URLs and never delete folder contents implicitly. Do not add telemetry by default.

## Shared analysis contract

The Swift (`LimeghostCore`) and JavaScript (`src/core`) local-analysis implementations are intentionally separate — one serves the native app, one the retained extension — but they must stay behaviorally equivalent. Both read the same fixtures:

- `macos/LimeghostBrowser/Tests/LimeghostCoreTests/Fixtures/local-analysis-contract.json` — page structure, risk, reading time, sentence segmentation, and the three interface-noise filters, with expected output; 37 cases across 7 keys;
- `macos/LimeghostBrowser/Tests/LimeghostCoreTests/Fixtures/provider-contract.json` — the shared default provider model.

Swift loads them through `Bundle.module`; Node loads the same files by relative path. Change intended behavior in the contract first, then make both runtimes satisfy it. Never edit one implementation alone, and never fork the fixtures per runtime.

## Safe development rules

- Inspect existing files before editing and preserve unrelated work.
- Do not reintroduce sentence scoring of any kind. Ranking sentences by how often the page repeats their words was removed on August 30, 2026: it measures repetition, not importance, and on a real page it ranked a navigation menu second. See [docs/project-context.md](docs/project-context.md).
- Match claim terms on whole words for non-CJK languages and by substring only for CJK, which has no word boundaries. Bare substring matching wrongly fires “only” inside “commonly.”
- Keep risk heuristics context-aware. A bare mention of remote-desktop software is ordinary technical writing; require nearby action language plus pressure, support, account, security, or payment context before raising a signal.
- Keep the default provider model in one constant per runtime, pinned by `provider-contract.json`. Preserve a user's customized model, migrate untouched defaults automatically, and route unavailable-model errors to Settings while keeping the local result visible.
- Tracker blocking is enforced through `WKContentRuleList` from the curated first-party catalog in `LimeghostCore` (policy: [docs/content-blocking.md](docs/content-blocking.md)). WebKit cannot count blocked requests: the shield and Settings show state only, never numbers. Do not import or convert third-party blocklists without a separate licensing review, and keep the compile canary test that proves the exact shipped rules compile.
- Draw chrome and surface colors from `LimeghostTheme`; do not add new scattered color literals. Semantic status colors (risk levels, failed downloads) are not brand accents. Site icons follow `FaviconStore`'s policy: fetched only during an actual visit, only from the page's own origin or a host that page already loaded a resource from during the same visit (its own CDN, in practice), cached in the local profile, memory-only for private tabs, and wiped by the browsing-data reset. Never contact a third-party icon service — no page loads anything from one, so none can pass that test — and never fetch icons for sites the user has not visited; those fall back to `IdentityColor`'s local host-hash square.
- Bookmark folder marks come from `LimeghostIconCatalog`, which ships three styles. Limeghost's own 104 icons are drawn in a 16-unit box at a 1.5 stroke and name no colour, so a folder's tint reaches them; Stickies and the emoji set carry their own colours, so the tint row is hidden for them rather than shown doing nothing. A test checks each style's `isTintable` against its actual artwork, so the claim cannot drift from the drawings. `VectorPathParser` is deliberately strict and all-or-nothing: it resolves groups, `<defs>`, and `<use>`, inherits `fill`/`stroke`/`fill-rule`/`stroke-linecap`/`stroke-linejoin` down the tree, and refuses the whole icon on anything it was not built for. Stroke cap and join default per style — round for Limeghost, SVG's own butt and miter for the licensed sets, since forcing round joins blunts sharp points. `StickiesIconCatalogData.swift` is generated by `scripts/import-stickies-icons.py`; change the artwork and rerun it rather than editing the file. The Streamline attribution is a CC BY 4.0 obligation and stays in the picker.
- The EmojiOne set (1261 icons, CC BY-SA 4.0, `scripts/import-emojione-icons.py`) added transforms and opacity to the parser. Transforms are composed down the tree and baked into coordinates at parse time, so no renderer knows they existed; a rotated or skewed ellipse becomes curves first, because an ellipse primitive cannot tilt. An unreadable transform refuses the icon rather than drawing it in the wrong place. `<use>` resolves against any element carrying an `id`, not only the contents of `<defs>` — this artwork draws a shape once and instantiates it again elsewhere. Do not round these coordinates: the set is drawn almost entirely in relative commands, so rounding accumulates along a path instead of cancelling.
- Icons whose artwork names its own colours draw through a single `Canvas`, not a shape view per element. Measured, not assumed: the heaviest emoji flag is over five thousand paths and cost 320 ms a frame as shape views versus 46 ms in a canvas, and the switch left only two icons in the whole set above one frame's budget. Keep the shape-view path for the Limeghost set, which is the only one that needs the caller's `foregroundStyle` to reach it.
- The repository is licensed under AGPL-3.0 (`LICENSE`, verbatim upstream text). Do not relicense, add per-file license headers, or change the `package.json` SPDX identifier without explicit user direction. Contribution terms (CLA or DCO) remain undecided.
- Keep each page `WKWebView` scoped to its tab and tear its delegates down when the tab closes. The assistant panel is the deliberate exception: `AICompanion` is scoped to the **window**, keeps at most two assistants loaded, and parks the rest by URL — see the companion rules in [CLAUDE.md](CLAUDE.md).
- Never script a provider's page from Limeghost. No typing into it, no pressing send, no reading its answers back. That is a terms boundary, not a feature gap.
- Validate restored/navigation URLs and default to `http`/`https` only.
- Limeghost calls no AI service and stores no credential for one. If that ever changes, do not ship a shared API key: a user key belongs in the macOS Keychain, and a public service requires an authenticated, metered backend.
- Do not claim Developer ID signing, notarization, App Store readiness, password-manager security, download scanning, or production security review unless those tasks were actually completed.
- Update the relevant documentation whenever capabilities, data flow, architecture, or release gaps change.
- Preserve the WebKit baseline while developing CEF in a separate target/output. Do not call Limeghost a Chromium browser until a real CEF runtime is integrated and verified.
- Preserve the product objective “fast and calm even when the web is heavy,” but do not claim Limeghost is the world's lightest or fastest without reproducible evidence.
- Preserve the primary promise: “Limeghost makes the AI world simple for ordinary people.” Favor clarity over feature count. The magic first minute starts from a human task, offers a small set of useful AI paths, and gets an open page ready to hand to the AI the person already uses. Understanding the page is not something Limeghost currently does, and must not be claimed.
- Preserve the roadmap order: Developer ID signing and notarization so an outside tester can open the app at all, then real-user validation, then extraction quality, then whatever reads that extraction. Monetization, search/referral economics and CEF expansion come later — and note that the intended Pro tier assumed Limeghost would provide the AI, which it no longer does.
- Keep early launch founder-led and zero-budget: real demos, personal/creative-community testers, short before/after examples, an honest GitHub build narrative, and learning from observed usage. Never substitute paid ads, spam, fake traction, or guaranteed-growth claims for validation.
- Follow [docs/go-to-market.md](docs/go-to-market.md): keep global English-first positioning but validate first with photographers, designers, video creators, and creative freelancers. Prefer useful workflow/how-to demonstrations over generic tool-list content, and do not recommend paid acquisition before activation, seven-day retention, and organic referral evidence exist.
- The trusted upstream repository is `https://github.com/romanlucian/Ki-browser`. Never force-push or rewrite remote history unless the user explicitly requests it after reviewing the exact impact.

## Build and verification

From `macos/LimeghostBrowser`:

```bash
swift test                       # includes compiling the E2E smoke suite; its live checks skip without the fixture server
./scripts/build-macos-app.sh     # builds dist/Limeghost.app (ad hoc signature, hardened runtime)
./scripts/run-browser-smoke.sh   # serves the fixtures and runs the live smoke checks
```

Plus `npm test` and `npm run validate` from the root. The smoke suite is `Tests/BrowserBehaviorTests/BrowserE2ESmokeTests.swift`, an ordinary member of the test target: **every `swift test` compiles it**, and its live checks run only when `LIMEGHOST_SMOKE_BASE_URL` is set, which the script does. It used to be a standalone file compiled by a hand-maintained list of source files inside the script; that list rotted silently twice in nine days — commits edited the smoke file itself and shipped it uncompilable — so never reintroduce a hand-listed parallel build. A note that stood here claiming both scripts were missing from every commit was wrong: they live under `macos/LimeghostBrowser/scripts/`, not the repository root's `scripts/`.

The smoke test requires a real logged-in macOS desktop session with WebKit/AppKit services available. A headless or restricted agent sandbox may compile the test and expose the SwiftUI window while blocking WebKit’s content process.

**Typechecking is not fitness.** A file that compiles for iOS has not been shown to *work* on iOS, and nothing in a green suite says otherwise. The first three Mac SwiftUI files the phone app reuses were chosen by measuring that they typecheck against the iOS SDK. Running the app is what uncovered that the AI guide, the start surface every new tab opens on, is unusable at 402 points wide: an eight-line headline that breaks mid-word, and nothing actionable above the fold. Since the September 10 merge it is worse, with the headline breaking almost letter by letter. That is a blocking release gate ([docs/ios-browser-foundation.md](docs/ios-browser-foundation.md)), and the compiler had no opinion about any of it. Run the thing on a phone-sized Simulator; do not report a typecheck as though it were a run.

**A Mac change can break the phone with every Mac test green.** The phone compiles five Mac SwiftUI files by reference: `AIToolStartPage.swift`, `LimeghostTheme.swift`, `SiteIconView.swift`, `StartSurfaceChrome.swift` and `BrandMark.swift`. `LimeghostCore` and `LimeghostShared` also run on both platforms. `swift test` cannot see an iOS compile error. Commit `c357511` put five into the iPhone target on September 2, and nothing noticed until the branches were merged on September 10. Before committing a change to any of those files or targets, also run the phone's suite, using the `xcodebuild test -scheme Limeghost` line below.

**Verifying `LimeghostShared` for iOS.** Prove portability with the compiler, never with a search for `import AppKit` — `import SwiftUI` re-exports AppKit on macOS, so an import list alone both under- and over-counts what is actually portable; this was measured wrong repeatedly while building the target (see [docs/ios-browser-foundation.md](docs/ios-browser-foundation.md)). The typecheck below has exactly one job: checking a file that is **not yet in any iOS target**, since SwiftPM cannot build for iOS at all. It is not a substitute for a Simulator run, and it is no longer standing in for one — the iOS 26.5 simulator platform was installed on this machine on September 3, 2026, and `xcodebuild -showdestinations` now lists iOS simulators, iPhone 17 Pro among them, as eligible destinations rather than under "Ineligible destinations".

```bash
cd macos/LimeghostBrowser/Sources
xcrun --sdk iphonesimulator swiftc -emit-module -module-name LimeghostCore \
  -swift-version 5 -target arm64-apple-ios17.0-simulator \
  -emit-module-path /tmp/limeghost-ios/LimeghostCore.swiftmodule LimeghostCore/*.swift
xcrun --sdk iphonesimulator swiftc -typecheck -swift-version 5 \
  -target arm64-apple-ios17.0-simulator -I /tmp/limeghost-ios LimeghostShared/*.swift
```

`LimeghostSharedLayer`, a scheme committed at `.swiftpm/xcode/xcshareddata/xcschemes/` (note the `.gitignore` exceptions carved into its blanket `**/.swiftpm/` rule — without them the scheme file is untracked and CI fails on a missing scheme with nothing in the diff to explain why), builds and tests exactly `LimeghostCore` and `LimeghostShared` plus their two test targets. This needed its own scheme because SwiftPM's auto-generated per-*product* schemes (the `LimeghostCore` and `LimeghostShared` entries in `xcodebuild -list`) carry **no test action at all**; only the whole-*package* scheme does, and that one's build action also drags in the AppKit-heavy `LimeghostBrowser` executable and `BrowserBehaviorTests`, neither of which can compile for iOS.

Verify it locally on both destinations, and verify the app itself alongside it. Start at the repository root and run the block top to bottom; the two schemes live in different projects, so every `cd` is written out rather than assumed.

```bash
# the shared layer, on both destinations
cd macos/LimeghostBrowser
xcodebuild test -scheme LimeghostSharedLayer -destination 'platform=macOS'
xcodebuild test -scheme LimeghostSharedLayer -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# the phone app itself
cd ../../ios
xcodebuild test -scheme Limeghost -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The shared layer runs **256 tests** on both destinations, and the app's own suite runs **27**. Take the 256 from `swift test --list-tests` (236 `LimeghostCoreTests` + 20 `LimeghostSharedTests`; the other 247 of the Mac's 503 are `BrowserBehaviorTests`) and **never from a run's own log**: xcodebuild runs that scheme across parallel workers, which suppresses the `Executed N tests` summary entirely and interleaves the per-case lines, and an interleaved line can be cut mid-name — that is how a correct 249 was once "corrected" to 248. The app's 27 does come from its run, which is not parallelised and prints the summary; read it with `grep -E "^\*\* TEST|Executed [0-9]+ tests"` rather than `tail`, for the same reason the counts above are grepped.

The `ios-simulator` CI job runs the shared-layer scheme, and now the app scheme too, against a Simulator it discovers at runtime on GitHub's macos-15 image. Both commands have been observed passing here against a real iPhone 17 Pro simulator; **the job itself has still never executed**, because `ci.yml` triggers only on push to `main` and on `pull_request`, so a branch push runs nothing. Report the commands as proven and the job as expected, never as known-green. And a passing Simulator run is not a passing *device* run: the Simulator shares the Mac's own libraries and file system, so it cannot show a sandbox, entitlement, or memory-pressure difference. Nothing has been installed on a phone.

From the repository root, validate the retained extension artifact with:

```bash
npm test
npm run validate
```

The preferred user launch path is Finder → `dist/Limeghost.app`. `swift run` is a developer workflow, not the product launch experience.

## Documentation map

- [Strategy, vision, non-goals, and roadmap](docs/limeghost-strategy.md)
- [Durable project decisions](docs/project-context.md)
- [AI catalog editorial and update policy](docs/ai-catalog-editorial.md)
- [Focused zero-budget go-to-market plan](docs/go-to-market.md)
- [Product foundation](docs/product-foundation.md)
- [macOS architecture and release gaps](docs/macos-browser-foundation.md)
- [iOS pocket-browser foundation](docs/ios-browser-foundation.md)
- [Chromium/CEF migration foundation](docs/chromium-migration.md)
- [Privacy and safety](docs/privacy-and-safety.md)
- [Market research](docs/market-research.md)
- [Cross-platform intelligence contract](docs/page-intelligence-contract.md)
- [Voice-first product and technical direction](docs/voice-first-spec.md)
- [Future programmer-focused side concept](docs/programmer-browser-concept.md)
