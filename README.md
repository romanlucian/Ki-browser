# Clearframe browser prototype

Clearframe is now a **standalone macOS browser foundation** built with SwiftUI and WebKit. It opens its own native window, navigates the web, and includes a source-aware page assistant. The earlier Chromium extension remains in the repository as a useful validation artifact; it is not the final browser.

The installed and `dist` builds still use WebKit. A future Chromium migration now has an isolated [CEF migration plan](docs/chromium-migration.md) and validation scaffold under `chromium/cef-spike`; that scaffold is not linked into the current app and must not be described as a working Chromium build.

The native app provides:

- multi-tab browsing with safe per-tab WebKit and assistant state;
- local restoration of recent tabs, with lazy loading and an opt-out setting;
- downloads with a user-selected destination, visible status, cancel, and reveal controls;
- searchable local bookmarks and history, including clear/disable controls;
- explicit loading, offline, timeout, blocked-link, and general error states;
- explicit on-device voice input that fills the visible address/search field for review without automatic submission;
- a visible, locally persisted search-engine chooser for DuckDuckGo, Google, Bing, Brave Search, and Startpage;
- a native new-tab AI guide with a small, locally defined catalog organized by everyday tasks;
- a concise three-step first-run introduction covering Clearframe's promise, search choice, privacy boundary, AI home, and Analyze page workflow;
- an extractive page summary that works without an account or API key;
- key points and page claims worth checking;
- visible risk signals such as unencrypted password forms, encoded domains, urgent payment language, wallet-secret requests, and remote-access prompts;
- a Plain English mode plus optional AI translation;
- a two-source comparison that highlights shared themes and extracted figures without pretending to decide which source is true.

## Open the standalone macOS browser

Requirements: macOS 14 or newer and Xcode/Swift 6.

The preferred local experience is the Finder-launchable development app:

1. In Finder, open this project’s `dist` folder.
2. Double-click **Clearframe.app**.
3. If macOS asks for confirmation because this local build is not Developer ID signed or notarized, right-click the app, choose **Open**, and confirm. Do not disable Gatekeeper globally.

To rebuild that app first:

```bash
cd macos/ClearframeBrowser
./scripts/build-macos-app.sh
```

The output is `dist/Clearframe.app` at the repository root. It opens as an ordinary macOS application rather than using Terminal as its keyboard target.

For source-level development only, you can still use:

```bash
cd macos/ClearframeBrowser
swift run ClearframeBrowser
```

If Swift’s user cache is restricted in your environment, keep the cache inside the project:

```bash
cd macos/ClearframeBrowser
mkdir -p .build/module-cache
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
swift run --disable-sandbox ClearframeBrowser
```

Then:

1. On the first launch, complete or skip the short introduction. It stores only a local completion flag and your selected search engine. Reopen it later from **Settings → Clearframe introduction**.
2. A new tab opens Clearframe’s local AI guide. Filter by task, or select a card to open that service’s official website.
3. Enter a URL or search in the address bar.
4. Browse with independent tabs; use `⌘T` for a new tab and the tab strip to switch or close tabs.
5. Open **Assistant** and click **Analyze page**.
6. Use local summary, claims, Plain English, visible risk signals, and source comparison.
7. Use the star/Library controls for bookmarks and local history. Downloads ask where to save and appear in the bottom shelf.
8. Click the provider name inside the address bar, or open **ClearframeBrowser → Settings…** (`⌘,`), to choose the search engine. After a toolbar choice, the address field is ready for typing.
9. Optional AI, tab-restoration, and local-history settings are available in the same Settings window.

DuckDuckGo is the initial search default, not Clearframe’s browser engine. Searches can instead use Google, Bing, Brave Search, or Startpage. The choice stays in local macOS preferences, direct website addresses bypass search, and Clearframe claims no partnership or revenue agreement with any listed provider.

The AI guide is editorial information stored inside the app, not a live ranking or recommendation feed. A card opens its listed official website as ordinary navigation. Clearframe does not append page text or a prompt, track the click, receive affiliate payment, or claim a partnership. Each provider controls its own availability, accounts, plans, data practices, and terms.

## Verify the native code

```bash
cd macos/ClearframeBrowser
swift test
./scripts/run-browser-smoke.sh
```

The smoke test exercises a native SwiftUI window, launch/address focus, deterministic WebKit navigation, tabs, local search resolution, bookmarks/history, session restore, and the local assistant. It requires a logged-in desktop session; restricted/headless environments can block WebKit services.

The Swift package separates the Foundation-only analysis/service contract (`ClearframeCore`) from the macOS-specific SwiftUI/WebKit interface (`ClearframeBrowser`). A future Windows app can reuse the language-neutral service contract and tests, but not the native SwiftUI/WebKit UI.

## Earlier extension validation artifact

The project root is also a local-first Manifest V3 side-panel extension. To run that artifact:

1. Open `chrome://extensions` in Chrome, Brave, Edge, or another Chromium browser.
2. Turn on **Developer mode**.
3. Click **Load unpacked** and choose this project folder.
4. Pin **Clearframe** to the toolbar.
5. Open an article, guide, or product page and click the Clearframe toolbar icon.
6. Click **Analyze this page** in the side panel.

The extension uses the temporary `activeTab` permission. When you navigate to a different site, click its toolbar icon again before analyzing the new page.

## Optional AI in either prototype

The local summary is the default. The native app stores a user-owned prototype key in macOS Keychain; the extension stores it in local extension storage. Both send page text only after an explicit AI action and request `store: false`.

A production version must put paid API access behind an authenticated backend proxy and must never ship a shared key in an app or extension.

Extension checks still run from the project root:

Requires a recent Node.js version:

```bash
npm test
npm run validate
```

## Important limits

- A local summary selects representative sentences; it is not a fact check.
- AI output can omit context or be wrong.
- Risk signals are heuristic and do not prove that a page is safe or malicious.
- Clearframe can save downloads but does not scan their contents or provide a reputation verdict. It also does not inspect certificate details, network traffic, reputation databases, or hidden page behavior.
- Browser-internal pages, extension stores, PDF viewers, and some restricted pages cannot be analyzed.
- The native browser is a single-window version-1 MVP with basic tabs; it is not yet a signed, notarized, independently security-reviewed consumer release.
- WebKit does not provide Chrome extension compatibility and is not a drop-in substitute for a future Chromium product.

## Documentation index

- [Clearframe strategy, vision, non-goals, and roadmap](docs/clearframe-strategy.md)
- [Durable project context](docs/project-context.md)
- [Product and technical foundation](docs/product-foundation.md)
- [Native macOS architecture and limits](docs/macos-browser-foundation.md)
- [Chromium/CEF migration foundation](docs/chromium-migration.md)
- [Privacy and safety notes](docs/privacy-and-safety.md)
- [2026 market research](docs/market-research.md)
- [Cross-platform page-intelligence contract](docs/page-intelligence-contract.md)
- [Voice-first product and technical direction](docs/voice-first-spec.md)
- [Programmer browser side concept](docs/programmer-browser-concept.md)
- [Agent development instructions](AGENTS.md)
- [Claude-compatible repository guidance](CLAUDE.md)
