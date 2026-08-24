# Changelog

Clearframe's development record, assembled from the repository's own history.

The project has not made a public release. There are no version tags, and the app bundle carries `0.1.0` as a development placeholder. Everything below is pre-release work on `main`, grouped by the week it landed. Once a first release ships, this file should switch to versioned sections following [Keep a Changelog](https://keepachangelog.com/) and [semantic versioning](https://semver.org/).

Dates are commit dates. Test counts are the totals at the end of each period, verified by running the suites.

---

## Unreleased

### Week of August 24, 2026

**Bookmarks, on arriving from another browser**
- Importing can put the other browser's bar folders straight onto Clearframe's bar, instead of burying everything in one dated folder. The preview asks, and defaults by what is already there: an empty bar takes the import, a bar somebody has arranged gets the removable-in-one-gesture shape. Anything the source kept off its own bar goes into a single dated chip. Chromium makes the same call, and its own source calls the alternative "unnecessary nesting"; Firefox no longer wraps at all.
- The source's own root level is collapsed away in both shapes. It is a container the exporting browser writes on its way out, not a folder anybody made, and keeping it was a whole extra click on every folder.
- Both importers now read which folder the source called its bar — Chromium's `bookmark_bar` key, Netscape HTML's `PERSONAL_TOOLBAR_FOLDER` — instead of discarding it. Clearframe's exporter had always written that marker and Clearframe could not read it back, so exporting bookmarks and re-importing them lost the bar. The bar is never identified by folder title: the same folder is called "toolbar", "Bookmarks Toolbar", "Favorites", or whatever a localized export calls it.
- A folder name that collides with one already on the bar is named in the preview and then left alone. Clearframe does not merge an import into a folder somebody made, and does not rename theirs to "AI (2)" to make room, so both appear and either can be deleted.

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
- New Private Window (⇧⌘N), which is what that chord means in both Safari and Chrome; Clearframe had put a private *tab* there. A private window opens blank, every tab in it is private, it restores no session and writes none, and it offers no way to open an ordinary tab beside the private ones.
- The File menu now carries what both browsers put there: New Tab, New Window, New Private Window, New Empty Tab Group (⌃⌘N), Open File…, Open Location… under its standard name rather than "Focus Address Bar" in Page, Close Window, Close All Windows (⌥⇧⌘W), Close Tab, Save Page As…, Export as PDF…, Share Page… and Print. Safari's empty tab group starts with no tabs; ours starts with one blank tab, because a group with no tabs is pruned by design.
- Reload, Stop, and the zoom commands moved from Page to View, where a Mac user looks for them; View had held nothing but Enter Full Screen. AppKit's own window tabbing is switched off, so Show Tab Bar and Show All Tabs no longer appear beside Clearframe's own tab strip.

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
- Clearframe can offer to become the default browser.
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
