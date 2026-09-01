# Limeghost browser prototype

A browser by [Zincoo](https://zincoo.com/).

Named for the barn owl. *Tyto alba* is called the **ghost owl** — the pale heart-shaped face, the silent flight, the way it appears white out of the dark — and lime is the accent the interface is drawn in. The project was called Clearframe until August 31, 2026; [why it changed](docs/brand/naming-decision-2026-08-31.md) is on the record, along with what was checked.

Limeghost is a **standalone macOS browser foundation** built with SwiftUI and WebKit. It opens its own native window, navigates the web, and can hand any page's readable text to the AI you already use. The earlier Chromium extension remains in the repository as a useful validation artifact; it is not the final browser.

The installed and `dist` builds still use WebKit. A future Chromium migration now has an isolated [CEF migration plan](docs/chromium-migration.md) and validation scaffold under `chromium/cef-spike`; that scaffold is not linked into the current app and must not be described as a working Chromium build.

The native app provides:

- a single-row dark browser chrome with inline traffic lights in the tab strip, one unified toolbar and address pill, and per-site icons: a site's real icon is captured only while you visit it, from that site's own pages, and cached locally; sites you have not visited show a locally computed identity-color square, and no third-party icon service is ever contacted;
- multi-tab browsing with safe per-tab WebKit and assistant state, including ephemeral private tabs that are never restored or added to history;
- local restoration of recent regular tabs, with lazy loading, corruption recovery, and an opt-out setting;
- downloads with a user-selected destination plus an obvious toolbar panel for status, destination, cancel, reveal, and the Downloads folder;
- the page basics people expect from any browser: file uploads through the standard macOS picker (including multiple files and, where a site asks for one, a folder), find in page (`⌘F`, with `⌘G` and `⇧⌘G` to step and Escape to close), printing the open page (`⌘P`), and per-tab page zoom (`⌘+`, `⌘−`, `⌘0`);
- the tab habits people arrive with: reopen the tab you just closed (`⇧⌘T`), jump straight to a tab with `⌘1`–`⌘8` and to the last one with `⌘9`, and duplicate the page you are on. Closed tabs are remembered for the current run only, and a private tab is never remembered at all;
- navigations upgraded to HTTPS where the host is known to support it, and an optional **Show features for web developers** switch that lets Safari's Develop menu attach the Web Inspector to a Limeghost page;
- a visible Limeghost bookmarks bar below navigation, with horizontally scrollable top-level links, nested emoji-folder menus, current-page and saved-bookmark drag filing, fixed overflow access, and a locally persisted show/hide setting;
- a full-page bookmarks home (the bar's All Bookmarks chip or ⌘⌥B) with visual folder cards, search across bookmarks and folder titles, and drill-down into subfolders, plus a separate history page (⌘Y) grouping visits by day—all local only;
- searchable local bookmarks organized into emoji-labeled nested folders, plus local history with clear/disable controls;
- explicit loading, offline, timeout, blocked-link, and general error states;
- default-on tracker blocking against a small, first-party curated list of common advertising and tracking domains, with a per-site shield toggle in the address bar, a global switch in Settings, and state-only status text—Limeghost cannot see or count what WebKit blocks;
- site information on the address bar's lock/globe chip: the site's host, a connection state read from WebKit's own secure-content answer instead of the address scheme alone (so an HTTPS page that pulled part of itself over HTTP says so rather than showing a plain lock), the same per-site tracker-blocking switch, and **Remove this site's data**;
- a **Site data** section in Settings listing every site holding data on this Mac with its own remove button, beside the existing all-at-once reset. Both surfaces name the *kinds* of data a site stored—cookies, cached files, local storage, and so on—and never a size or a cookie count, because WebKit reports neither;
- explicit on-device voice input that fills the visible address/search field for review without automatic submission;
- address-bar completion and a suggestion list, both from this Mac's own history and bookmarks: typing a few letters finishes the address you have already been to, with the added part selected so the next keystroke replaces it, and a list underneath offers matching pages by name as well as by address, with one row that searches for what you typed. Unlike Chrome's omnibox, no keystroke is sent anywhere to build that list — it offers only places already in this profile, never a guessed host, a popular-sites list, or anything fetched. Arrow keys move through it, Return opens the highlighted row, and the whole thing stays silent in private tabs;
- a visible, locally persisted search-engine chooser for DuckDuckGo, Google, Bing, Brave Search, and Startpage;
- a native new-tab AI guide with a small, locally defined catalog organized by everyday tasks;
- a concise three-step first-run introduction covering Limeghost's promise, search choice, privacy boundary, AI home, and the copy-for-AI workflow;
- **Reader and Copy for AI** (`⇧⌘R`, `⇧⌘C`) — Limeghost pulls the readable article out of a page. Reader shows you that text, on its own, with its word count and reading time: it is the extracted article and nothing else, so what you read is exactly what an AI would receive. Copy puts the same text on your clipboard to paste into whichever AI you already use. No account, no API key, nothing sent anywhere by Limeghost;
- **your AI beside the page** (`⇧⌘A`) — ChatGPT, Claude, Gemini, Le Chat or Grok in a panel on the right, signed in with your own account. It belongs to the window rather than the tab, so the conversation stays put while you read around it, and switching between two assistants returns you to where each of them was. Limeghost does not type into it or read it: you paste and ask, as you would in a tab. **Compare answers** puts two of them side by side for asking the same question twice;
- visible risk signals such as unencrypted password forms, encoded domains, urgent payment language, wallet-secret requests, and contextual remote-access requests;

## Open the standalone macOS browser

Requirements: macOS 14 or newer and Xcode/Swift 6.

The preferred local experience is the Finder-launchable development app:

1. In Finder, open this project’s `dist` folder.
2. Double-click **Limeghost.app**.
3. If macOS asks for confirmation because this local build is not Developer ID signed or notarized, right-click the app, choose **Open**, and confirm. Do not disable Gatekeeper globally.

To rebuild that app first:

```bash
cd macos/LimeghostBrowser
./scripts/build-macos-app.sh
```

The output is `dist/Limeghost.app` at the repository root. The script embeds the app icon and privacy manifest, enables the hardened runtime, and applies an ad hoc signature for local development. This is still not a Developer ID signature or notarization. The bundle opens as an ordinary macOS application rather than using Terminal as its keyboard target.

For source-level development only, you can still use:

```bash
cd macos/LimeghostBrowser
swift run LimeghostBrowser
```

If Swift’s user cache is restricted in your environment, keep the cache inside the project:

```bash
cd macos/LimeghostBrowser
mkdir -p .build/module-cache
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
swift run --disable-sandbox LimeghostBrowser
```

Then:

1. On the first launch, complete or skip the short introduction. It stores only a local completion flag and your selected search engine. Reopen it later from **Settings → General → Limeghost introduction**. Settings itself is a sidebar of nine pages — General, Search, Tabs, Privacy, Blocking, Downloads, Bookmarks, Advanced, About — where you can also set what opens at start, where the Home button goes, the text size pages open at, and whether downloads ask where to save.
2. A new tab opens Limeghost’s local AI guide. Choose a human task, search the catalog, or explicitly reveal all tools; then select a card to open that service’s official website.
3. Enter a URL or search in the address bar. Click the lock/globe chip at the left of the address pill for site information: the host, how the connection stands, this site's tracker-blocking switch, and **Remove this site's data**. The same chip still drags this page's link out to the bookmarks bar.
4. Browse with independent tabs; use `⌘T` for a new tab, `⌘⇧N` for a private tab, and `⌘W` to close the current tab. Private tabs use an ephemeral WebKit data store and are not written to history or session restoration.
5. Press **⇧⌘R**, or the page button in the toolbar's outlined pair, to open **Reader**: the page's article with the site's furniture removed, and a Copy for AI button beside it. **⇧⌘C** — or **Page → Copy Page for AI** — copies without opening Reader first. Limeghost stays quiet when it works; it speaks only when it could not find the article, or when the page is a list rather than one piece of writing.
6. Press **⇧⌘A**, or the speech-bubble button in the toolbar, to open your own AI beside the page. Pick which one from the panel header; the button beside it with two panes opens **Compare answers**, a second assistant next to the first. Both are ordinary websites on your own account — paste and send them yourself.
7. Click the lock/globe chip at the left of the address bar and choose **Check this page** to look for visible risk signals — an unencrypted password form, an encoded address, urgent payment or wallet-secret language.
8. The bookmarks bar shows Unfiled links and emoji-labeled folders. Drag the address bar’s lock/globe page-link chip—or an existing bookmark—onto bar space or a visible folder to file it; dropping the same URL moves its single record instead of duplicating it. Secondary-click and the **More** and **Page** menus expose the same create, file, organize, and show/hide actions, with an accessible Move menu for keyboard use. **⌘⌥B** and the bar’s All Bookmarks chip open the full-page bookmarks home; the toolbar’s Library button keeps a separate quick popover for fast lookups. Legacy bookmarks remain in **Unfiled**.
9. Use the Downloads toolbar button to see a clear empty state or the current session’s download status, destination, and Reveal action; **Open Downloads Folder** remains available even when the list is empty. Attachment downloads keep the existing page visible instead of presenting WebKit's internal policy-handoff message as a page error.
10. Click the provider name inside the address bar, or open **LimeghostBrowser → Settings…** (`⌘,`), to choose the search engine. After a toolbar choice, the address field is ready for typing.
11. Tab-restoration, bookmark-bar, and local-history settings are available in the same Settings window. **Site data** lists every site that has stored data on this Mac, described in kinds rather than amounts, with a remove button each. **Clear local browsing data** removes regular/private tabs, history, bookmarks, the in-app download list, cookies, caches, website storage, session records, and recovery backups; it does not delete downloaded files or general preferences.

DuckDuckGo is the initial search default, not Limeghost’s browser engine. Searches can instead use Google, Bing, Brave Search, or Startpage. The choice stays in local macOS preferences, direct website addresses bypass search, and Limeghost claims no partnership or revenue agreement with any listed provider.

The AI guide is editorial information stored inside the app, not a live recommendation feed. When a task is selected, a few cards may receive a task-specific Best Overall, Best Value, or Easiest to Start badge with a short rationale and official source. The app visibly shows the catalog version and manually checked date. These are Limeghost editorial shortcuts—not universal rankings, product testing, exact prices, automatic updates, or commercial placements. A card opens its listed official website as ordinary navigation. Limeghost does not append page text or a prompt, track the click, receive affiliate payment, or claim a partnership. Each provider controls its own availability, accounts, plans, data practices, and terms. See the [AI catalog editorial and update policy](docs/ai-catalog-editorial.md).

## Verify the native code

```bash
cd macos/LimeghostBrowser
swift test
./scripts/run-browser-smoke.sh   # the live end-to-end pass; needs a logged-in desktop session
```

Tests that need isolated storage each make their own `UserDefaults` suite.
Teardown empties the domain, but macOS writes an empty `.plist` back as the
test process exits, so a full run leaves roughly eighty files in
`~/Library/Preferences`. They are inert, and they accumulate. To clear them:

```bash
./scripts/clean-test-preferences.sh
```

It removes only files matching `limeghost.<name>.<uuid>.plist` and refuses
anything beginning `com.clearframe`, which is where the app's own settings and
each profile's bookmarks and history actually live.

The smoke test uses a kernel-selected local fixture port and exercises a native SwiftUI window, launch/content focus, WebKit navigation, same-document SPA URL/title changes, popups, tabs, local search resolution, bookmark persistence and safe drag filing, download-panel state, history, session restore, visible-content filtering, open Shadow DOM extraction, local analysis, exact evidence highlighting, the file-upload panel wiring, find in page, page zoom, and print availability. It requires a logged-in desktop session; restricted/headless environments can block WebKit services.

The Swift package separates the Foundation-only analysis/service contract (`LimeghostCore`) from the macOS-specific SwiftUI/WebKit interface (`LimeghostBrowser`). A shared JSON contract fixture is executed by both the Swift and JavaScript suites so page-structure detection, risk signals, sentence segmentation, interface-noise filtering, and reading-time behavior cannot drift silently. A future Windows app can reuse the language-neutral service contract and tests, but not the native SwiftUI/WebKit UI.

## Earlier extension validation artifact

The project root is also a local-first Manifest V3 side-panel extension. To run that artifact:

1. Open `chrome://extensions` in Chrome, Brave, Edge, or another Chromium browser.
2. Turn on **Developer mode**.
3. Click **Load unpacked** and choose this project folder.
4. Pin **Limeghost** to the toolbar.
5. Open an article, guide, or product page and click the Limeghost toolbar icon.
6. Click **Analyze this page** in the side panel.

The extension uses the temporary `activeTab` permission. When you navigate to a different site, click its toolbar icon again before analyzing the new page.

## What Reader and the copy button actually do

Both run one extraction. It takes the page's rendered reading text, keeps it in the page's own language, and removes interface noise like a video player's control labels and anything the page repeats three or more times.

**⇧⌘C** puts that text straight on your clipboard. Limeghost interrupts only for the two things a paste would not reveal — that it was unsure it found the article, or that the page lists many articles rather than being one.

**⇧⌘R** shows you the same text first. Reader is not a prettier rendering of the page: it is the extractor's output, drawn — no images, no links, no reconstructed layout — because the point is to let you see what an assistant would be given before you give it. Where the extractor was unsure it found an article, Reader says so above the text rather than after the fact. Copying from Reader copies the words on screen, not a second reading of the page.

**Limeghost makes no AI request and holds no credential for one.** There is no key to configure and nothing to enable. The only way a page reaches an AI is you copying it and pasting it somewhere yourself — which means you can see exactly what you are handing over, and to whom.

Until August 30, 2026 Limeghost also produced a summary, key points and claims to check, by ranking sentences on word frequency. That was removed: counting words cannot know what matters, and on a real encyclopedia page it ranked the site's own navigation menu second. The reasoning is recorded in [docs/project-context.md](docs/project-context.md).

Extension checks still run from the project root:

Requires a recent Node.js version:

```bash
npm test
npm run validate
```

Limeghost presents Safari's user agent because it renders with WebKit, Safari's engine. Sites that tailor pages by user agent then serve what they serve Safari, rather than the reduced page they keep for clients they cannot identify. The version is read from the Safari installed on the Mac.

## Important limits

- Limeghost does not summarise a page or judge what matters in it. It extracts text and prepares it; anything more is done by an AI you choose.
- Extraction preserves the page language, but text-based risk phrases do not have equal language coverage.
- Copying tries to notice when a page is a list of many articles rather than one piece of writing, and says so. That check currently misses news homepages whose cards carry teaser paragraphs — see the known defect in [docs/page-intelligence-contract.md](docs/page-intelligence-contract.md).
- Extraction misses things. A page whose article is not marked up as one, or that renders after first paint, can yield the wrong text or none at all.
- Risk signals are heuristic and do not prove that a page is safe or malicious.
- Tracker blocking uses a small, first-party curated list of common advertising and tracking domains—not a complete ad blocker. It does not stop first-party analytics, cookie-based tracking, browser fingerprinting, or CNAME-cloaked trackers, and WebKit never reports back which requests it blocked, so no per-page or running count exists anywhere in the UI. See [docs/content-blocking.md](docs/content-blocking.md).
- Site data controls name the kinds of data a site stored and never how much. `WKWebsiteDataRecord` carries a display name and a set of data types with no byte size and no cookie count, so no amount appears anywhere—the same reason the tracker shield shows no numbers. WebKit files a site's data under its registrable domain, so removing data for `www.example.com` removes what its other subdomains stored too, and private-tab storage is never listed because it lives in an ephemeral store discarded with the tab.
- The connection state says whether the page and everything on it arrived encrypted. It is not a statement about who runs the site: Limeghost shows no certificate details and makes no judgment about the site's identity, intent, or safety.
- Find in page reports whether the page still contains a match, not how many. WebKit's find API answers match or no match and returns no count or position, so the bar shows **No results** or shows nothing at all—never an invented "3 of 12".
- Page zoom applies to the tab it was used in. It is not remembered per site, not shared between tabs, and not restored after a relaunch.
- Limeghost can save downloads but does not scan their contents or provide a reputation verdict. It also does not inspect certificate details, network traffic, reputation databases, or hidden page behavior.
- The download list is session-only in this version; saved files remain at the destination the user selected, and the toolbar panel can always open the local Downloads folder.
- The bookmarks bar and folder organizer are local only. Native URL drag-and-drop creates or moves bookmarks into Unfiled or visible folders; it does not reorder items or move folders, and the existing Move menu remains the keyboard alternative. The organizer supports drops onto the folders currently visible in it, not closed submenu rows. There is no account, sync, or cloud backup. Hiding the bar does not delete bookmarks. Deleting a non-empty folder requires confirmation and rehomes its direct contents instead of deleting saved pages.
- Browser-internal pages, extension stores, PDF viewers, and some restricted pages cannot be analyzed.
- Private tabs isolate website storage for that tab and avoid history/restoration, but they do not provide network anonymity, hide activity from websites or the network, or erase files the user downloads.
- Passkeys do not work yet. WebKit implements them, but macOS withholds the on-device authenticator (Touch ID and iCloud Keychain passkeys) from a web view inside an app that is not Developer ID signed, so `isUserVerifyingPlatformAuthenticatorAvailable()` reports false and sites fall back to scanning a cross-device passkey over Bluetooth. Sign in with a password and second factor until the app is properly signed and the browser entitlement is in place.
- The native browser is a version-1 MVP with basic tabs; its local bundle is ad hoc signed with the hardened runtime, but it is not Developer ID signed, notarized, or independently security reviewed for consumer distribution.
- WebKit does not provide Chrome extension compatibility and is not a drop-in substitute for a future Chromium product.
- The repository is published under the [GNU Affero General Public License v3.0](LICENSE). Source may be read, modified, and redistributed under those terms; modified versions offered to users over a network must also offer their corresponding source. Limeghost holds the copyright and may additionally offer separate commercial terms.
- The folder icon picker offers three sets. The Limeghost set (104 icons) is the project's own artwork, and the only one a folder's tint reaches — it is drawn in `currentColor`, while the licensed sets carry their own colours, so the swatch row hides for them rather than showing a control that does nothing. Licensed sets are credited in the picker wherever they are shown.
  - **Stickies** (100 drawings) — ["Stickies color icons" by Streamline](https://github.com/webalys-hq/streamline-vectors), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Attribution required. The set's single-lime `duo` form is not shipped: that green sits close enough to the mint accent to read as a mismatch rather than a choice.
  - **Emoji** (1261 drawings) — [EmojiOne v1 by Emoji One](https://github.com/joypixels/emojione), [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). Attribution required, **and share-alike**: any modification of that artwork must be released under the same licence. Bundling it is a collection rather than an adaptation, and CC 4.0 states that a change of format alone never creates an adaptation, so compiling it into the app does not place the app under share-alike — but redrawing or remixing these icons would put the result under CC BY-SA 4.0. That matters if separate commercial terms are ever offered, so treat the set as read-only artwork.
  Redistributing this repository carries these attribution requirements with it.
- Icon sets under the GPL are deliberately not shipped. One was added and withdrawn: GPL copyleft covers the whole program rather than only adaptations of the artwork, so a GPL set would have to be removed or separately licensed before Limeghost could be offered under closed commercial terms. Iconify summarises such licences as "commercial use is allowed", which is true and easy to misread — GPL software may be sold, but it must still be conveyed under the GPL. Prefer CC BY for anything new.

## Brand

The mark is in [`docs/brand/limeghost-mark-2026-08-31/`](docs/brand/limeghost-mark-2026-08-31/) in three forms, and they are not interchangeable:

| File | Where it belongs |
|---|---|
| `limeghost-mark-full.png` | App icon, Dock, website, App Store — anywhere 32 px or larger |
| `limeghost-mark-small.png` | The 16 px favicon and the menu bar. The owl's face alone |
| `limeghost-mark-mono.png` | One-colour contexts: print, watermarks, a stamp |

`scripts/generate-app-icon.swift` reads the first two and switches between them by size: above 32 px the whole mark, at 16 and 32 the face alone, because the ring turns to mud at that size and takes the face with it. The accent is `#66DB7D`, and the gradient never approaches black or white — an earlier version faded to near-black and lost the owl's body against the app's own dark chrome.

## Documentation index

- [Limeghost strategy, vision, non-goals, and roadmap](docs/limeghost-strategy.md)
- [Durable project context](docs/project-context.md)
- [Why the browser is called Limeghost](docs/brand/naming-decision-2026-08-31.md) — the evidence, and the names that were rejected
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
