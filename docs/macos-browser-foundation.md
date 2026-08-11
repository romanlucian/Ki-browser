# Standalone macOS browser foundation

## What is implemented

The primary prototype is a native SwiftUI application under `macos/ClearframeBrowser`. It launches as its own macOS process and window. `WKWebView` renders websites inside that window; it is not an extension hosted by Chrome, Brave, or Edge.

The current version-1 release stage includes:

- multiple independent tabs with a clear tab strip, new/close/next/previous shortcuts, safe teardown, and web popups routed into new tabs;
- a concise, keyboard-accessible first-run introduction with locally persisted completion, existing search-provider selection, privacy explanation, Analyze page teaching, Start browsing handoff, Skip/Back controls, and a Settings revisit action;
- explicit AppKit startup activation plus reliable address-field focus/selection on launch, tab changes, search-provider selection, and start-page reactivation; navigation releases focus back to WebKit, and reactivation does not steal focus from loaded page content;
- back, forward, home, reload, stop, loading progress, and an HTTPS indicator per tab;
- a visible address-bar and Settings chooser for DuckDuckGo, Google, Bing, Brave Search, and Startpage, persisted only in local preferences;
- a native local AI-guide start page with seven task categories (including Create Images and Create Videos), local filtering, concise informational cards, and direct official-site navigation, plus dedicated loading, offline, timeout, missing-host, unsupported-link, and general error states;
- AI-guide card activation that immediately shows the exact HTTPS destination in the address field and a provider-specific loading state; replacement navigation is tracked so cancellation of the underlying local start-page load cannot overwrite the new request;
- opt-out session restoration of up to 12 recent tabs; inactive restored tabs load lazily, and only URL/title/activity metadata is saved;
- user-confirmed downloads with a macOS save dialog and a dedicated toolbar popover containing a clear empty state, visible destination/status, cancel, Reveal in Finder, clear-finished, and Open Downloads Folder controls; WebKit's expected attachment-policy handoff no longer replaces the page with a false “Frame load interrupted” error;
- local bookmarks organized into titled, emoji-labeled folders and nested subfolders, including safe legacy migration to Unfiled, folder create/rename/delete, bookmark moves, and searchable local history with remove/clear controls and a setting to disable history;
- user-triggered, on-device English dictation into the visible address field with review before submission and no background listening;
- user-invoked visible-page extraction that prioritizes rendered reading blocks and filters navigation, consent, hidden, and embedded-media control UI;
- source-language local gist, key points, candidate claims, read time, English-only local Plain English simplification, and explained risk signals;
- a one-source save / second-source comparison flow;
- an optional OpenAI provider and translation action;
- API-key storage in macOS Keychain;
- nineteen tests for the reusable core logic, English/Romanian/French/Simplified-Chinese extraction, media-boilerplate handling, bookmark-tree migration and safe deletion, local AI-tool catalog, local onboarding completion, search endpoint construction, and safe session-record handling.

DuckDuckGo is the changeable initial search default. Submitted search text goes to the selected provider’s ordinary HTTPS results URL; direct website addresses do not. Clearframe requests no search suggestions while the user types and claims no partnership, default-search contract, or revenue-share agreement.

The current app remains the WebKit baseline. A future Chromium/Blink implementation is being evaluated separately through the official Chromium Embedded Framework; see [Chromium migration foundation](chromium-migration.md). The scaffold is not linked into this app.

## Code boundaries

`ClearframeCore` is intentionally UI- and WebKit-independent:

- page and analysis models;
- serializable tab, bookmark, history, and workspace records;
- a platform-neutral local bookmark-folder tree with invalid-reference/cycle normalization and lossless legacy migration;
- local analysis and simplification;
- visible-page risk heuristics;
- source comparison;
- `PageIntelligenceProviding` protocol;
- optional Responses API provider.
- static AI-tool catalog models and local filtering.

`ClearframeBrowser` is macOS-specific:

- SwiftUI app/window and assistant views;
- `WKWebView` lifecycle and navigation;
- JavaScript extraction from the current page;
- macOS Keychain settings.
- local search-provider preferences and address/search resolution.
- native AI-guide start-page presentation.

A future Windows app should implement the same page-intelligence contract with a Windows-native UI and likely WebView2 or another chosen engine. SwiftUI and WebKit code will not transfer directly.

## Build, open, and test

Create the local Finder app:

```bash
cd macos/ClearframeBrowser
./scripts/build-macos-app.sh
```

Open `dist/Clearframe.app` from Finder at the repository root. This bundle is ad hoc signed for local execution only; it is not Developer ID signed or notarized.

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
- **Basic tabs, not Chrome-scale tab management.** This release is single-window and has no tab reordering, pinned tabs, tab groups, multiple profiles, private windows, or cross-device sync. Restoration reloads the current URL; it does not preserve back/forward stacks, form state, or page content.
- **Basic downloads, not a production download service.** Downloads use a user-selected destination and remain visible in a dedicated toolbar panel while the app runs. The panel explains an empty session and can open the Downloads folder, but there is no byte-level progress, persisted download list, pause/resume UI, background transfer service, quarantine scanner, or reputation verdict.
- **Local bookmark organization, not sync.** Folder titles, emoji, hierarchy, and bookmark placement remain in the current Mac user profile. Legacy flat records become Unfiled; deleting a non-empty folder rehomes its direct bookmarks/subfolders after confirmation. There is no drag-and-drop, account, cloud backup, conflict resolution, or cross-device sync.
- **Incomplete browser services.** There is no password/import system, certificate-detail UI, comprehensive site-permission center, content blocker, full browsing-data manager, crash reporter, updater, or enterprise policy.
- **Distribution is unfinished.** A local `.app` bundle is generated in `dist`, but a public release still needs a maintained Xcode release target, Developer ID signing, notarization, hardened-runtime/entitlement review, update delivery, accessibility QA, and release engineering.
- **Security claims are narrow.** WebKit provides a modern rendering process, but Clearframe has not completed an independent browser security review. Its risk scanner reads only visible text and page-level facts.
- **Platform-specific UI.** SwiftUI is appropriate for macOS but does not create a Windows/Linux interface for free.

These are acceptable limits for validating the source-aware assistant. They become architecture decision inputs only after retention and workflow evidence exist.

## Remaining release stages

1. Add navigation/download integration tests, hostile-page fixtures, crash-recovery testing, and manual QA across supported macOS hardware.
2. Link every summary point to highlighted page evidence and add sensitive-identifier redaction before cloud analysis.
3. Add a permission center, clearer certificate/site-information UI, private browsing, and complete browsing-data deletion controls.
4. Replace direct prototype API access with an authenticated, metered backend and abuse controls.
5. Convert the local bundle workflow into a maintained Xcode release target, then complete accessibility QA, hardened-runtime configuration, Apple signing, notarization, updater/distribution work, and an independent security review.

Signing, notarization, App Store distribution, password-manager security, and production security review are not complete in this repository.
