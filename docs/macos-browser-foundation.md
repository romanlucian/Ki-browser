# Standalone macOS browser foundation

## What is implemented

The primary prototype is a native SwiftUI application under `macos/ClearframeBrowser`. It launches as its own macOS process and window. `WKWebView` renders websites inside that window; it is not an extension hosted by Chrome, Brave, or Edge.

The current version-1 release stage includes:

- multiple independent tabs with a clear tab strip, `⌘T` new-tab, `⌘⇧N` private-tab, `⌘W` current-tab close, next/previous shortcuts, safe teardown, and popups routed into same-privacy-mode tabs; a `window.open()` popup adopts the web view WebKit hands over, so `window.opener` stays connected and a popup sign-in can report back to the page that started it, a popup opened with no address yet still gets a tab, and `target="_blank"` links open a credential-free HTTP/HTTPS tab without an opener;
- a concise, keyboard-accessible first-run introduction with locally persisted completion, existing search-provider selection, privacy explanation, Analyze page teaching, Start browsing handoff, Skip/Back controls, and a Settings revisit action;
- explicit AppKit startup activation plus reliable address-field focus/selection on launch, new/start tabs, search-provider selection, and start-page reactivation; ordinary tab changes do not issue a global focus request, navigation releases focus back to WebKit, and reactivation does not steal focus from loaded page content;
- back, forward, home, reload, and stop from the toolbar, from the `⌘R`, `⌘.`, `⌘[`, and `⌘]` menu commands (each disabled when it cannot act), and from the two-finger trackpad back/forward gesture; a back or forward move onto a tab's own start-surface entry restores that start surface instead of failing as an unsupported link; real WebKit loading progress, HTTPS indication, and same-document URL/title synchronization per tab;
- links Clearframe does not navigate to never replace the page being read: `mailto:` and `tel:` go to the macOS app that owns them, and any other unsupported scheme is named in a dismissible notice above the page;
- default-on tracker blocking against a small, first-party curated domain list, enforced locally through WebKit's `WKContentRuleList` engine, with an address-bar shield control, a Settings switch and exceptions list, and state-only status text with no per-page or running block counts; while the rule list is still compiling the shield states that nothing is being blocked yet, because nothing is attached to the page (see [Tracker blocking](content-blocking.md));
- a visible address-bar and Settings chooser for DuckDuckGo, Google, Bing, Brave Search, and Startpage, persisted only in local preferences; the query is percent-encoded so characters these engines read as query syntax — `+` above all — reach them as the words that were typed;
- a native local AI-guide start page with seven task categories (including Create Images and Create Videos), local filtering, concise informational cards, transparent task-specific editorial badges/ordering, broad access labels, a visible manual checked date/version, official rationale sources, and direct official-site navigation, plus dedicated loading, offline, timeout, missing-host, unsupported-link, and general error states;
- AI-guide card activation that immediately shows the exact HTTPS destination in the address field and a provider-specific loading state; replacement navigation is tracked so cancellation of the underlying local start-page load cannot overwrite the new request;
- opt-out session restoration of up to 12 recent regular tabs; inactive restored tabs load lazily, only validated URL/title/activity metadata is saved, private tabs are excluded, and corrupt records are quarantined/recovered from a last-known-good copy where available;
- user-confirmed downloads with a macOS save dialog and a dedicated toolbar popover containing a clear empty state, visible destination/status, cancel, Reveal in Finder, clear-finished, and Open Downloads Folder controls; choosing Replace in the save dialog removes the existing file so the transfer proceeds instead of failing after that consent; a `download` link to a `blob:` or `data:` address is treated as the download it is rather than refused as an unsupported scheme; and WebKit's expected attachment-policy handoff no longer replaces the page with a false “Frame load interrupted” error;
- a visible-by-default native bookmarks bar directly below navigation, showing compact top-level emoji folders and Unfiled bookmarks, recursive nested-folder menus, horizontal scrolling, a fixed More overflow menu, a clear empty state, and a locally persisted Settings/Page-menu show-hide control; the address field's lock/globe chip is a native URL drag source, bar space and visible emoji folders are highlighted drop targets, and saved bar/organizer bookmarks can be moved by URL drag without duplication; native secondary-click/Control-click actions can add the current page, file it into a folder, create a root folder or subfolder, open the full-page bookmarks home, or hide the bar, with equivalent More/Page-menu access and ⌘⌥B for keyboard users;
- a unified single-row dark chrome with inline traffic lights in the tab strip, one toolbar/address-pill row, and per-site icons captured only during an actual visit from the visited site's own origin, cached in the local profile with a deterministic identity-color square fallback for unvisited hosts (no third-party icon service);
- a full-page bookmarks home (⌘⌥B or the bookmarks bar) with folder cards showing rolled-up bookmark/subfolder counts, search across bookmarks and folder titles, drill-down navigation, and a restyled local history view; the toolbar's Library button keeps a separate quick popover;
- local bookmarks organized into titled, emoji-labeled folders and nested subfolders, including safe legacy migration to Unfiled, folder create/rename/delete, bookmark moves, and searchable local history with per-entry removal and a confirmed Clear History in both the quick popover and the bookmarks home; turning off “Save browsing history” stops Clearframe recording new visits and leaves the visits already stored in place;
- user-triggered, on-device English dictation into the visible address field with review before submission and no background listening;
- user-invoked visible-page extraction that prioritizes rendered reading blocks, includes open Shadow DOM reading content, and filters navigation, consent, hidden, and embedded-media control UI; Analyze page refuses immediately, and says so, on a tab that holds no web page, and every path that abandons an analysis mid-read settles on a state the reader can act on rather than an endless spinner;
- source-language local gist, key points, candidate claims, read time, exact-text Evidence Mode with best-effort live-page highlighting, English-only local Plain English simplification, and explained risk signals;
- a one-source save / second-source comparison flow;
- an optional OpenAI provider and translation action with minimized disclosed payloads, strict analysis output, cancellation/stale-navigation guards, timeouts, and local-result preservation on remote failure;
- API-key storage in macOS Keychain;
- non-persistent private-tab website storage, no private history/restoration, a user-confirmed all-browser-data reset, external HTTP/HTTPS event handling, visible JavaScript/media-permission prompts, and a renderer-termination error state;
- Swift unit/integration suites plus a deterministic desktop smoke covering reusable core behavior, provider contracts/failures, persistence recovery, navigation policy, private tabs, multilingual extraction, media/hidden-content filtering, open Shadow DOM, SPA chrome synchronization, evidence highlighting, popup teardown, bookmarks, history, search, and session restoration.

DuckDuckGo is the changeable initial search default. Submitted search text goes to the selected provider’s ordinary HTTPS results URL; direct website addresses do not. Clearframe requests no search suggestions while the user types and claims no partnership, default-search contract, or revenue-share agreement.

The current app remains the WebKit baseline. A future Chromium/Blink implementation is being evaluated separately through the official Chromium Embedded Framework; see [Chromium migration foundation](chromium-migration.md). The scaffold is not linked into this app.

## Code boundaries

`ClearframeCore` is intentionally UI- and WebKit-independent:

- page and analysis models;
- serializable tab, bookmark, history, and workspace records;
- a platform-neutral local bookmark-folder tree with invalid-reference/cycle normalization, lossless legacy migration, and a credential-free `http`/`https` URL policy for bookmark drags;
- local analysis and simplification;
- visible-page risk heuristics;
- source comparison;
- `PageIntelligenceProviding` protocol;
- optional Responses API provider.
- static AI-tool catalog models, maintainable local configuration, release metadata, task-specific editorial ordering, and local filtering.
- a first-party curated tracker-domain catalog and a deterministic WebKit content-rule-list generator.

`ClearframeBrowser` is macOS-specific:

- SwiftUI app/window and assistant views;
- `WKWebView` lifecycle and navigation;
- JavaScript extraction from the current page;
- macOS Keychain settings.
- local search-provider preferences and address/search resolution.
- native AI-guide start-page presentation.
- local tracker-blocking settings/provider and the address-bar shield/Settings UI.
- the Halo chrome's design tokens (surfaces, text tiers, accent, hairlines, radii, meta type), centralized in `ClearframeTheme.swift` rather than restated per view.

A future Windows app should implement the same page-intelligence contract with a Windows-native UI and likely WebView2 or another chosen engine. SwiftUI and WebKit code will not transfer directly.

## Build, open, and test

Create the local Finder app:

```bash
cd macos/ClearframeBrowser
./scripts/build-macos-app.sh
```

Open `dist/Clearframe.app` from Finder at the repository root. The script generates the app icon, embeds `PrivacyInfo.xcprivacy`, validates bundle metadata, enables the hardened runtime with narrow camera/microphone entitlements, and ad hoc signs/verifies the bundle for local execution. `CLEARFRAME_SIGNING_IDENTITY` can select an available signing identity, but notarization is a separate credentialed release step. The checked-in result is not Developer ID signed or notarized.

For development and verification:

```bash
cd macos/ClearframeBrowser
swift test
swift run ClearframeBrowser
./scripts/run-browser-smoke.sh
```

If Swift cannot write its user-level module cache:

```bash
mkdir -p .build/module-cache
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
swift run --disable-sandbox ClearframeBrowser
```

## Unavoidable limits versus a production Chromium browser

WebKit is a pragmatic macOS-first engine, but this foundation is not equivalent to Chrome, Safari, or a maintained Chromium fork.

- **No Chrome extension ecosystem.** `WKWebView` cannot install ordinary Chrome Web Store extensions.
- **Engine differences.** Sites are rendered by Apple WebKit, so behavior and debugging can differ from Chromium/Blink.
- **Provider-page performance varies.** Clearframe uses WebKit's default persistent website data store and does not proxy, prefetch, or rewrite third-party media. Media-heavy pages such as ByteDance Seed may load images or video incrementally as the user scrolls. Compare the exact URL in Safari on the same connection, once cold and once after caching; a repeatable Clearframe-only slowdown needs a separate WebKit/network trace.
- **Basic tabs, not Chrome-scale tab management.** This release was single-window and had no tab reordering, pinned tabs, tab groups, multiple profiles, separate private windows, or cross-device sync. Tab reordering, pinned tabs, tab groups, multiple windows, and dragging a tab into its own window landed later, in August 2026; multiple profiles, private windows, and sync remain absent. Private tabs are clearly marked, use an ephemeral WebKit data store, and avoid local history/restoration, but do not provide network anonymity. Restoration reloads the current URL; it does not preserve back/forward stacks, form state, or page content.
- **Basic downloads, not a production download service.** Downloads use a user-selected destination and remain visible in a dedicated toolbar panel while the app runs. The panel explains an empty session and can open the Downloads folder, but there is no byte-level progress, persisted download list, pause/resume UI, background transfer service, quarantine scanner, or reputation verdict.
- **Local bookmark bar and organization, not sync.** Bar visibility, folder titles, emoji, hierarchy, and bookmark placement remain in the current Mac user profile. A native URL drag can create a bookmark in Unfiled or a visible folder, and dragging an existing bookmark moves that one record. It does not drag folders, reorder items, expose closed nested-menu rows as targets, or replace the accessible Move menu. Hiding the bar does not delete anything. Legacy flat records become Unfiled; deleting a non-empty folder rehomes its direct bookmarks/subfolders after confirmation. There is no account, cloud backup, conflict resolution, or cross-device sync.
- **Incomplete browser services.** There is no password/import system, certificate-detail UI, comprehensive site-permission center, crash reporter/relaunch recovery, updater, or enterprise policy. Per-site data can now be listed and removed one site at a time, from the address-bar site panel or Settings, but WebKit reports only which kinds of data a site holds — never a size or a count — so Clearframe cannot show how much a site stored. Tracker blocking (see [Tracker blocking](content-blocking.md)) is a small first-party curated domain list, not a comprehensive ad blocker. The delivered reset removes all Clearframe browsing records, per-site tracker-blocking exceptions, and WebKit website data at once.
- **Distribution is unfinished.** A hardened-runtime local `.app` bundle and CI checks are generated, and the source license is settled (AGPL-3.0, `LICENSE`), but a public release still needs a maintained Xcode archive/release target, Developer ID credentials/signing, notarization, entitlement review, update delivery, accessibility QA, and release engineering.
- **Default-browser registration is only a prerequisite.** The app declares HTTP/HTTPS handling and safely opens incoming web URLs, but Clearframe does not silently change the user's default browser. Finder/System Settings registration and default selection still need release QA after a Developer ID-signed installation.
- **Security claims are narrow.** WebKit provides a modern rendering process, but Clearframe has not completed an independent browser security review. Its risk scanner reads only visible text and page-level facts.
- **Platform-specific UI.** SwiftUI is appropriate for macOS but does not create a Windows/Linux interface for free.

These are acceptable limits for validating the source-aware assistant. They become architecture decision inputs only after retention and workflow evidence exist.

## Remaining release stages

1. Expand navigation/download integration tests, hostile-page fixtures, renderer/relaunch-recovery testing, and manual QA across supported macOS hardware.
2. Extend current local key-point evidence into citation-grade grounding for every output and add sensitive-identifier redaction before cloud analysis.
3. Add a permission center, certificate details beyond the connection state the site panel already reports, multiple profiles, and a separate private-window experience.
4. Replace direct prototype API access with an authenticated, metered backend and abuse controls.
5. Convert the local bundle workflow into a maintained Xcode archive/release target, then complete accessibility QA, entitlement review, Apple signing, notarization, updater/distribution work, and an independent security review. The source license is already settled (AGPL-3.0); a contribution-terms policy is not.

Signing, notarization, App Store distribution, password-manager security, and production security review are not complete in this repository.
