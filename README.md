# Clearframe browser prototype

A browser by [Zincoo](https://zincoo.com/).

Clearframe is now a **standalone macOS browser foundation** built with SwiftUI and WebKit. It opens its own native window, navigates the web, and includes a source-aware page assistant. The earlier Chromium extension remains in the repository as a useful validation artifact; it is not the final browser.

The installed and `dist` builds still use WebKit. A future Chromium migration now has an isolated [CEF migration plan](docs/chromium-migration.md) and validation scaffold under `chromium/cef-spike`; that scaffold is not linked into the current app and must not be described as a working Chromium build.

The native app provides:

- a single-row dark browser chrome with inline traffic lights in the tab strip, one unified toolbar and address pill, and per-site icons: a site's real icon is captured only while you visit it, from that site's own pages, and cached locally; sites you have not visited show a locally computed identity-color square, and no third-party icon service is ever contacted;
- multi-tab browsing with safe per-tab WebKit and assistant state, including ephemeral private tabs that are never restored or added to history;
- local restoration of recent regular tabs, with lazy loading, corruption recovery, and an opt-out setting;
- downloads with a user-selected destination plus an obvious toolbar panel for status, destination, cancel, reveal, and the Downloads folder;
- a visible Clearframe bookmarks bar below navigation, with horizontally scrollable top-level links, nested emoji-folder menus, current-page and saved-bookmark drag filing, fixed overflow access, and a locally persisted show/hide setting;
- a full-page bookmarks home (the bar's All Bookmarks chip or ⌘⌥B) with visual folder cards, search across bookmarks and folder titles, drill-down into subfolders, and a local history view—all local only;
- searchable local bookmarks organized into emoji-labeled nested folders, plus local history with clear/disable controls;
- explicit loading, offline, timeout, blocked-link, and general error states;
- default-on tracker blocking against a small, first-party curated list of common advertising and tracking domains, with a per-site shield toggle in the address bar, a global switch in Settings, and state-only status text—Clearframe cannot see or count what WebKit blocks;
- explicit on-device voice input that fills the visible address/search field for review without automatic submission;
- a visible, locally persisted search-engine chooser for DuckDuckGo, Google, Bing, Brave Search, and Startpage;
- a native new-tab AI guide with a small, locally defined catalog organized by everyday tasks;
- a concise three-step first-run introduction covering Clearframe's promise, search choice, privacy boundary, AI home, and Analyze page workflow;
- a source-language extractive page summary that works without an account or API key;
- key points and page claims worth checking, with best-effort highlighting of the exact extracted evidence on the live page;
- visible risk signals such as unencrypted password forms, encoded domains, urgent payment language, wallet-secret requests, and contextual remote-access requests;
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

The output is `dist/Clearframe.app` at the repository root. The script embeds the app icon and privacy manifest, enables the hardened runtime, and applies an ad hoc signature for local development. This is still not a Developer ID signature or notarization. The bundle opens as an ordinary macOS application rather than using Terminal as its keyboard target.

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
2. A new tab opens Clearframe’s local AI guide. Choose a human task, search the catalog, or explicitly reveal all tools; then select a card to open that service’s official website.
3. Enter a URL or search in the address bar.
4. Browse with independent tabs; use `⌘T` for a new tab, `⌘⇧N` for a private tab, and `⌘W` to close the current tab. Private tabs use an ephemeral WebKit data store and are not written to history or session restoration.
5. Open **Assistant** and click **Analyze page**.
6. Use local summary, claims, Plain English, visible risk signals, source comparison, and **View evidence** to reveal the extracted source sentence in the page when its DOM still matches.
7. The bookmarks bar shows Unfiled links and emoji-labeled folders. Drag the address bar’s lock/globe page-link chip—or an existing bookmark—onto bar space or a visible folder to file it; dropping the same URL moves its single record instead of duplicating it. Secondary-click and the **More** and **Page** menus expose the same create, file, organize, and show/hide actions, with an accessible Move menu for keyboard use. **⌘⌥B** and the bar’s All Bookmarks chip open the full-page bookmarks home; the toolbar’s Library button keeps a separate quick popover for fast lookups. Legacy bookmarks remain in **Unfiled**.
8. Use the Downloads toolbar button to see a clear empty state or the current session’s download status, destination, and Reveal action; **Open Downloads Folder** remains available even when the list is empty. Attachment downloads keep the existing page visible instead of presenting WebKit's internal policy-handoff message as a page error.
9. Click the provider name inside the address bar, or open **ClearframeBrowser → Settings…** (`⌘,`), to choose the search engine. After a toolbar choice, the address field is ready for typing.
10. Optional AI, tab-restoration, bookmark-bar, and local-history settings are available in the same Settings window. **Clear local browsing data** removes regular/private tabs, history, bookmarks, the in-app download list, cookies, caches, website storage, session records, and recovery backups; it does not delete downloaded files, general preferences, or the Optional AI key.

DuckDuckGo is the initial search default, not Clearframe’s browser engine. Searches can instead use Google, Bing, Brave Search, or Startpage. The choice stays in local macOS preferences, direct website addresses bypass search, and Clearframe claims no partnership or revenue agreement with any listed provider.

The AI guide is editorial information stored inside the app, not a live recommendation feed. When a task is selected, a few cards may receive a task-specific Best Overall, Best Value, or Easiest to Start badge with a short rationale and official source. The app visibly shows the catalog version and manually checked date. These are Clearframe editorial shortcuts—not universal rankings, product testing, exact prices, automatic updates, or commercial placements. A card opens its listed official website as ordinary navigation. Clearframe does not append page text or a prompt, track the click, receive affiliate payment, or claim a partnership. Each provider controls its own availability, accounts, plans, data practices, and terms. See the [AI catalog editorial and update policy](docs/ai-catalog-editorial.md).

## Verify the native code

```bash
cd macos/ClearframeBrowser
swift test
./scripts/run-browser-smoke.sh
```

The smoke test uses a kernel-selected local fixture port and exercises a native SwiftUI window, launch/content focus, WebKit navigation, same-document SPA URL/title changes, popups, tabs, local search resolution, bookmark persistence and safe drag filing, download-panel state, history, session restore, visible-content filtering, open Shadow DOM extraction, local analysis, and exact evidence highlighting. It requires a logged-in desktop session; restricted/headless environments can block WebKit services.

The Swift package separates the Foundation-only analysis/service contract (`ClearframeCore`) from the macOS-specific SwiftUI/WebKit interface (`ClearframeBrowser`). A shared JSON contract fixture is executed by both the Swift and JavaScript suites so language scoring, summaries, risk signals, Plain English, and reading-time behavior cannot drift silently. A future Windows app can reuse the language-neutral service contract and tests, but not the native SwiftUI/WebKit UI.

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

The local summary is the default. It privately selects and structures source-language sentences; deterministic coverage currently includes English, Romanian, French, and Simplified Chinese. Scoring selects stopwords from the page’s primary language tag so French or Romanian words do not suppress English topic terms. This is useful extraction, not proof of equal semantic quality in every language. A configured optional provider may produce deeper multilingual summarization or translation after an explicit AI action. For analysis, the request contains the page title, hostname, declared language, and up to 18,000 characters of extracted visible text; it omits the full URL, query, fragment, cookies, form values, and browsing history. Translation sends only the displayed summary and source/target language names. The native app stores a user-owned prototype key in macOS Keychain; the extension stores it in local extension storage. Both use structured Responses API output for analysis, request `store: false`, retain the local result if a provider request fails, and direct unavailable-model errors to Settings.

A production version must put paid API access behind an authenticated backend proxy and must never ship a shared key in an app or extension.

Extension checks still run from the project root:

Requires a recent Node.js version:

```bash
npm test
npm run validate
```

Clearframe presents Safari's user agent because it renders with WebKit, Safari's engine. Sites that tailor pages by user agent then serve what they serve Safari, rather than the reduced page they keep for clients they cannot identify. The version is read from the Safari installed on the Mac.

## Important limits

- A local summary selects representative sentences; it is not a fact check.
- Local multilingual analysis preserves the page language but is extractive. Plain English rewriting is local only for English sources, and text-based risk phrases do not have equal language coverage.
- Analyze page detects section and listing pages with many unrelated headlines and offers Analyze anyway instead of silently summarizing them as one article; this structure check is calibrated for the tested languages (see [docs/page-intelligence-contract.md](docs/page-intelligence-contract.md)).
- AI output can omit context or be wrong.
- Risk signals are heuristic and do not prove that a page is safe or malicious.
- Tracker blocking uses a small, first-party curated list of common advertising and tracking domains—not a complete ad blocker. It does not stop first-party analytics, cookie-based tracking, browser fingerprinting, or CNAME-cloaked trackers, and WebKit never reports back which requests it blocked, so no per-page or running count exists anywhere in the UI. See [docs/content-blocking.md](docs/content-blocking.md).
- Clearframe can save downloads but does not scan their contents or provide a reputation verdict. It also does not inspect certificate details, network traffic, reputation databases, or hidden page behavior.
- The download list is session-only in this version; saved files remain at the destination the user selected, and the toolbar panel can always open the local Downloads folder.
- The bookmarks bar and folder organizer are local only. Native URL drag-and-drop creates or moves bookmarks into Unfiled or visible folders; it does not reorder items or move folders, and the existing Move menu remains the keyboard alternative. The organizer supports drops onto the folders currently visible in it, not closed submenu rows. There is no account, sync, or cloud backup. Hiding the bar does not delete bookmarks. Deleting a non-empty folder requires confirmation and rehomes its direct contents instead of deleting saved pages.
- Browser-internal pages, extension stores, PDF viewers, and some restricted pages cannot be analyzed.
- Private tabs isolate website storage for that tab and avoid history/restoration, but they do not provide network anonymity, hide activity from websites or the network, or erase files the user downloads.
- The native browser is a single-window version-1 MVP with basic tabs; its local bundle is ad hoc signed with the hardened runtime, but it is not Developer ID signed, notarized, or independently security reviewed for consumer distribution.
- WebKit does not provide Chrome extension compatibility and is not a drop-in substitute for a future Chromium product.
- The repository is published under the [GNU Affero General Public License v3.0](LICENSE). Source may be read, modified, and redistributed under those terms; modified versions offered to users over a network must also offer their corresponding source. Clearframe holds the copyright and may additionally offer separate commercial terms.

## Documentation index

- [Clearframe strategy, vision, non-goals, and roadmap](docs/clearframe-strategy.md)
- [Durable project context](docs/project-context.md)
- [AI catalog editorial and update policy](docs/ai-catalog-editorial.md)
- [Focused zero-budget go-to-market plan](docs/go-to-market.md)
- [Product and technical foundation](docs/product-foundation.md)
- [Native macOS architecture and limits](docs/macos-browser-foundation.md)
- [Chromium/CEF migration foundation](docs/chromium-migration.md)
- [Tracker blocking](docs/content-blocking.md)
- [Privacy and safety notes](docs/privacy-and-safety.md)
- [2026 market research](docs/market-research.md)
- [Cross-platform page-intelligence contract](docs/page-intelligence-contract.md)
- [Voice-first product and technical direction](docs/voice-first-spec.md)
- [Programmer browser side concept](docs/programmer-browser-concept.md)
- [Agent development instructions](AGENTS.md)
- [Claude-compatible repository guidance](CLAUDE.md)
