# Changelog

Limeghost's development record, assembled from the repository's own history.

The project has not made a public release. There are no version tags, and the app bundle carries `0.1.0` as a development placeholder. Everything below is pre-release work on `main`, grouped by the week it landed. Once a first release ships, this file should switch to versioned sections following [Keep a Changelog](https://keepachangelog.com/) and [semantic versioning](https://semver.org/).

Dates are commit dates. Test counts are the totals at the end of each period, verified by running the suites.

---

## Unreleased

### Week of August 30, 2026

**Analyze page stopped claiming to understand a page**

- The gist, the key points and the claims to check are gone, and so is the term-frequency scorer that chose them. It ranked a sentence by how many of the page's most repeated words it contained, divided by its length. That is lexical centrality, not importance, and on a live Britannica article the site's own navigation menu scored second — it contains the words *intelligence*, *artificial* and *technology*, and the scorer has no concept of a menu.
- The gist was a category error rather than a bug. It was three separately-chosen sentences joined by a space, with nothing checking that the second followed from the first, so it opened with dangling references — "These advances in software and operating systems were matched by…" — and on a news homepage welded a headline onto a paragraph with no punctuation between them. Three independent reviews reached the same conclusion: a summary has to be written, and choosing three existing sentences never produces one.
- Plain English went too. It swapped thirteen fixed phrases and worked only on English — find-and-replace wearing the name of simplification.
- **Analyze page now shows the source, the read time, any visible risk signals, and Copy for AI.** Copy shows the character count and the complete payload before it copies anything, and says plainly that the Mac's clipboard is shared with other apps and with Universal Clipboard. Limeghost prepares the text; the person decides where it goes.
- The two filters that keep video-player controls and thrice-repeated interface text out of the reader's way moved out of the summarizer into that copied text, so a paste into somebody's AI no longer begins "Video Player is loading. Stream Type LIVE. Playback controls." Their three contract suites now test the filter directly instead of through a summarizer, which is stronger coverage than before.

**And the AI it never really had**

- The optional OpenAI provider is removed, with the Keychain key storage, the Optional AI settings, the model contract fixture and the extension's options page — which existed for nothing but that key. The extension no longer requests permission to reach `api.openai.com`, because it no longer reaches it. **No page text leaves the Mac by Limeghost's hand at all now**, which makes the privacy claim simpler than it has ever been.
- Evidence Mode's exact-match highlighting is removed. It was the one thing no other browser could claim, and it had no reachable entry point once key points were gone. If a model that quotes ever arrives, the shape that keeps the honesty is verifying its quotes against the page by substring test — recorded in `docs/on-device-ai-design.md`.

**The profile dialogs stand up straight**

- New profile, Rename profile and Delete profile were left-aligned — icon in the corner, ragged text — while every other alert on the Mac is a centered column. Not a styling choice: they were plain `NSAlert`s, and AppKit silently switches an alert to a left-aligned "wide" layout once its text passes an unpublished length, which these prompts do. They are now drawn as the centered column deliberately — icon, title, message, field, buttons — with everything else kept: Return still creates or renames, deletion still defaults to Cancel so the easiest key changes nothing, Escape still cancels, and they still work with no window in front, since they are menu-bar commands.

**A closed window stops making noise**

- Closing a window left every web view in it alive: a page that was playing went on playing, audibly, with nothing on screen left to stop it. Three causes, uncovered in sequence because the first two fixes each tested clean and then failed on the real machine.
- First: nothing tore a window's tabs down at all — closing a *tab* called `teardown`, closing the *window* only dropped a dictionary entry. And `teardown` itself never stopped media: `stopLoading` ends the network fetch and does nothing to a `<video>` that has already buffered. It now pauses playback, closes full screen and picture-in-picture, and finally replaces the document — pausing alone is not enough, because the page's own script can resume it.
- Second, measured in the unified log after the first fix still leaked: **SwiftUI never closes these windows.** Clicking the red button on the last window of a `WindowGroup` posts no `willCloseNotification` — the window is ordered out and the scene kept, which is why a "closed" window could later reappear with its tab intact. A `willClose` observer waits forever for an event that never comes. The teardown now keys on the window *losing visibility*, with the states that must not count — miniaturized, app hidden with ⌘H, covered by another window, on another Space — explicitly excluded, and a half-second watcher backing up the occlusion notification. A window SwiftUI later revives comes back as one clean fresh tab, and a persistence guard keeps that fresh tab from overwriting the session saved on the way out.
- Third, measured again when the second fix *also* leaked: when one window of several closes, SwiftUI unmounts the view hierarchy **while the window is still on screen** — `forgetWindow` ran first, deleted the watcher's state, and the hide a moment later went unobserved. Forgetting a still-visible window now defers to the watcher, and a nil strip registration no longer erases what is known about the window.
- Confirmed by the founder on his own machine — the report that drove all three rounds. Proven first by ear-equivalent measurement, not by a green suite: a looping audio fixture in a private window, closed with the red button — the web content process dropped from steady decode to idle, and the log shows the teardown firing. The three regression tests encode each measured sequence, including the forget-while-visible ordering, and each fails when its fix is removed. The earlier claim in this entry that the first fix was "verified" was wrong: the verification had watched a window whose video was never audibly playing.

**Clearframe is now Limeghost**

- The product is renamed. `clearframe.com` turned out to be an operating software company — a live media-preservation product, not a parked domain — and the name was taken on .com, .net, .io, .ai and .co, which is what a single holder looks like. A trademark filing would have been made against an existing software user of the identical name. The reasoning, the roughly 140 names checked, and every rejected alternative are in [docs/brand/naming-decision-2026-08-31.md](docs/brand/naming-decision-2026-08-31.md).
- Limeghost describes the mark rather than decorating it: *Tyto alba*, the barn owl already drawn as the app icon, is called the **ghost owl** — the pale heart-shaped face, the silent flight. *Lime* is `#66DB7D`, the accent the interface already uses. And the name never says *bird*, which is what keeps it clear of Duolingo's "green owl" and of Owl Browser, an existing AI-assisted privacy browser.
- 130 files rewritten, every source directory, target and type renamed, the app bundle rebuilt as `Limeghost.app`.
- **The storage identifiers deliberately did not change.** The bundle identifier stays `com.clearframe.browser`, and the eighteen preference keys stay `clearframe.*`. Both `UserDefaults.standard` and `WKWebsiteDataStore.default()` hang off the bundle identifier, so renaming it would have orphaned bookmarks, history, profiles and every cookie and login, with no WebKit API to migrate the store. They are invisible to users, so the rename cost nothing by leaving them; the rule against tidying them later is in CLAUDE.md.
- Verified by launching the renamed build: every tab restored, the bookmarks bar intact, still signed in. 444 Swift tests, 50 of 50 live smoke checkpoints, 13 JavaScript tests, validator green.

**Limeghost has a face**

- The app icon is a barn owl — a heart-shaped facial disc inside a green ring — replacing the geometric cut-corner frame the icon script drew before. Three forms ship: the full mark, the face alone for small sizes, and a one-colour version for print and watermarks.
- The icon changes drawing by size rather than scaling one image down. Above 32 px it uses the full mark; at 16 and 32 it uses the face alone, because the ring turns to mud at that size and takes the face down with it. Rendered at both before deciding.
- The gradient stops well short of black. An earlier version faded to near-black, which looked striking on a dark presentation and lost the owl's entire body against Limeghost's own near-black chrome — the face floated above a wing with nothing joining them. Firefox's mark was the reference: four redesigns spent removing detail while keeping the gradient, and a palette that never touches white or black.
- The artwork's transparency and edges were verified rather than trusted — composited onto white and onto magenta, because a cut-out's fringe is invisible against both white and black.
- Adopting the owl ends the app icon's shared geometry with the 104 folder icons, which was a deliberate trade rather than an oversight. A missing artwork file falls back to the old geometric mark instead of breaking the build.

**The assistant's buttons stay where you left them**

- Compare, Fill the window and the close button used to live in the primary column's header — which slides a thousand points inward the moment a second column opens, taking them with it. They now sit immediately left of the close button and nowhere else, and close is anchored to the window's right edge in every layout, so they cannot move.
- There were two close buttons doing different things: one closed the second assistant, the other closed the entire panel. Same glyph, a thousand points apart, different amounts of damage. Every close button now closes its own column, and the last one closes the panel; closing one of two promotes the survivor and reloads nothing. One press to close everything is still the toolbar button and ⇧⌘A, which is where a control about the whole window belongs.
- Compare and Fill the window fold away while comparing, because neither has a job there, leaving two identical headers. Filling the window during Compare stays deliberate: it is a focused task, and on a small screen it is the only sensible shape.

**The smoke suite can no longer rot in silence**

- The end-to-end smoke suite moved into the ordinary test target. It had been a standalone file compiled only by a hand-maintained list of source files inside `run-browser-smoke.sh`, and that list rotted twice in nine days — most recently, the commits that removed the judgment layer edited the smoke file itself and shipped it uncompilable, because nothing but the script ever built it. Now every `swift test` compiles it, so a change that breaks it breaks the build everyone runs. The live checks — a real window, real pages from the local fixture server, focus, popups, extraction against live WebKit — still run only through the script, which shrank from 121 lines to about 60 and lists no files.
- Its assertions about the deleted judgment layer were rewritten against what exists: extraction through `session.extractPage()`, the two-layer defence against player-control text (the extractor skips containers that name themselves; the phrase filter catches the rest and is proven by the shared contract), structure detection on live pages, and the address guard that keeps Copy for AI from reading the start surface. One rewritten assertion initially aimed at the wrong layer and passed against a deliberately gutted filter; it was caught by sabotage-testing the suite before trusting it, and re-aimed.
- CI pins its Xcode now instead of drifting with the runner image, and no longer builds the release binary twice. A long-standing note in the README and AGENTS claiming both scripts were missing from every commit was false — they live under `macos/LimeghostBrowser/scripts/`, and the note came from searching the repository root.

**Your own AI, beside the page**

- The panel that used to hold Limeghost's opinions now holds the person's own assistant: ChatGPT, Claude, Gemini, Le Chat or Grok, as an ordinary web view signed in with their own account. ⇧⌘A opens it, one per window rather than one per tab — a conversation is something you keep while you read around it, and a per-tab assistant would start over every time you followed a link. It survives switching tabs, hiding, and expanding to fill the window. Copy for AI is a toolbar button now (⇧⌘C), and the risk signals moved into the site-information popover behind an explicit *Check this page*.
- Limeghost sends that panel nothing. It does not type into it, does not press its send button, and does not read what it says. The person pastes and asks, exactly as they would in a tab. Scripting a provider's page would be automated access to a service Limeghost has no agreement with, which their consumer terms forbid — so the manual paste is the design, not a missing feature.
- **Switching assistant no longer throws the conversation away.** It used to tear the web view down, so leaving ChatGPT mid-thread to check something in Claude and coming back landed on a blank ChatGPT. Two assistants now stay loaded — the one on screen and the one used most recently — and coming back to either is the same view, still where it was. A third parks the least recently used: its conversation's own address is remembered, the view is destroyed, and returning reopens that address. Signed-in chats live in the person's account on the provider's side, so the thread comes back; an unsent draft and a temporary chat are the two things that genuinely do not.
- Two stay loaded rather than five because hiding a web view does not give its memory back. WebKit keeps a "recently visible" claim on a hidden page for four minutes and suspending it pauses rather than discards it, so an uncapped panel would leave every assistant somebody ever tried still running.
- **Asking for a page now shows you the page.** While the assistant filled the window, ten of the fifteen ways to open one loaded it invisibly behind the panel — typing an address, clicking a bookmark, a Library or History row, ⇧⌘T, ⌘⌥B, ⌘Y, the Home button, a card on the AI guide, back and forward, and opening a local file. The address bar sits above the panel and stays usable, so it accepted what you typed and showed you nothing. One rule now covers every door: ask for a page and the page becomes visible; nothing moves when you did not ask. Switching between tabs you already have, a provider's sign-in popup, and reload are excluded on purpose.
- The first version of this fix covered ⌘T alone, which was worse than covering nothing: the same request behaved two ways depending on which button you pressed. A table-driven test now names each door, and it earned its place immediately — it passed against a deliberately broken rule until its setup was fixed, because opening and closing a tab is itself one of the doors it was using to prepare.
- Where a window has no room for both, the assistant leaves rather than shrinking into nothing, and comes back on its own when the window widens — so it reads as "no room" rather than "closed". One closed by hand stays closed.
- Leaving Compare now keeps the assistant that stayed **on screen** rather than the one that left it. Comparing loaded the second assistant last, so the next switch discarded the conversation still in front of the person — the opposite of what this file and CLAUDE.md both said it did.
- Opening a tab steps a full-window assistant back to the side rather than opening the page behind it. A new tab is somebody asking to look at something, and Compare covering the whole window answered that with a page nobody could see. Both conversations stay loaded; only the layout moves. Switching between tabs that already exist leaves the assistant exactly as it was.
- **Compare answers** puts two assistants side by side in the window, each with its own picker and its own close button, for asking the same question twice and reading the difference. It fills the window because two readable columns and a page do not fit on a laptop, and it is unavailable below 1,000 points of width rather than squeezing two providers into a shape neither designed for. Closing the second column gives back the layout you had.

3,550 lines deleted across two commits. 438 Swift tests, 13 JavaScript tests, validator green. The shared contract keeps 37 of its 61 cases: page structure, risk, reading time, sentence segmentation, and the three interface-noise suites.

### Week of August 24, 2026

**The page assistant is no longer always there**
- A tab opens without the assistant panel now, and Settings ▸ Page assistant has the switch that says otherwise. Analysis had always been something you click, but the panel arrived open regardless, so every new tab gave 380 points of a window to a button nobody had asked for yet. The sparkles button in the toolbar still opens and closes it for the tab in front of you, whichever way the setting is left.
- That button's effect now lasts as long as the tab does. Panel visibility used to be view state, and SwiftUI rebuilds a tab's view whenever the selection changes — so the panel you opened closed itself the moment you looked at another tab and came back. It lives on the tab.
- Changing the setting reaches the windows already open. Settings is its own window, so without that the switch appeared to do nothing until the next new tab.

**Bookmarks, on arriving from another browser**
- Importing can put the other browser's bar folders straight onto Limeghost's bar, instead of burying everything in one dated folder. The preview asks, and defaults by what is already there: an empty bar takes the import, a bar somebody has arranged gets the removable-in-one-gesture shape. Anything the source kept off its own bar goes into a single dated chip. Chromium makes the same call, and its own source calls the alternative "unnecessary nesting"; Firefox no longer wraps at all.
- The source's own root level is collapsed away in both shapes. It is a container the exporting browser writes on its way out, not a folder anybody made, and keeping it was a whole extra click on every folder.
- Both importers now read which folder the source called its bar — Chromium's `bookmark_bar` key, Netscape HTML's `PERSONAL_TOOLBAR_FOLDER` — instead of discarding it. Limeghost's exporter had always written that marker and Limeghost could not read it back, so exporting bookmarks and re-importing them lost the bar. The bar is never identified by folder title: the same folder is called "toolbar", "Bookmarks Toolbar", "Favorites", or whatever a localized export calls it.
- A folder name that collides with one already on the bar is named in the preview and then left alone. Limeghost does not merge an import into a folder somebody made, and does not rename theirs to "AI (2)" to make room, so both appear and either can be deleted.

**History**
- History is its own full-page destination on ⌘Y, grouped into Today, Yesterday and the days before, with its own search and Clear History. It used to share the bookmarks home behind a toggle, which meant the History menu's own "Show Full History" opened the bookmarks page, and ⌘Y was bound to nothing. ⌘Y is history in Safari, Chrome, Firefox, Edge, Brave and Arc on this platform.
- The toolbar's books button keeps a bookmarks-only popover. It is the drill-down organizer, with move menus and drop targets the full page has no equivalent for; the history half was what became redundant.

**Speed, with several hundred bookmarks**
- The store rebuilt and re-normalized its entire bookmark collection on every read, and the bookmarks bar reads once per chip, per redraw. With four hundred bookmarks in ninety-six folders that was about 135 ms per bar redraw, and moving a window redraws continuously — so dragging a window stalled for seconds. The collection is now built once and rebuilt only when the records change. Measured against the running app: the two normalization passes accounted for about 15% of main-thread time before, and do not appear in the trace at all after.
- Applying an import made one store call per folder and per bookmark, each re-encoding both whole collections. Four hundred bookmarks meant roughly a thousand full serializations of a growing collection. It is one write now.
- The address bar rebuilt its whole suggestion list several times per keystroke, and re-lowercased and re-split every candidate's title while matching — about 25 ms per character against a 17 ms frame. Both are done once now, and the folded forms are kept separate from the address a row opens, because a path or query folded to lowercase is a dead link.
- Renaming one bookmark no longer re-encodes every folder, and saving no longer re-decodes the stored value to check something it already knew.

### Week of August 21, 2026

**Windows**
- Multiple windows. Each keeps its own tabs and selection; bookmarks, history, downloads, site icons, tracker rules, and settings stay shared. Menu commands act on the window in front rather than on a single app-wide workspace. New Window (⌘N) and Close Window (⇧⌘W) appear in a File menu the app did not have before.
- A tab can be dragged out of the strip, upwards or downwards, into a window of its own, and the same move is on the tab's menu as "Move tab to new window". The tab carries its live web view across, so the page keeps its scroll position and its back/forward list instead of reloading. Dragging the last tab in a window moves the window, as Chrome does. Only the first window restores the saved session and only its tabs are written back; a torn-off window's tabs are not restored after a relaunch.

**Profiles**
- Profiles. Each one owns its bookmarks, history, saved session, site icons, per-site tracker exceptions, and — through its own `WKWebsiteDataStore` — its logins: two profiles signed into the same site do not see each other's session. The download list, the search choice and the WebKit switches stay shared.
- The profile that existed before this feature keeps the application's original stores, so bookmarks, history and signed-in sessions saved beforehand are not stranded behind a new identifier. It cannot be deleted; there has to be somewhere for a window to open.
- A window belongs to one profile for life. Choosing a profile opens a window in it rather than swapping the one in front, because a window's open pages are bound to their profile's cookies. For the same reason a tab dragged out of a window stays in its profile, and a drop into a window of a different profile is declined rather than silently rehomed.
- Deleting a profile removes its bookmarks, history, site icons, exceptions and logins from the Mac, after saying so and defaulting to cancel. Downloaded files are left alone.

**Menus**
- A File menu, which the app did not have: New Window, Open File…, Close Window, Save Page As…, and Share Page…. Opening a file is a separate door from opening an address — `WebURLPolicy` still refuses local schemes for links, typed addresses, popups, bookmarks and restored tabs, and a local page is kept out of both history and the saved session.
- Save Page As… writes a web archive of what the page is currently showing, rather than re-fetching the address.
- Share Page… offers the page's address through the system picker. The address only, never the page's text, and never without a destination being chosen there.
- History and Bookmarks menus. History lists recent pages, one entry per page rather than one per visit, and holds Back, Forward and Reopen Closed Tab. Bookmarks mirrors the bar's folders and links.
- New Private Window (⇧⌘N), which is what that chord means in both Safari and Chrome; Limeghost had put a private *tab* there. A private window opens blank, every tab in it is private, it restores no session and writes none, and it offers no way to open an ordinary tab beside the private ones.
- The File menu now carries what both browsers put there: New Tab, New Window, New Private Window, New Empty Tab Group (⌃⌘N), Open File…, Open Location… under its standard name rather than "Focus Address Bar" in Page, Close Window, Close All Windows (⌥⇧⌘W), Close Tab, Save Page As…, Export as PDF…, Share Page… and Print. Safari's empty tab group starts with no tabs; ours starts with one blank tab, because a group with no tabs is pruned by design.
- Reload, Stop, and the zoom commands moved from Page to View, where a Mac user looks for them; View had held nothing but Enter Full Screen. AppKit's own window tabbing is switched off, so Show Tab Bar and Show All Tabs no longer appear beside Limeghost's own tab strip.

**Tabs**
- A tab is dragged by any part of its chip and reorders live under the pointer, rather than through the system drag-and-drop session with its press-and-hold delay. Dragging a tab previously moved the whole window: `hiddenTitleBar` keeps `fullSizeContentView`, so the strip sits in the band AppKit treats as a title bar, and every view AppKit hit-tests there is a SwiftUI-internal container answering `mouseDownCanMoveWindow` with the NSView default of `true`. The window is now not movable by AppKit at all, and the strip grants dragging back as a gesture on empty background only.
- Known gap: dropping the `Button` that made a pinned chip an accessibility element costs it its spoken name. A pinned tab is reachable and actionable and carries its title as a hint, but announces as "button" first.

### Week of August 18–20, 2026

**Tabs**
- Tabs compress as the window narrows: a width-distribution layout capping each tab at 200pt, holding a 54pt comfortable minimum, giving the selected tab a larger share so it stays readable, and scrolling only below that floor.
- Tab groups: named, eight colours, collapsible, persisted across relaunch, with menus on both tabs and group chips. Sessions saved before groups existed restore unchanged.

**Bookmarks**
- Bar chips size to their own label. They had been pinned to a fixed 140pt because a width measurement never landed in the shipped app, which is what made short names sit in wide boxes.
- Bookmarks became editable. Bar links, organizer rows, and the bookmarks home now share one menu — open, open in a new tab, edit, copy address, move to a folder, delete — backed by an editor sheet that validates the address. Folders gained open all, add current page, new subfolder, rename, and delete.

**Page understanding**
- Key points and claims are now guaranteed verbatim substrings of the page, enforced by the shared analysis contract. Evidence Mode finds them by searching the live page, so any invented character broke it.
- Sentences split per reading block instead of inventing terminators; evidence matching widened; a failed match no longer blames the page.

**Browser basics**
- File upload through the standard macOS picker, find in page, print, and per-tab page zoom.
- Limeghost can offer to become the default browser.
- Restored tabs show their address in the bar; an option loads every restored tab at start.
- Webpages follow the Mac's appearance while the chrome stays dark; sites are asked for the page Safari would receive.

**Identity**
- 104 custom folder icons replaced emoji throughout, with four tints, drawn on bar chips and folder cards. Two licensed sets — Stickies and EmojiOne — sit alongside them with visible attribution.
- The app mark is drawn from the icon set's own construction rule. Zincoo credited as maker.

**Documentation**
- Browser feature research and gap analysis recorded, including a complete bookmark-import specification.
- The naming decision recorded, along with what it does not settle.
- Passkeys documented as not working yet, rather than left ambiguous.

*End of period: 217 Swift tests, 27 JavaScript tests, 48 smoke-suite groups, CI green.*

### Week of August 14–16, 2026

**Tracker blocking, built for real**
- A curated first-party list of 205 advertising and tracking domains, versioned and dated, compiled through WebKit's content-rule engine and applied to every tab including private ones.
- An address-bar shield with per-site exceptions and a global switch in Settings. The interface shows state and never counts, because WebKit applies rules inside the page process and reports nothing back — so no honest count exists.
- Verified end to end: a real request blocked in a live WebKit window, released by a per-site exception, then blocked again.

**The Halo redesign**
- A single-row dark chrome: hidden system title bar with traffic lights inline in the tab strip, one unified toolbar and address pill, a slim bookmarks bar. Roughly 155pt of chrome became 113pt.
- Every colour moved into one theme. Per-site identity colours derived locally from the host by a stable hash.
- A full-page bookmarks home with visual folder cards, rolled-up counts, search across bookmarks and folder names, drill-down, and local history.
- Site icons captured only during an actual visit, from the visited site's own origin, cached locally, memory-only in private tabs, wiped by the data reset. No third-party icon service.

**Page understanding**
- Section pages are recognised. Analyzing a news index used to stitch dozens of unrelated headlines into a confident-looking summary; it now explains what the page is and offers Analyze anyway.
- Claims stopped repeating sentences already shown in the summary or key points.
- Stopwords are selected by the page's declared language. A single merged multilingual set had been suppressing ordinary English words such as "care" and "son".

**Licensing**
- The repository was licensed under AGPL-3.0.

*End of period: 85 Swift tests, 26 JavaScript tests.*

### Week of August 11–13, 2026

- The macOS browser foundation: a native SwiftUI window with WebKit rendering, tabs, private tabs, navigation, and error states.
- Local page analysis — extractive summary, key points, candidate claims, risk signals — with multilingual support and an evidence mode that highlights the extracted sentence in the live page.
- Downloads with a chosen destination, local bookmarks with folders, a bookmarks bar with drag filing, and capped local history.
- A task-first AI guide as the new-tab surface, with editorial badges, a visible catalog version, and links to official destinations only.
- The shared Swift and JavaScript analysis contract, so both runtimes are held to identical behaviour by one set of fixtures.
- The focused creator go-to-market plan.

---

## Conventions

- One user-visible change per entry, written in terms of what a person can now do or see.
- Honest scope: no entry claims validation, safety, or completeness the project has not earned.
- Fixes state what was wrong, not only that something was fixed.
