# The phone's tab switcher — page previews and a card worth looking at

**Date:** September 27, 2026
**Status:** design agreed, implementation in progress
**Step:** 5 of the pocket-browser plan, "the look" — its first piece

## 1. What prompted this

The founder used the reinstalled build on an iPhone 13 Pro Max and reported it
working, with one wish, sent as a screenshot of Chrome's own tab switcher: the
cards have no preview, they could be longer, and Chrome's top row carries more
controls.

Reading `ios/Sources/TabSwitcher.swift` against that screenshot turns up more
than was asked for:

| | today | Chrome |
|---|---|---|
| preview | none | a page snapshot filling the card |
| card | fixed height 110 | ~185 × 243 pt on a Pro Max |
| favicon | none — a grey host string instead | favicon beside the title |
| the tab you are on | **nothing marks it** | a blue ring |
| surfaces | the system's default sheet | its own |
| private tabs | a second section, always visible even when empty | a segment |

The missing selected marker is the one nobody asked about and the one that
matters most: with denser cards, a grid that does not say where you are is a
grid you have to guess at.

## 2. Scope

**In:** page previews, the card's shape, the favicon, the selected ring, and
the switcher drawing on Limeghost's surfaces like every other sheet.

**Out, deliberately:** tab groups, and search across tabs. Search is real once
somebody has twenty tabs and should come later on its own evidence; groups are
a control Chrome needs because Chrome has users with eighty tabs, and adding
them here would be copying a competitor rather than answering a need. The
private/regular segment is also held back to its own change, because it
restructures what the screen *is* rather than how it looks.

## 3. Previews

### 3.1 When a snapshot is taken

`WKWebView.takeSnapshot(with:)`, at the moment a tab **stops being visible** —
the switcher opening, or the app backgrounding. Never on a timer: a timer
photographs pages nobody is looking at and spends battery to do it.

Only the tab that was visible is captured. Capturing every tab when the
switcher opens would hitch the animation, and the others cannot be captured
anyway — a tab with no live web view has nothing to photograph.

### 3.2 What a snapshot is, for privacy — memory only, for every tab

The obvious move is to copy `FaviconStore`: disk cache for ordinary tabs,
memory only for private ones. **That is the wrong policy here**, and reading
the codebase is what says so.

A favicon is a site's mark, keyed by host, and it is the same picture whoever
loads it. A page snapshot is keyed by tab and is *a photograph of what that
page showed you* — a bank balance, a medical result, a draft. The workspace
already draws this distinction elsewhere: `rememberClosedTab` keeps closed
tabs in memory only, and the comment beside it
(`LimeghostShared/BrowserWorkspace.swift:341`) gives the reason — a closed tab
coming back after a relaunch is a surprise, and for a private tab it would be
a leak. A folder of page photographs surviving a relaunch is the same leak
with pictures.

So: **no disk, for any tab.** The store is an in-memory cache and nothing
else, which also deletes the entire file-naming, path-traversal, eviction and
cold-start surface that the favicon store needs a hundred lines to get right.

What it costs is narrow: after a relaunch the switcher shows identity squares
until each tab has been looked at once. Restored tabs are deferred and have
not loaded anyway, so for most of them there would have been nothing truthful
to show.

The store still clears explicitly, in three places:

- `BrowserWorkspace.resetLocalBrowsingData()`, beside `favicons.clearAll()`
  (`BrowserWorkspace.swift:1588`). There is no iOS entry point for the reset
  yet; wiring one is not this change.
- `closeTab`, because a closed tab's picture has no reader left.
- `teardown`.

Snapshots are downscaled to the card's pixel size on capture regardless — a
full-resolution page image is megabytes and the card is about 173 points wide.

### 3.3 Not `PageSnapshot`

`PageSnapshot` already means the local-analysis input struct in
`LimeghostCore`, and `BrowserWorkspaceSnapshot` means the persisted tab list.
Both are *state*, neither is a picture. The new type is **`TabPreviewStore`**.

### 3.4 When there is no snapshot

A tab restored from a previous launch has never been seen, and a parked tab's
image may have been evicted. The fallback is the `SiteIconView` identity
square the product already shows for an unvisited host — **never a grey
rectangle**, which reads as a page that failed to load rather than a page not
yet seen.

### 3.5 Where the code lives

The store lives in `LimeghostShared`, owned by `BrowserWorkspace` the way
`favicons` is, because the reset that must clear it lives there too. The
shared suite then tests it on both destinations.

It takes no `#if os`, by the route `FaviconStore` already found and documents
at its line 140: `takeSnapshot` hands back an `NSImage` on the Mac and a
`UIImage` on the phone, and neither type belongs in a shared file — so the
store deals in **`CGImage`**, which both convert to, and **capture happens on
the iOS side**. No protocol member is added, because only one platform has a
grid to draw.

Like `FaviconStore`, it publishes a `revision` counter rather than the cache
itself, since an `NSCache` mutating does not tell SwiftUI anything.

The image must reach the card as a value, not by the card reaching a session.
`TabSwitcherModel`'s own doc comment says it touches no session *so the grid
can be laid out without a live `WKWebView`*, and its three tests depend on
that. A card that pulled its own image would quietly end it.

## 4. The card

Chrome's card is a header strip — favicon, title, close — above an image that
fills the rest, cropped from the top. It reads as *the page* because a page is
taller than it is wide.

- The fixed height of 110 goes. Height is **driven from width by an aspect
  ratio of 3:4** on the preview, so one number covers an iPhone SE, a Pro Max
  and landscape without a second number kept in sync by hand. This is the same
  reasoning that made the Mac's address pill a `Capsule`.
- The favicon comes from `SiteIconView`, already compiled into the phone
  target, at `LimeghostTheme.siteIconSize`.
- The selected tab takes a ring in `LimeghostTheme.accent`. Limeghost's accent,
  not Chrome's blue.
- The close control stays a real `Button` and the card body stays a tap
  gesture, for the reason already written in the file: a `Button` inside a
  `Button`'s label is ambiguous to hit-test.

## 5. Surfaces

The switcher is the only sheet that does not call `limeghostListSheet()`, so it
opens system-grey while Bookmarks and History open on Limeghost's surfaces.
`SheetLook.swift` says in its own comment that the rest of the app waits for
step 5. This is step 5.

## 6. What this must not become

Previews make a tab switcher look like a product decision about *content*. It
is not one. A snapshot is a picture of what the page looked like, and
Limeghost must not sort, rank, score, or label tabs by it — the same line the
product drew when it deleted sentence ranking and the judgment layer. The grid
shows tabs in the order they were opened, and that is all it knows.

## 7. Honesty

Nothing here is user-validated. It answers one founder's use of their own app
on one phone, which is dogfooding, and the card geometry was measured off a
screenshot of a competitor rather than tested with anybody.
