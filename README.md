# Clearframe browser prototype

A browser by [Zincoo](https://zincoo.com/).

Clearframe is now a **standalone macOS browser foundation** built with SwiftUI and WebKit. It opens its own native window, navigates the web, and can hand any page's readable text to the AI you already use. The earlier Chromium extension remains in the repository as a useful validation artifact; it is not the final browser.

The installed and `dist` builds still use WebKit. A future Chromium migration now has an isolated [CEF migration plan](docs/chromium-migration.md) and validation scaffold under `chromium/cef-spike`; that scaffold is not linked into the current app and must not be described as a working Chromium build.

The native app provides:

- a single-row dark browser chrome with inline traffic lights in the tab strip, one unified toolbar and address pill, and per-site icons: a site's real icon is captured only while you visit it, from that site's own pages, and cached locally; sites you have not visited show a locally computed identity-color square, and no third-party icon service is ever contacted;
- multi-tab browsing with safe per-tab WebKit and assistant state, including ephemeral private tabs that are never restored or added to history;
- local restoration of recent regular tabs, with lazy loading, corruption recovery, and an opt-out setting;
- downloads with a user-selected destination plus an obvious toolbar panel for status, destination, cancel, reveal, and the Downloads folder;
- the page basics people expect from any browser: file uploads through the standard macOS picker (including multiple files and, where a site asks for one, a folder), find in page (`⌘F`, with `⌘G` and `⇧⌘G` to step and Escape to close), printing the open page (`⌘P`), and per-tab page zoom (`⌘+`, `⌘−`, `⌘0`);
- the tab habits people arrive with: reopen the tab you just closed (`⇧⌘T`), jump straight to a tab with `⌘1`–`⌘8` and to the last one with `⌘9`, and duplicate the page you are on. Closed tabs are remembered for the current run only, and a private tab is never remembered at all;
- navigations upgraded to HTTPS where the host is known to support it, and an optional **Show features for web developers** switch that lets Safari's Develop menu attach the Web Inspector to a Clearframe page;
- a visible Clearframe bookmarks bar below navigation, with horizontally scrollable top-level links, nested emoji-folder menus, current-page and saved-bookmark drag filing, fixed overflow access, and a locally persisted show/hide setting;
- a full-page bookmarks home (the bar's All Bookmarks chip or ⌘⌥B) with visual folder cards, search across bookmarks and folder titles, and drill-down into subfolders, plus a separate history page (⌘Y) grouping visits by day—all local only;
- searchable local bookmarks organized into emoji-labeled nested folders, plus local history with clear/disable controls;
- explicit loading, offline, timeout, blocked-link, and general error states;
- default-on tracker blocking against a small, first-party curated list of common advertising and tracking domains, with a per-site shield toggle in the address bar, a global switch in Settings, and state-only status text—Clearframe cannot see or count what WebKit blocks;
- site information on the address bar's lock/globe chip: the site's host, a connection state read from WebKit's own secure-content answer instead of the address scheme alone (so an HTTPS page that pulled part of itself over HTTP says so rather than showing a plain lock), the same per-site tracker-blocking switch, and **Remove this site's data**;
- a **Site data** section in Settings listing every site holding data on this Mac with its own remove button, beside the existing all-at-once reset. Both surfaces name the *kinds* of data a site stored—cookies, cached files, local storage, and so on—and never a size or a cookie count, because WebKit reports neither;
- explicit on-device voice input that fills the visible address/search field for review without automatic submission;
- address-bar completion and a suggestion list, both from this Mac's own history and bookmarks: typing a few letters finishes the address you have already been to, with the added part selected so the next keystroke replaces it, and a list underneath offers matching pages by name as well as by address, with one row that searches for what you typed. Unlike Chrome's omnibox, no keystroke is sent anywhere to build that list — it offers only places already in this profile, never a guessed host, a popular-sites list, or anything fetched. Arrow keys move through it, Return opens the highlighted row, and the whole thing stays silent in private tabs;
- a visible, locally persisted search-engine chooser for DuckDuckGo, Google, Bing, Brave Search, and Startpage;
- a native new-tab AI guide with a small, locally defined catalog organized by everyday tasks;
- a concise three-step first-run introduction covering Clearframe's promise, search choice, privacy boundary, AI home, and the copy-for-AI workflow;
- **Copy for AI** — Clearframe pulls the readable article out of a page, shows you the exact text and its size, and copies it for you to paste into whichever AI you already use. No account, no API key, nothing sent anywhere by Clearframe;
- **your AI beside the page** (`⇧⌘A`) — ChatGPT, Claude, Gemini, Le Chat or Grok in a panel on the right, signed in with your own account. It belongs to the window rather than the tab, so the conversation stays put while you read around it, and switching between two assistants returns you to where each of them was. Clearframe does not type into it or read it: you paste and ask, as you would in a tab. **Compare answers** puts two of them side by side for asking the same question twice;
- visible risk signals such as unencrypted password forms, encoded domains, urgent payment language, wallet-secret requests, and contextual remote-access requests;

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

> **Missing, as of August 30, 2026.** `scripts/build-macos-app.sh` and `scripts/run-browser-smoke.sh` are referenced throughout this repository and by `.github/workflows/ci.yml`, but neither file exists in any commit. The macOS CI job therefore cannot pass, and `Tests/BrowserE2ESmoke.swift` — which is not a member of any target in `Package.swift` — has no runner. `swift test`, `npm test` and `npm run validate` all work.

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
3. Enter a URL or search in the address bar. Click the lock/globe chip at the left of the address pill for site information: the host, how the connection stands, this site's tracker-blocking switch, and **Remove this site's data**. The same chip still drags this page's link out to the bookmarks bar.
4. Browse with independent tabs; use `⌘T` for a new tab, `⌘⇧N` for a private tab, and `⌘W` to close the current tab. Private tabs use an ephemeral WebKit data store and are not written to history or session restoration.
5. Press **⇧⌘C**, or the copy button at the right of the toolbar, to put the page's readable text on your clipboard for whichever AI you use. Clearframe stays quiet when it works; it speaks only when it could not find the article, or when the page is a list rather than one piece of writing.
6. Press **⇧⌘A**, or the speech-bubble button in the toolbar, to open your own AI beside the page. Pick which one from the panel header; the button beside it with two panes opens **Compare answers**, a second assistant next to the first. Both are ordinary websites on your own account — paste and send them yourself.
7. Click the lock/globe chip at the left of the address bar and choose **Check this page** to look for visible risk signals — an unencrypted password form, an encoded address, urgent payment or wallet-secret language.
8. The bookmarks bar shows Unfiled links and emoji-labeled folders. Drag the address bar’s lock/globe page-link chip—or an existing bookmark—onto bar space or a visible folder to file it; dropping the same URL moves its single record instead of duplicating it. Secondary-click and the **More** and **Page** menus expose the same create, file, organize, and show/hide actions, with an accessible Move menu for keyboard use. **⌘⌥B** and the bar’s All Bookmarks chip open the full-page bookmarks home; the toolbar’s Library button keeps a separate quick popover for fast lookups. Legacy bookmarks remain in **Unfiled**.
9. Use the Downloads toolbar button to see a clear empty state or the current session’s download status, destination, and Reveal action; **Open Downloads Folder** remains available even when the list is empty. Attachment downloads keep the existing page visible instead of presenting WebKit's internal policy-handoff message as a page error.
10. Click the provider name inside the address bar, or open **ClearframeBrowser → Settings…** (`⌘,`), to choose the search engine. After a toolbar choice, the address field is ready for typing.
11. Tab-restoration, bookmark-bar, and local-history settings are available in the same Settings window. **Site data** lists every site that has stored data on this Mac, described in kinds rather than amounts, with a remove button each. **Clear local browsing data** removes regular/private tabs, history, bookmarks, the in-app download list, cookies, caches, website storage, session records, and recovery backups; it does not delete downloaded files or general preferences.

DuckDuckGo is the initial search default, not Clearframe’s browser engine. Searches can instead use Google, Bing, Brave Search, or Startpage. The choice stays in local macOS preferences, direct website addresses bypass search, and Clearframe claims no partnership or revenue agreement with any listed provider.

The AI guide is editorial information stored inside the app, not a live recommendation feed. When a task is selected, a few cards may receive a task-specific Best Overall, Best Value, or Easiest to Start badge with a short rationale and official source. The app visibly shows the catalog version and manually checked date. These are Clearframe editorial shortcuts—not universal rankings, product testing, exact prices, automatic updates, or commercial placements. A card opens its listed official website as ordinary navigation. Clearframe does not append page text or a prompt, track the click, receive affiliate payment, or claim a partnership. Each provider controls its own availability, accounts, plans, data practices, and terms. See the [AI catalog editorial and update policy](docs/ai-catalog-editorial.md).

## Verify the native code

```bash
cd macos/ClearframeBrowser
swift test
./scripts/run-browser-smoke.sh   # see the note above: this file is missing
```

Tests that need isolated storage each make their own `UserDefaults` suite.
Teardown empties the domain, but macOS writes an empty `.plist` back as the
test process exits, so a full run leaves roughly eighty files in
`~/Library/Preferences`. They are inert, and they accumulate. To clear them:

```bash
./scripts/clean-test-preferences.sh
```

It removes only files matching `clearframe.<name>.<uuid>.plist` and refuses
anything beginning `com.clearframe`, which is where the app's own settings and
each profile's bookmarks and history actually live.

The smoke test uses a kernel-selected local fixture port and exercises a native SwiftUI window, launch/content focus, WebKit navigation, same-document SPA URL/title changes, popups, tabs, local search resolution, bookmark persistence and safe drag filing, download-panel state, history, session restore, visible-content filtering, open Shadow DOM extraction, local analysis, exact evidence highlighting, the file-upload panel wiring, find in page, page zoom, and print availability. It requires a logged-in desktop session; restricted/headless environments can block WebKit services.

The Swift package separates the Foundation-only analysis/service contract (`ClearframeCore`) from the macOS-specific SwiftUI/WebKit interface (`ClearframeBrowser`). A shared JSON contract fixture is executed by both the Swift and JavaScript suites so page-structure detection, risk signals, sentence segmentation, interface-noise filtering, and reading-time behavior cannot drift silently. A future Windows app can reuse the language-neutral service contract and tests, but not the native SwiftUI/WebKit UI.

## Earlier extension validation artifact

The project root is also a local-first Manifest V3 side-panel extension. To run that artifact:

1. Open `chrome://extensions` in Chrome, Brave, Edge, or another Chromium browser.
2. Turn on **Developer mode**.
3. Click **Load unpacked** and choose this project folder.
4. Pin **Clearframe** to the toolbar.
5. Open an article, guide, or product page and click the Clearframe toolbar icon.
6. Click **Analyze this page** in the side panel.

The extension uses the temporary `activeTab` permission. When you navigate to a different site, click its toolbar icon again before analyzing the new page.

## What the copy button actually does

One keystroke — **⇧⌘C** — extracts the page's rendered reading text, keeps it in the page's own language, removes interface noise like a video player's control labels and anything the page repeats three or more times, and puts the result on your clipboard. There is no panel and nothing to read: the text appears in front of you when you paste it. Clearframe interrupts only for the two things a paste would not reveal — that it was unsure it found the article, or that the page lists many articles rather than being one.

**Clearframe makes no AI request and holds no credential for one.** There is no key to configure and nothing to enable. The only way a page reaches an AI is you copying it and pasting it somewhere yourself — which means you can see exactly what you are handing over, and to whom.

Until August 30, 2026 Clearframe also produced a summary, key points and claims to check, by ranking sentences on word frequency. That was removed: counting words cannot know what matters, and on a real encyclopedia page it ranked the site's own navigation menu second. The reasoning is recorded in [docs/project-context.md](docs/project-context.md).

Extension checks still run from the project root:

Requires a recent Node.js version:

```bash
npm test
npm run validate
```

Clearframe presents Safari's user agent because it renders with WebKit, Safari's engine. Sites that tailor pages by user agent then serve what they serve Safari, rather than the reduced page they keep for clients they cannot identify. The version is read from the Safari installed on the Mac.

## Important limits

- Clearframe does not summarise a page or judge what matters in it. It extracts text and prepares it; anything more is done by an AI you choose.
- Extraction preserves the page language, but text-based risk phrases do not have equal language coverage.
- Copying tries to notice when a page is a list of many articles rather than one piece of writing, and says so. That check currently misses news homepages whose cards carry teaser paragraphs — see the known defect in [docs/page-intelligence-contract.md](docs/page-intelligence-contract.md).
- Extraction misses things. A page whose article is not marked up as one, or that renders after first paint, can yield the wrong text or none at all.
- Risk signals are heuristic and do not prove that a page is safe or malicious.
- Tracker blocking uses a small, first-party curated list of common advertising and tracking domains—not a complete ad blocker. It does not stop first-party analytics, cookie-based tracking, browser fingerprinting, or CNAME-cloaked trackers, and WebKit never reports back which requests it blocked, so no per-page or running count exists anywhere in the UI. See [docs/content-blocking.md](docs/content-blocking.md).
- Site data controls name the kinds of data a site stored and never how much. `WKWebsiteDataRecord` carries a display name and a set of data types with no byte size and no cookie count, so no amount appears anywhere—the same reason the tracker shield shows no numbers. WebKit files a site's data under its registrable domain, so removing data for `www.example.com` removes what its other subdomains stored too, and private-tab storage is never listed because it lives in an ephemeral store discarded with the tab.
- The connection state says whether the page and everything on it arrived encrypted. It is not a statement about who runs the site: Clearframe shows no certificate details and makes no judgment about the site's identity, intent, or safety.
- Find in page reports whether the page still contains a match, not how many. WebKit's find API answers match or no match and returns no count or position, so the bar shows **No results** or shows nothing at all—never an invented "3 of 12".
- Page zoom applies to the tab it was used in. It is not remembered per site, not shared between tabs, and not restored after a relaunch.
- Clearframe can save downloads but does not scan their contents or provide a reputation verdict. It also does not inspect certificate details, network traffic, reputation databases, or hidden page behavior.
- The download list is session-only in this version; saved files remain at the destination the user selected, and the toolbar panel can always open the local Downloads folder.
- The bookmarks bar and folder organizer are local only. Native URL drag-and-drop creates or moves bookmarks into Unfiled or visible folders; it does not reorder items or move folders, and the existing Move menu remains the keyboard alternative. The organizer supports drops onto the folders currently visible in it, not closed submenu rows. There is no account, sync, or cloud backup. Hiding the bar does not delete bookmarks. Deleting a non-empty folder requires confirmation and rehomes its direct contents instead of deleting saved pages.
- Browser-internal pages, extension stores, PDF viewers, and some restricted pages cannot be analyzed.
- Private tabs isolate website storage for that tab and avoid history/restoration, but they do not provide network anonymity, hide activity from websites or the network, or erase files the user downloads.
- Passkeys do not work yet. WebKit implements them, but macOS withholds the on-device authenticator (Touch ID and iCloud Keychain passkeys) from a web view inside an app that is not Developer ID signed, so `isUserVerifyingPlatformAuthenticatorAvailable()` reports false and sites fall back to scanning a cross-device passkey over Bluetooth. Sign in with a password and second factor until the app is properly signed and the browser entitlement is in place.
- The native browser is a version-1 MVP with basic tabs; its local bundle is ad hoc signed with the hardened runtime, but it is not Developer ID signed, notarized, or independently security reviewed for consumer distribution.
- WebKit does not provide Chrome extension compatibility and is not a drop-in substitute for a future Chromium product.
- The repository is published under the [GNU Affero General Public License v3.0](LICENSE). Source may be read, modified, and redistributed under those terms; modified versions offered to users over a network must also offer their corresponding source. Clearframe holds the copyright and may additionally offer separate commercial terms.
- The folder icon picker offers three sets. The Clearframe set (104 icons) is the project's own artwork, and the only one a folder's tint reaches — it is drawn in `currentColor`, while the licensed sets carry their own colours, so the swatch row hides for them rather than showing a control that does nothing. Licensed sets are credited in the picker wherever they are shown.
  - **Stickies** (100 drawings) — ["Stickies color icons" by Streamline](https://github.com/webalys-hq/streamline-vectors), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Attribution required. The set's single-lime `duo` form is not shipped: that green sits close enough to the mint accent to read as a mismatch rather than a choice.
  - **Emoji** (1261 drawings) — [EmojiOne v1 by Emoji One](https://github.com/joypixels/emojione), [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). Attribution required, **and share-alike**: any modification of that artwork must be released under the same licence. Bundling it is a collection rather than an adaptation, and CC 4.0 states that a change of format alone never creates an adaptation, so compiling it into the app does not place the app under share-alike — but redrawing or remixing these icons would put the result under CC BY-SA 4.0. That matters if separate commercial terms are ever offered, so treat the set as read-only artwork.
  Redistributing this repository carries these attribution requirements with it.
- Icon sets under the GPL are deliberately not shipped. One was added and withdrawn: GPL copyleft covers the whole program rather than only adaptations of the artwork, so a GPL set would have to be removed or separately licensed before Clearframe could be offered under closed commercial terms. Iconify summarises such licences as "commercial use is allowed", which is true and easy to misread — GPL software may be sold, but it must still be conveyed under the GPL. Prefer CC BY for anything new.

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
- [Browser feature research and gap analysis](docs/browser-feature-research.md)
- [Intellectual property and ownership](docs/ip-and-ownership.md)
- [Data inventory](docs/data-inventory.md)
- [Changelog](CHANGELOG.md)
- [Cross-platform page-intelligence contract](docs/page-intelligence-contract.md)
- [Voice-first product and technical direction](docs/voice-first-spec.md)
- [Programmer browser side concept](docs/programmer-browser-concept.md)
- [Agent development instructions](AGENTS.md)
- [Claude-compatible repository guidance](CLAUDE.md)
