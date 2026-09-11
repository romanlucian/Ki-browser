# Limeghost for iPhone — the page menu

**Status:** designed with the founder on September 11–12, 2026, and approved in two parts in that conversation. This document records that design, plus what reading the code for it changed (§3.2, §4 and §6 mark each change). It is the first of the pieces the phone still lacks (§1).

- The phone app it builds on is described in [docs/ios-browser-foundation.md](../../ios-browser-foundation.md).
- The overall iOS design is [2026-09-03-ios-pocket-browser-design.md](2026-09-03-ios-pocket-browser-design.md). Its §4 already names a menu that "does the Page menu's job".
- The mockups are a design canvas: [Limeghost iPhone Page Menu](https://claude.ai/code/artifact/905a148d-bffc-4c9b-9ba1-af0e9785f144), private to the founder's account. They show six screens at the founder's iPhone 13 Pro Max size. They are a visual draft, not a pixel contract.

## 1. Why a menu, and why first

The phone app browses. It has tabs and private tabs, a bottom bar, an address sheet with local completion, a tab switcher, and the AI guide. It has no menu.

Chrome for iOS, from the founder's screenshots on September 11, keeps most of a browser behind one "•••" sheet: a row of large buttons, then a list of page actions. The founder chose that shape. The contents, colours and wording here are Limeghost's own, and the icons are Apple's system symbols.

On September 11 the founder and Claude split the remaining phone work into steps, in this order:

1. **The menu and everyday basics.** This document.
2. **Bookmarks and History pages.**
3. **The person's own AI on the phone**, as designed in the iOS spec's §5.
4. **Settings.**
5. **The look:** a design round for the phone's chrome, as the Mac had.
6. **Later:** bookmark import from the Mac, the introduction, and downloads.

The menu comes first for three reasons:
- Every later step plugs into it.
- Most of its items reuse code that `LimeghostShared` already runs on both platforms.
- It brings Reader and Copy for AI to the phone, and those carry the product's promise of a page whose text is ready to hand to an AI.

## 2. Scope

**In this step:**

- **A `•••` button** in the bottom bar, after the tab count. This is the place `BottomBar.swift` already reserves for it.
- **A sheet** with two large buttons, **Reader** and **Copy for AI**, then two cards of rows:
  - Reload, Forward, New Tab, New Private Tab.
  - Add Bookmark, Find in Page, Share, Request Desktop Site.
- **Reader on the phone**: the Mac's own `ReaderView`, with a header a finger can use.
- **Find in Page**, as a bar in the bottom bar's place.
- **A banner** that shows the shared session's page notices.
- **A per-tab desktop-site switch** in `LimeghostShared`. The page-load hook is rewritten as a decision that tests can read.

**Not in this step.** These are Chrome's menu items that stay out, compared with the founder on September 11:

| Chrome | Where it goes |
|---|---|
| Bookmarks and History buttons | Step 2, together with their pages. A button that opens onto nothing teaches the wrong thing about where it lives. That is why `BottomBar.swift` left the menu's place empty until now. |
| Settings, Delete browsing data | Step 4. |
| Zoom text | Not this step. The shared session already zooms, so it is cheap to add later. |
| Downloads | v1.1, as in the iOS spec's §2. On iOS downloads are a subsystem, not a button. |
| Recent tabs from other devices | Needs sync. CloudKit waits on Developer Program enrolment. |
| Password Manager | Not planned. Whether the phone's own AutoFill works inside `WKWebView` is on the device checklist and untested. |
| Translate, Google Lens | Not planned. Limeghost prepares a page for the person's own AI; it does not interpret the page. |
| Reading list | Not planned. Bookmarks already cover "save for later". |
| AI Mode | The person's own assistant arrives in step 3. |

## 3. What the person sees

### 3.1 The button

```
‹   [      example.com      ]   2   •••
```

The button is the SF Symbol `ellipsis`, styled like the rest of today's bar. VoiceOver reads it as "Menu". Its touch area is 44 points wide and as tall as the address pill, so it is much larger than the glyph. The address pill gives up that width. The bar's other controls keep their current touch areas, and the bar's colours belong to step 5, not to this document.

### 3.2 The sheet

The menu is a SwiftUI `.sheet` with a visible drag indicator. The person closes it by swiping down or tapping outside it.

**It opens exactly as tall as its rows.** *(Changed from the approved design, which used the medium detent, half the screen.)*
- The rows need about 530 points.
- So at half height, by the layout's own arithmetic, the last rows would open below the fold. On the founder's iPhone 13 Pro Max, 926 points tall, that is Share and Request Desktop Site. On a 667-point iPhone SE, it is most of the second card.
- The menu therefore measures its own content and uses that height as the sheet's detent.
- The content sits in a scroll view, which scrolls only when the rows are taller than the screen allows, for example at the largest text sizes.

```
┌────────────────────────────────────┐
│               ────                 │
│   [ Reader ]     [ Copy for AI ]   │
│ ┌────────────────────────────────┐ │
│ │ Reload                       ↻ │ │
│ │ Forward                      › │ │
│ │ New Tab                      ⧉ │ │
│ │ New Private Tab              ⊘ │ │
│ └────────────────────────────────┘ │
│ ┌────────────────────────────────┐ │
│ │ Add Bookmark                 ☆ │ │
│ │ Find in Page                 ⌕ │ │
│ │ Share                        ⇪ │ │
│ │ Request Desktop Site         ▭ │ │
│ └────────────────────────────────┘ │
└────────────────────────────────────┘
```

**Labels use Apple's title case for menu items.** Where the Mac's menu bar already names an action, the phone uses the Mac's name: New Tab, New Private Tab, Add Bookmark, Find in Page, Forward. There are two exceptions:
- **Reload**, not the Mac's Reload Page.
- **Share**, not Share Page….

In a menu about the page, the extra word says nothing.

**Symbols:**

| Item | Symbol |
|---|---|
| Reader | `doc.plaintext`, as the Mac's Reader header uses |
| Copy for AI | `doc.on.doc` |
| Reload | `arrow.clockwise` |
| Forward | `chevron.forward`, matching the bar's back chevron |
| New Tab | `plus.square.on.square` |
| New Private Tab | `eye.slash`, as the tab switcher's Private section already uses |
| Add Bookmark | `star`, or `star.fill` on a saved page |
| Find in Page | `magnifyingglass` |
| Share | `square.and.arrow.up` |
| Request Desktop Site | `desktopcomputer`, or `iphone` while the desktop version is on |

**Copy for AI is always labelled, never an icon alone.** `CLAUDE.md` records why the Mac's toolbar icon for it was removed: `doc.on.doc` named neither AI nor copying. A labelled button inside a menu is exactly where the Mac keeps it.

### 3.3 States

**On a web page,** every row works, with two exceptions:
- Forward works only while `workspace.canGoForwardInSelectedTab` is true.
- Find in Page is greyed while Reader is open. Find searches the page, and Reader covers it, so a match would be highlighted where nobody can see it.

**On the AI guide,** or anywhere else without a web page:
- These are greyed: Reader, Copy for AI, Reload, Add Bookmark, Find in Page, Share and Request Desktop Site.
- New Tab and New Private Tab stay live.
- Forward follows its own state.
- "Has a page" means `workspace.canShareSelectedPage`, the check Share already uses: a valid web address in the selected tab.

Greyed rows stay in place rather than disappearing. They become available the moment a page opens.

**Three labels change with the page:**
- **Add Bookmark** reads Remove Bookmark when `dataStore.isBookmarked(currentURL)` is true. This is the check the Mac's own chrome uses.
- **Request Desktop Site** reads Request Mobile Site while the tab's switch is on (§6).
- **Reader** reads Close Reader while Reader is open. *(Added while writing this document: the tile toggles, and its label says what a tap will do next.)*

## 4. What each item does

**A tapped row closes the sheet first, and acts once the sheet has gone.** This is not only tidiness:
- `IOSPageSharing.share` presents the system share sheet from the window's root view controller. That controller cannot present anything while the menu sheet is still up.
- The find bar's keyboard and Reader need a clear screen for the same reason.

A small value type, `PageMenuPresentation`, holds that rule so a test can hold it too.

**Reader**
- `await workspace.toggleReaderInSelectedTab()` sets or clears `tab.readerArticle`.
- While an article is open, `TabSurface` draws the Mac's own `ReaderView` over the page. `WebViewHost` stays mounted underneath, so no web view moves or reloads.
- Reader's ✕ sets `tab.readerArticle = nil`.
- Reader's own Copy for AI copies the article on screen and turns into "Copied" for a moment, exactly as on the Mac.
- `ReaderView.swift` joins the iOS target by reference. That makes six Mac Swift files the phone compiles. Whether it compiles for iOS is the first thing the plan's Reader task checks.
- The Reader rule in `CLAUDE.md` binds either way: Reader draws `readableText`, and nothing else.

**Reader's header for a finger** *(changed after reading `ReaderView.swift`)*
- The Mac's header is one row of 11- to 13-point text and borderless buttons, sized for a mouse.
- At 428 points that row even fits a phone, so a width-based switch (`ViewThatFits`, as the AI guide's header uses) would pick it. But its buttons are still far below the 44-point minimum Apple gives a finger.
- So the caller chooses the arrangement. `ReaderView` gains `headerStyle`:
  - The Mac passes nothing and keeps its row, `.pointer`.
  - The phone passes `.touch`. That is two rows of 44 points each:
    - Row one: the Reader symbol, "Reader", the host, and a ✕ in a 30-point circle.
    - Row two: the word count, and a labelled Copy for AI button.

**Copy for AI**
- `await workspace.copySelectedPageForAI()` copies the open Reader article if there is one; otherwise it reads the page. It now returns the article it copied, or nil when nothing was copied. *(A shared change. The Mac's one caller discards the result.)*
- The phone then posts `article.copyConfirmation`, a new shared property. When the copy is doubtful, it is the article's own `copyNotice`, for example "Copied 812 words — but Limeghost could not find an article here, so this is the whole page, menus included." When it is not, it is "Copied 127 words."
- The Mac deliberately says nothing about a clean copy, because a sentence on every copy is one nobody reads by the third time. Reader's button already changes to "Copied". The phone's menu closes as it copies, though, and iOS shows nothing when an app writes to the clipboard. Without a sentence, there is no sign the copy happened at all.
- When nothing is copied, `readCurrentPage(verb:)` has already posted the reason, for example "Limeghost found no readable text on this page." No confirmation goes on top of it.

**Reload.** `workspace.reloadSelectedTab()`. This is not a door; `CLAUDE.md` excludes reload deliberately.

**Forward.** `workspace.goForwardInSelectedTab()`. This is a door, already in the door table.

**New Tab / New Private Tab.** `workspace.addTab()` and `workspace.addTab(isPrivate: true)`. Both are doors, already in the table. A new tab opens on the AI guide.

**Add Bookmark / Remove Bookmark**
- `workspace.toggleBookmarkForSelectedTab()` adds the page at the top level (`folderID: nil`), or removes it if it is already saved.
- The shared toggle posts nothing, and the phone has no star to show the change. So the phone reads the store before and after the toggle, and posts "Bookmark added." or "Bookmark removed." for whichever happened.
- If the store refused the address, nothing changed and nothing is claimed.
- Choosing a folder arrives with step 2.

**Find in Page**
- `workspace.findInSelectedTab()` opens it.
- While `tab.find.isPresented`, a find bar takes the bottom bar's place. The field takes the keyboard.
- Typing calls `queryChanged()`. Return and the down arrow step forward; the up arrow steps back. Done calls `close()`, which keeps the query, as on the Mac.
- The bar says "No results" for `.noResults`, and nothing for `.idle` or `.matched`. On a match, the page's own highlight is the answer.
- The arrows (`chevron.up`, `chevron.down`, as on the Mac's bar) stay greyed until there is a match to step through. The Mac greys them only while the field is empty. On a phone, with no count to show, greyed arrows are how the bar says there is nothing to step to.
- **There is no position and no count.** WebKit's find reports only whether a match exists, and `PageFindController` forbids presenting either. The September 11 conversation first promised "3 of 12"; this corrects it.

**Share.** `workspace.shareSelectedPage()` goes through `PageSharing.share(url)` to `IOSPageSharing`'s system share sheet.

**Request Desktop Site / Request Mobile Site.** `workspace.toggleDesktopSiteInSelectedTab()` is new. It flips the selected session's switch, and the session reloads (§6).

## 5. The look

This step keeps the structure the founder chose and uses Limeghost's colours. Every new colour comes from `LimeghostTheme`, as `CLAUDE.md` requires.

**The sheet**
- `.presentationBackground(LimeghostTheme.bg1)`.
- The two large buttons and both cards are `bg2`, with a `hairline2` edge and `radius12` continuous corners.
- Large buttons are 84 points tall, with a 22-point `accent` symbol over a 15-point semibold label.
- Rows are 48 points: 17-point text in `textPrimary`, with the symbol trailing in `textSecondary`.
- Greyed rows and buttons draw both text and symbol in `textTertiary`.

**The banner**
- A rounded rectangle, `radius14`, on `bg3`, with a `hairline3` edge and a soft shadow. Its text is 15-point `textPrimary`.
- It floats 12 points above the bottom bar, over the page.
- A tap dismisses it (`dismissPageNotice()`). Otherwise the session clears it after eight seconds.
- It is a rectangle, not a capsule, because the longest notices run to three lines.

**The find bar.** The bottom bar's height and its system look: the system tint, and a grey capsule field. It stands where the bar stands, so the two take the theme together in step 5.

**Reader.** The Mac's colours, unchanged: a `bg1` body under a `bg2` header. The touch header's buttons sit on `bg3`.

**The bottom bar.** Unchanged except for the `•••` button. Its colours are step 5's.

## 6. The page-load hook and the desktop switch (shared)

**The switch**
- `BrowserSession` gains `@Published public private(set) var prefersDesktopSite = false`, and `setPrefersDesktopSite(_:)`.
  - `setPrefersDesktopSite(_:)` changes the switch and reloads, because the page on screen was fetched as the other version.
  - The reload is a navigation, so it passes the page-load hook, where the switch is read.
- `BrowserWorkspace` gains `toggleDesktopSiteInSelectedTab()`.
- The switch holds per tab, for the life of the tab in this run. Nothing saves it, so a restored tab loads the ordinary version. Remembering the choice per site is a later decision.
- It is not a door: turning it on reloads the page the person is already on.

**The hook** *(changed after reading `BrowserSession.swift`: the decision is now a function tests can read)*
- The delegate method changes to WebKit's other signature: from `webView(_:decidePolicyFor:decisionHandler:)` to `webView(_:decidePolicyFor:preferences:decisionHandler:)`.
  - `WKNavigationDelegate.h` in the iOS 26.5 SDK states that when the second exists, the first "will not be called".
  - It marks the second `API_AVAILABLE(macos(10.15), ios(13.0))`. So `LimeghostShared` still takes no `#if os`.
- The old method's branches move, unchanged, into a pure function:

  ```swift
  static func decide(shouldPerformDownload: Bool, targetFrameIsMain: Bool?, url: URL?) -> NavigationActionDecision
  ```

  `NavigationActionDecision` has five cases, one per branch the old method had:
  - `.download`
  - `.openInNewTab(URL?)`
  - `.restoreStartSurface`
  - `.unsupported(URL)`
  - `.allow(mainFrameURL: URL?)`

  No test reached those branches before. Each is tested now, with plain values, on the Mac and on the Simulator.
- The delegate becomes a thin adapter. It asks `decide`, carries out the answer exactly as the old branches did, and hands WebKit its preferences back.
- Before deciding, it calls `applyContentMode(prefersDesktopSite:to:)`:
  - With the switch on, this sets `preferredContentMode = .desktop`.
  - With it off, it leaves WebKit's preferences exactly as they came in.
- The Mac never turns the switch on, so its navigations are unchanged. Its full suite, which the plan runs after the hook changes, is the check.

## 7. Architecture

**iPhone** (`ios/Sources` and the project file):
- **`BottomBar.swift`** gains the `•••` button and an `openMenu` closure.
- **`PageMenu.swift`** is new. It holds:
  - `PageMenuItem`, the ten items in the order they show.
  - `PageMenuModel`, a pure value from five inputs: has a page, can go forward, is bookmarked, prefers the desktop site, Reader is open. It answers a title, a symbol and whether each item is enabled.
  - `PageMenuActions`, with one `perform(_:)` entry point plus named methods for the two items that say something: `copyForAI()` and `toggleBookmark()`.
  - `PageMenuPresentation`, the close-then-act rule.
  - The `PageMenu` view, which reports its content height up for the sheet's detent.
- **`FindBar.swift`** is new: the find bar, with its outcome text and arrow state as pure static functions.
- **`NoticeBanner.swift`** is new: the banner, and `NoticeLayer`, which observes the selected session.
- **`BrowserScreen.swift`**:
  - It presents the menu sheet and runs the chosen item from `onDismiss`.
  - It draws `NoticeLayer` over the bottom of the tab's surface.
  - It gains `BottomChrome`, which observes the tab's find controller and shows the find bar or the bottom bar.
  - `TabSurface` gains `showsTheReader` and draws Reader over the page.
- **`project.pbxproj`** gains the three new files, `ReaderView.swift` by reference, and three test files.

**Shared:**
- `BrowserSession.swift`: the switch, `decide`, `applyContentMode`, and the delegate's new signature.
- `BrowserWorkspace.swift`: `toggleDesktopSiteInSelectedTab()`, and `copySelectedPageForAI()` returning the article.
- `ReaderArticle.swift`: `copyConfirmation`.

**Mac:**
- `ReaderView.swift` gains `headerStyle` and a nested `Header` type, so a test can render the header at a given width, as `AIToolStartPage.Header` is rendered. The Mac's call site is unchanged.

**Why the views are split this way.** `BrowserScreen` observes the workspace. A tab's find controller and a session's notice change without the workspace hearing of them. So each is drawn by a small view that observes its own object: `BottomChrome` and `NoticeLayer`. `TabSurface` already observes its tab and session for the same reason.

**Rules this design keeps:**
- No `#if os` in `LimeghostShared`.
- The phone adds no door, as the iOS spec's §4 requires. Forward and the two new-tab rows are existing doors, and reload is deliberately not one.
- Reader draws `readableText` and nothing else, in one `ReaderView` compiled by both apps.
- Copy for AI is labelled wherever it appears.
- New colours come from `LimeghostTheme`.
- No count is ever shown for Find in Page.
- A notice never claims something that did not happen.

## 8. Testing

Every test is written first and watched failing for the reason it names, before the code that satisfies it exists.

**Shared, `LimeghostSharedTests`, on macOS and on the iPhone simulator:**
- `decide` gives each of its five answers for the navigation that should produce it.
- The session answers WebKit's `preferences:` variant of the policy question, and not the old one.
- `applyContentMode` asks for `.desktop` with the switch on, and leaves `.recommended` alone with it off.
- A session starts with the switch off. It turns on and off.
- The workspace turns the switch in the tab in front.

**Mac, `BrowserBehaviorTests`:**
- `copyConfirmation` is the article's `copyNotice` when the copy is doubtful, and "Copied N words." when it is not.
- Reader's pointer header keeps one row at two Mac widths, and the touch header is taller.

**iPhone, `LimeghostTests`:**
- `PageMenuModel`:
  - On the guide, only New Tab and New Private Tab work.
  - On a page, everything works but Forward.
  - Forward follows the tab.
  - Find waits while Reader is open.
  - The three labels flip.
  - The model reads the tab in front.
- `PageMenuPresentation`: a row closes the sheet before it acts, and acts once; a swipe runs nothing.
- `PageMenuActions`, against a real workspace from `WorkspaceHost.forTesting`:
  - New Private Tab puts a private tab in front.
  - Add Bookmark saves the page and says "Bookmark added."
  - Remove Bookmark removes it and says "Bookmark removed."
  - Request Desktop Site turns the switch on.
  - Find in Page opens the find bar.
  - A copy that did not happen gets no confirmation.
- `FindBar`: the text for each of the three outcomes, and the arrows waiting for a match.
- Reader:
  - The touch header is two 44-point rows at 375, 402 and 428 points wide.
  - `TabSurface` shows Reader over a page while an article is open.
  - Reader never covers the guide.

**Whole:**
- The Mac suite (504 on September 10).
- `LimeghostSharedLayer` on macOS and on the iPhone simulator.
- The app's own suite.
- By hand on the Simulator: every row, each state in the canvas, Share presenting the system sheet, and a site that serves a different desktop layout doing so.
- A reinstall on the founder's iPhone.

**Success criteria for this step:**
1. The menu opens from `•••` on the phone, and every row does what §4 says.
2. On the AI guide, the page rows are greyed and the new-tab rows work.
3. Copy for AI puts on the clipboard the same text that Reader shows, and says so in words.
4. Find in Page never shows a count.
5. All three suites are green, and the Mac's behaviour is unchanged.
6. The documents that describe the phone say what now exists. None of them claims validation.

## 9. Honesty

No observed-user session has been run on either platform. The founder using this on their own phone is dogfooding, and no document may call it validation.
