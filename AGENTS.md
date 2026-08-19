# Clearframe development instructions

Read both [docs/clearframe-strategy.md](docs/clearframe-strategy.md) and [docs/project-context.md](docs/project-context.md) before changing product direction. This repository’s primary product is a real, standalone macOS browser for ordinary users—not a Chrome extension, programmer-only tool, or generic Chrome clone. The current installed app remains WebKit. Do not begin a Chromium switch; the isolated CEF work is only a future cross-platform/extension-compatibility gate.

## Architecture

- `macos/ClearframeBrowser/Sources/ClearframeCore`: reusable models, deterministic local analysis, risk heuristics, source comparison, and the optional-provider contract. Keep this layer independent of SwiftUI and WebKit where practical.
- `macos/ClearframeBrowser/Sources/ClearframeBrowser`: macOS-specific SwiftUI window/UI, `WKWebView` sessions, tabs, persistence, downloads, Keychain settings, and app lifecycle.
- `chromium/cef-spike`: isolated CEF dependency/build validation and the Swift-facing bridge contract. It is not linked into the current app. Keep CEF C++ types behind Objective-C++ and do not commit downloaded runtimes or generated builds.
- Root Manifest V3 files: earlier extension validation artifact only. Do not present the extension as the primary browser.
- `docs/page-intelligence-contract.md`: conceptual boundary a later Windows implementation can reproduce; native UI code is platform-specific.

## Product and privacy constraints

- Preserve local-first page understanding. Extract and analyze visible page text only after an explicit user action.
- Analyze Page is multilingual by requirement. Local mode must preserve the page's source language and provide private structured extraction; current deterministic coverage is English, Romanian, French, and Simplified Chinese. Do not claim equal semantic quality across all languages. Deeper provider-assisted summarization is optional and explicitly triggered.
- Optional provider use must be explicit and visible. Never upload pages merely because they were opened.
- Never sell browsing history, add hidden advertising, claim nonexistent partnerships, or silently bias analysis for a commercial partner.
- Treat the AI home as a curated local directory of official destinations. Task badges are sparse, documented editorial shortcuts based on official product descriptions—not universal/live rankings, Clearframe testing, partnerships, affiliate ordering, exact pricing, or automatic page/prompt sharing. Preserve the visible catalog version/checked date and the policy in `docs/ai-catalog-editorial.md`.
- Voice input must remain user-triggered and visibly active. Do not add background listening, hidden recording, silent cloud fallback, or autonomous transactions.
- Treat page content as untrusted. Keep AI read-only unless a separate threat model, approval flow, and security review exist.
- Risk indicators are explainable signals, not malware, scam, truth, or safety verdicts.
- Text-based risk phrases and local Plain English rewriting have narrower language coverage than page extraction. Document those limits instead of implying multilingual security or translation parity.
- Keep history, bookmarks/folder hierarchy/bar visibility, and tab restoration local with clear controls. Preserve legacy bookmarks in Unfiled, the address page-link drag handle, duplicate-safe drops onto bar/visible folders, the accessible Move menu, native secondary-click actions, Page-menu alternatives, and organizer backed by the same records. Accept only safe web URLs and never delete folder contents implicitly. Do not add telemetry by default.

## Shared analysis contract

The Swift (`ClearframeCore`) and JavaScript (`src/core`) local-analysis implementations are intentionally separate — one serves the native app, one the retained extension — but they must stay behaviorally equivalent. Both read the same fixtures:

- `macos/ClearframeBrowser/Tests/ClearframeCoreTests/Fixtures/local-analysis-contract.json` — tokenization, summary, risk, Plain English, and reading-time cases with expected output;
- `macos/ClearframeBrowser/Tests/ClearframeCoreTests/Fixtures/provider-contract.json` — the shared default provider model.

Swift loads them through `Bundle.module`; Node loads the same files by relative path. Change intended behavior in the contract first, then make both runtimes satisfy it. Never edit one implementation alone, and never fork the fixtures per runtime.

## Safe development rules

- Inspect existing files before editing and preserve unrelated work.
- Select local-analysis stopwords by the page's declared language. Do not reintroduce a single merged multilingual stopword set; it silently suppresses ordinary English content words such as “care” and “son” and degrades English extraction quality.
- Match claim terms on whole words for non-CJK languages and by substring only for CJK, which has no word boundaries. Bare substring matching wrongly fires “only” inside “commonly.”
- Keep risk heuristics context-aware. A bare mention of remote-desktop software is ordinary technical writing; require nearby action language plus pressure, support, account, security, or payment context before raising a signal.
- Keep the default provider model in one constant per runtime, pinned by `provider-contract.json`. Preserve a user's customized model, migrate untouched defaults automatically, and route unavailable-model errors to Settings while keeping the local result visible.
- Tracker blocking is enforced through `WKContentRuleList` from the curated first-party catalog in `ClearframeCore` (policy: [docs/content-blocking.md](docs/content-blocking.md)). WebKit cannot count blocked requests: the shield and Settings show state only, never numbers. Do not import or convert third-party blocklists without a separate licensing review, and keep the compile canary test that proves the exact shipped rules compile.
- Draw chrome and surface colors from `ClearframeTheme`; do not add new scattered color literals. Semantic status colors (risk levels, failed downloads) are not brand accents. Site icons follow `FaviconStore`'s policy: fetched only during an actual visit, only from the visited site's own origin, cached in the local profile, memory-only for private tabs, and wiped by the browsing-data reset. Never contact a third-party icon service, and never fetch icons for sites the user has not visited; those fall back to `IdentityColor`'s local host-hash square.
- Bookmark folder marks come from `ClearframeIconCatalog`, which ships three styles. Clearframe's own 104 icons are drawn in a 16-unit box at a 1.5 stroke and name no colour, so a folder's tint reaches them; the two licensed Stickies styles are drawn in a 40-unit box and carry their own colours, so the tint row is hidden for them rather than shown doing nothing. `VectorPathParser` is deliberately strict and all-or-nothing: it resolves groups, `<defs>`, and `<use>`, inherits `fill`/`stroke`/`fill-rule`/`stroke-linecap`/`stroke-linejoin` down the tree, and refuses the whole icon on anything it was not built for. Stroke cap and join default per style — round for Clearframe, SVG's own butt and miter for the licensed sets, since forcing round joins blunts sharp points. `StickiesIconCatalogData.swift` is generated by `scripts/import-stickies-icons.py`; change the artwork and rerun it rather than editing the file. The Streamline attribution is a CC BY 4.0 obligation and stays in the picker.
- The EmojiOne set (1261 icons, CC BY-SA 4.0, `scripts/import-emojione-icons.py`) added transforms and opacity to the parser. Transforms are composed down the tree and baked into coordinates at parse time, so no renderer knows they existed; a rotated or skewed ellipse becomes curves first, because an ellipse primitive cannot tilt. An unreadable transform refuses the icon rather than drawing it in the wrong place. `<use>` resolves against any element carrying an `id`, not only the contents of `<defs>` — this artwork draws a shape once and instantiates it again elsewhere. Do not round these coordinates: the set is drawn almost entirely in relative commands, so rounding accumulates along a path instead of cancelling.
- Icons whose artwork names its own colours draw through a single `Canvas`, not a shape view per element. Measured, not assumed: the heaviest emoji flag is over five thousand paths and cost 320 ms a frame as shape views versus 46 ms in a canvas, and the switch left only two icons in the whole set above one frame's budget. Keep the shape-view path for the Clearframe set, which is the only one that needs the caller's `foregroundStyle` to reach it.
- The repository is licensed under AGPL-3.0 (`LICENSE`, verbatim upstream text). Do not relicense, add per-file license headers, or change the `package.json` SPDX identifier without explicit user direction. Contribution terms (CLA or DCO) remain undecided.
- Keep each `WKWebView` and assistant lifecycle scoped to its tab; tear delegates down when closing tabs.
- Validate restored/navigation URLs and default to `http`/`https` only.
- Do not ship shared API keys. Prototype user keys belong in macOS Keychain; a public service requires an authenticated, metered backend.
- Do not claim Developer ID signing, notarization, App Store readiness, password-manager security, download scanning, or production security review unless those tasks were actually completed.
- Update the relevant documentation whenever capabilities, data flow, architecture, or release gaps change.
- Preserve the WebKit baseline while developing CEF in a separate target/output. Do not call Clearframe a Chromium browser until a real CEF runtime is integrated and verified.
- Preserve the product objective “fast and calm even when the web is heavy,” but do not claim Clearframe is the world's lightest or fastest without reproducible evidence.
- Preserve the primary promise: “Clearframe makes the AI world simple for ordinary people.” Favor clarity over feature count. The magic first minute starts from a human task, offers a small set of useful AI paths, and makes an open page understandable with honest grounding; exact cited Evidence Mode is future work, not a current claim.
- Preserve the roadmap order: real-user validation and extraction/performance quality, Evidence Mode and Translate & Explain, release/security work, then optional Pro/team monetization. Search/referral economics and CEF expansion come later.
- Keep early launch founder-led and zero-budget: real demos, personal/creative-community testers, short before/after examples, an honest GitHub build narrative, and learning from observed usage. Never substitute paid ads, spam, fake traction, or guaranteed-growth claims for validation.
- Follow [docs/go-to-market.md](docs/go-to-market.md): keep global English-first positioning but validate first with photographers, designers, video creators, and creative freelancers. Prefer useful workflow/how-to demonstrations over generic tool-list content, and do not recommend paid acquisition before activation, seven-day retention, and organic referral evidence exist.
- The trusted upstream repository is `https://github.com/romanlucian/Ki-browser`. Never force-push or rewrite remote history unless the user explicitly requests it after reviewing the exact impact.

## Build and verification

From `macos/ClearframeBrowser`:

```bash
swift test
./scripts/build-macos-app.sh
./scripts/run-browser-smoke.sh
```

The smoke test requires a real logged-in macOS desktop session with WebKit/AppKit services available. A headless or restricted agent sandbox may compile the test and expose the SwiftUI window while blocking WebKit’s content process.

From the repository root, validate the retained extension artifact with:

```bash
npm test
npm run validate
```

The preferred user launch path is Finder → `dist/Clearframe.app`. `swift run` is a developer workflow, not the product launch experience.

## Documentation map

- [Strategy, vision, non-goals, and roadmap](docs/clearframe-strategy.md)
- [Durable project decisions](docs/project-context.md)
- [AI catalog editorial and update policy](docs/ai-catalog-editorial.md)
- [Focused zero-budget go-to-market plan](docs/go-to-market.md)
- [Product foundation](docs/product-foundation.md)
- [macOS architecture and release gaps](docs/macos-browser-foundation.md)
- [Chromium/CEF migration foundation](docs/chromium-migration.md)
- [Privacy and safety](docs/privacy-and-safety.md)
- [Market research](docs/market-research.md)
- [Cross-platform intelligence contract](docs/page-intelligence-contract.md)
- [Voice-first product and technical direction](docs/voice-first-spec.md)
- [Future programmer-focused side concept](docs/programmer-browser-concept.md)
