# Changelog

Clearframe's development record, assembled from the repository's own history.

The project has not made a public release. There are no version tags, and the app bundle carries `0.1.0` as a development placeholder. Everything below is pre-release work on `main`, grouped by the week it landed. Once a first release ships, this file should switch to versioned sections following [Keep a Changelog](https://keepachangelog.com/) and [semantic versioning](https://semver.org/).

Dates are commit dates. Test counts are the totals at the end of each period, verified by running the suites.

---

## Unreleased

### Week of August 21, 2026

**Windows**
- Multiple windows. Each keeps its own tabs and selection; bookmarks, history, downloads, site icons, tracker rules, and settings stay shared. Menu commands act on the window in front rather than on a single app-wide workspace. New Window (⌘N) and Close Window (⇧⌘W) appear in a File menu the app did not have before.
- A tab can be dragged out of the strip, upwards or downwards, into a window of its own, and the same move is on the tab's menu as "Move tab to new window". The tab carries its live web view across, so the page keeps its scroll position and its back/forward list instead of reloading. Dragging the last tab in a window moves the window, as Chrome does. Only the first window restores the saved session and only its tabs are written back; a torn-off window's tabs are not restored after a relaunch.

**Menus**
- A File menu, which the app did not have: New Window, Open File…, Close Window, Save Page As…, and Share Page…. Opening a file is a separate door from opening an address — `WebURLPolicy` still refuses local schemes for links, typed addresses, popups, bookmarks and restored tabs, and a local page is kept out of both history and the saved session.
- Save Page As… writes a web archive of what the page is currently showing, rather than re-fetching the address.
- Share Page… offers the page's address through the system picker. The address only, never the page's text, and never without a destination being chosen there.
- History and Bookmarks menus. History lists recent pages, one entry per page rather than one per visit, and holds Back, Forward and Reopen Closed Tab. Bookmarks mirrors the bar's folders and links.
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
