# Limeghost for iPhone — Bookmarks and History

**Status:** designed with the founder on September 13, 2026. The shape in §2 was approved in conversation, through three answers. Sections 3–8 were written from the recommendations given in that conversation, after the founder said "let's do it", and were not reviewed line by line. §10 lists the judgment calls made while writing them, so any of them can be reversed cheaply.

- It builds on the page menu, [2026-09-12-ios-page-menu-design.md](2026-09-12-ios-page-menu-design.md). That step left Bookmarks and History for this one (its §2) and said that choosing a bookmark's folder "arrives with step 2" (its §4).
- The phone app is described in [docs/ios-browser-foundation.md](../../ios-browser-foundation.md).
- The overall iOS design is [2026-09-03-ios-pocket-browser-design.md](2026-09-03-ios-pocket-browser-design.md). Its v1 table lists "Bookmarks home, folders with the icon catalogue, history home". §9 records how this step amends that.

## 1. What this step adds

- **Two rows in the page menu**, Bookmarks and History, in a third card below the other two.
- **Bookmarks**, a sheet over the page:
  - folders you tap into, in the store's order;
  - search across every folder;
  - a tap opens a bookmark in this tab;
  - touch and hold for Open in New Tab, Rename…, Move to… and Delete;
  - swipe to delete;
  - New Folder.
- **History**, a sheet over the page:
  - visits grouped by day;
  - search;
  - a tap opens a visit in this tab;
  - touch and hold for Open in New Tab and Delete;
  - swipe to delete;
  - Clear History, which asks first.
- **Site icons in both lists.** The phone never handed the icons it captures during visits to its views, so every site icon it drew was the fallback square. This step hands them over, which reaches the AI guide too.

**Not in this step:**

| Left out | Why |
|---|---|
| Choosing a folder's icon or tint | The founder chose no icon picker for now. New folders get the plain folder. |
| Reordering by dragging | Not asked for. Both lists keep the store's order. |
| Editing a bookmark's address | Rename changes the name only. |
| Moving a folder into another folder | Neither platform can: the store has no call for it. |
| Open All in Tabs | Not asked for. |
| Import and export | Step 6. |
| Turning history off | A Settings switch, step 4. |

## 2. Where they live (approved)

- The founder chose **phone-shaped lists that share the Mac's data model**, **a sheet over the page**, and **browse, open, delete and file**.
- The page menu gains a third card: **Bookmarks** (`book`) and **History** (`clock`). Both always work: on the guide, on a page, and in a private tab.
- Choosing one closes the menu first, and the list opens once the menu has gone. That is the menu's existing rule, and SwiftUI presents one sheet at a time anyway.
- The menu grows by one card, about 113 points. On an iPhone SE it no longer fits the screen, and its last card scrolls into view.
- **No new door.** A tap goes through `workspace.open(_:)`, and Open in New Tab through `workspace.open(_:inNewTab: true)`. Those are the door table's "an address or a bookmark" and "a bookmark in a new tab". The Mac's `openBookmarksHome()` and `openHistoryHome()` change a tab's start surface; the phone does not call them.

## 3. Bookmarks

### 3.1 The screens

- A navigation stack in a full-height sheet. The top screen is titled **Bookmarks**; a folder's screen carries the folder's name. Back is the system's.
- Each screen lists the folder's subfolders, then its bookmarks, each in the store's order: `bookmarkFolders(in:)` and `bookmarks(in:)`, the order the Mac shows the same records in. Nothing on the phone reorders, so today that is the order things were added.
- **A folder row:** the folder's own icon (`BookmarkFolderIcon`), its name, and a chevron.
- **A bookmark row:** the site's icon (`SiteIconView`), its name, and its host underneath.
- **Done** closes the sheet, at the top right of every screen. **New Folder** sits in the bottom toolbar of every screen and makes the folder inside the one on screen.
- **Empty:** the top screen says "No Bookmarks Yet" and "Add Bookmark in the menu saves the page you're on." A folder says "This Folder Is Empty" and "To file a bookmark here, touch and hold it, then choose Move to…".

### 3.2 Search

- A search field on the top screen only, always visible: "Search bookmarks".
- While something is typed, the top screen lists two sections: **Folders** whose names match, and **Bookmarks** whose names or addresses match, from every folder. The filters are the Mac's own `BookmarksHomeSearch`, moved to Core (§6).
- A folder in the results opens that folder, and Back returns to the results.
- When nothing matches, the system's "No Results" view.

### 3.3 What a tap does

- **A bookmark** opens in this tab, and the sheet closes.
- **Open in New Tab** puts a new tab in front, private if the tab in front is private (the shared rule), and the sheet closes.
- **A folder** opens.

### 3.4 Filing

- **Delete a bookmark:** swipe, or touch and hold → Delete Bookmark. It goes at once, as on the Mac (`removeBookmark`).
- **Delete a folder:** swipe, or touch and hold → Delete Folder.
  - An empty folder goes at once.
  - A folder holding anything asks first, in the Mac's words: "Delete folder?", then "‹name› contains saved items. Its bookmarks and subfolders will move to the parent folder; nothing will be deleted." `deleteBookmarkFolderPreservingContents` does exactly that.
  - A full swipe never deletes a folder.
- **Rename…:** an alert with a text field holding the current name, and Cancel / Save.
  - A bookmark keeps its address and folder (`updateBookmark(id:title:url:)`). An empty name becomes the site's host: the store's rule.
  - A folder keeps its icon and tint (`updateBookmarkFolder`, handed the folder's own values). An empty name leaves the old one: the store's rule.
- **Move to…** (bookmarks only): a sheet listing **Bookmarks**, the top level, then every folder, indented under its parent and alphabetical within it (Core's `BookmarkTree.rows`, everything expanded). The bookmark's current place has a checkmark. A tap moves the bookmark to the end of that folder (`moveBookmark(_:to:)`) and closes the sheet. Cancel closes it.
- **New Folder:** an alert with an empty text field, and Cancel / Create. The folder joins the end of the folder on screen, with the plain folder icon (`LimeghostIconCatalog.defaultIconID`) and no tint. An empty name makes a folder called "New Folder".
- **Add Bookmark stays one tap**, to the top level, as the page menu shipped it. Its folder is chosen afterwards with Move to…, which is how the page menu's promise is kept.

### 3.5 Folder icons

`LimeghostIconView.swift` joins the phone's build by reference, as the September 3 spec planned. It is the seventh Mac file the phone compiles. Folders made on the phone draw the plain folder; folders that arrive by import will draw their own icons and tints.

## 4. History

- A navigation stack in a full-height sheet, titled **History**, with Done.
- Visits grouped by day with Core's `HistoryDayGrouping`: Today, Yesterday, then the date, newest first. Each day is a section.
- **A row:** the site's icon, the page's title (its address when it has none), and "14:05 · example.com" underneath.
- **Search:** always visible, "Search history". The Mac's `HistoryHomeSearch`, moved to Core, filters before grouping. When nothing matches, "No Results".
- **A tap** opens the visit in this tab, and the sheet closes. **Touch and hold:** Open in New Tab, Delete. **Swipe:** Delete (`removeHistory`). One visit goes without asking, as on the Mac.
- **Clear History**, in the bottom toolbar while there is any history (as on the Mac), asks first:
  - "Clear all local history?"
  - "This removes 42 stored visits from this device and cannot be undone. Your bookmarks and open tabs are not affected."
  - **Clear History**, destructive, and Cancel.
  - It says "this device" rather than "this iPhone", because the target also builds for iPad. Unlike the Mac's, it does not mention downloaded files: the phone has none.
- **A footnote under the list:** "Stored only on this device. Private tabs are never recorded." Both are true. The workspace records a visit only when its tab is not private, and history never syncs (September 3 spec, §1).
- **Empty:** "No History Yet" and "Pages you visit appear here. Private tabs are never recorded."
- **History works in a private tab**, as on the Mac, where a private window can open History. What a private tab refuses is *completing an address* from history, which would put history on screen unasked.

## 5. The look

Both sheets draw on Limeghost's surfaces, like the menu they open from. A white sheet opening out of the dark menu would look broken.

- `.presentationBackground(LimeghostTheme.bg1)`, list rows on `bg2`, text in `textPrimary`, second lines in `textTertiary`.
- The sheets ask for the dark appearance (`.preferredColorScheme(.dark)`), so the system's own parts match the surfaces: navigation bar, search field, swipe buttons, alerts and menus. The rest of the app still follows the system; "the look" (step 5) decides that.
- Controls take the accent (`.tint(LimeghostTheme.accent)`). Destructive buttons keep the system's red.
- Icons at `LimeghostTheme.siteIconSize`, the one size for every site icon and folder mark.

## 6. Shared changes

- **`BookmarksHomeSearch` and `HistoryHomeSearch` move to Core**, unchanged, into `LimeghostCore/BookmarkAndHistorySearch.swift`, and become public. They are pure Foundation filters that lived inside the Mac's two page files. The phone needs the same filters, and a second copy is how two platforms come to disagree about what a search finds.
- **Their two tests move with them**, from `BrowserBehaviorTests` to `LimeghostCoreTests`, so they now run on the simulator as well. The Mac's total stays 517:
  - `BrowserBehaviorTests` goes from 251 to 249;
  - `LimeghostCoreTests` from 236 to 238;
  - `LimeghostSharedLayer` from 266 to 268.
- Nothing changes in `LimeghostShared`: no store call, no workspace method, no door.

## 7. Architecture

**The page menu** (`ios/Sources/PageMenu.swift`)
- `PageMenuItem` gains `bookmarks` and `history`, and the view a third card.
- A new `PageMenuDestination`, with `bookmarks` and `history`.
- `PageMenuPresentation.didDismiss()` returns nil for those two rows and sets `destination` instead. `BrowserScreen` presents `.sheet(item: $menu.destination)`.
- `PageMenuActions.perform` does nothing for them.

**Bookmarks** (`ios/Sources/BookmarksSheet.swift`, new)
- `BookmarksModel`: a `@MainActor` struct around the workspace, like `TabSwitcherModel`. It answers titles, listings and searches, and holds the two doors and every filing call.
- `BookmarkNameEdit`: a new folder, or a rename. It carries the alert's title, button and starting text, and what the button does.
- `BookmarksSheet`: the stack, the search field and the look. `BookmarkFolderScreen`: one folder's list, with its swipe actions, menus, alerts and the Move to… sheet.

**Move to…** (`ios/Sources/BookmarkMovePicker.swift`, new)
- `BookmarkDestination` and `BookmarkDestinations.rows(folders:)`: pure, built from `BookmarkTree.rows`.
- `BookmarkMovePicker`: the list.

**History** (`ios/Sources/HistorySheet.swift`, new)
- `HistoryModel`: the days matching a query (calendar and "now" injectable, as Core's grouping allows), the two doors, delete and clear.
- `HistoryWording`: the confirmation, the footnote, and a row's title and detail.
- `HistorySheet`: the view.

**Wiring** (`ios/Sources/BrowserScreen.swift`)
- The destination sheet.
- `.environment(\.faviconStore, host.workspace.favicons)` on the screen, which the guide and every sheet inherit.

**By reference:** `LimeghostIconView.swift`, in the "Reused from macOS" group.

## 8. Testing

Tests call the models against `WorkspaceHost.forTesting`, as `PageMenuTests` does. SwiftUI views are not unit-tested; they are checked by eye.

**The page menu** (`PageMenuTests`)
- On the guide, New Tab, New Private Tab, Bookmarks and History work. This replaces `testOnTheGuideOnlyTheNewTabRowsWork`.
- Choosing Bookmarks closes the menu, and opens Bookmarks only once the menu has gone. The same for History. No other row sets a destination.
- The two rows' titles and symbols.

**Bookmarks** (`BookmarksSheetTests`, new)
- The top screen is "Bookmarks"; a folder's screen carries its name.
- A folder lists its subfolders, then its bookmarks, in the store's order. The test rearranges them with `moveBookmark(_:toIndex:)` first, so it proves the order is the store's and not the order of creation.
- Search from the top finds a bookmark filed two folders deep, by its address.
- Opening a bookmark on the guide loads it in the tab in front and uncovers the page; no tab is added.
- Open in New Tab puts a new tab in front, holding the bookmark.
- Deleting a bookmark removes it.
- An empty folder does not ask before it is deleted. A folder holding a bookmark does, and deleting it moves the bookmark up a level.
- Renaming a bookmark keeps its address and folder.
- Renaming a folder keeps its icon and tint.
- Move to… files a bookmark in a folder, and back at the top level.
- New Folder makes a folder inside the one on screen, with the plain icon. An empty name makes "New Folder".
- `BookmarkNameEdit`'s three cases: their titles, buttons and starting text, and that each one's button does its own job.
- Move to…'s rows: the top level first, then parents before children, alphabetical, indented by depth.

**History** (`HistorySheetTests`, new)
- Visits come back as days, newest first, filtered by the query before grouping.
- Opening a visit loads it in the tab in front. Open in New Tab adds a tab.
- Delete removes one visit. Clear removes them all. Clear History is offered only while there is history.
- The confirmation counts visits ("1 stored visit", "3 stored visits"), names this device, and never names the Mac.
- A row's title falls back to the address.

**Core** (`BookmarkAndHistorySearchTests`): the two moved tests, unchanged.

**By hand, on the phone** (listed, not yet run):
- Menu → Bookmarks, and Menu → History, each open once the menu has gone. Done closes them.
- Into a folder and back. New Folder. Rename…. Move to…. Swipe to delete.
- Deleting a folder that holds a bookmark asks, and the bookmark appears one level up.
- History's day sections, search, swipe, and Clear History asking first.
- After visiting a site, its icon shows in both lists instead of a coloured square.
- At iPhone SE size, the menu scrolls to its last card.

## 9. Amending the September 3 spec

That spec's component table planned `BookmarksHomePage` and `HistoryHomePage` as "referenced by path in v1, not moved". The founder chose phone-shaped lists instead. The Mac pages are a 250-point sidebar beside a column up to 1,020 points wide. The phone keeps their data, filters and grouping, not their layout. `LimeghostIconView` is referenced by path as planned. `LimeghostIconPicker` waits until the phone chooses icons.

## 10. Judgment calls

Made while writing this, without asking the founder. Each is small to reverse.

1. The Bookmarks and History card comes last in the menu, nearest the thumb, rather than first as in Chrome.
2. A folder holding anything asks before it is deleted. A bookmark or a single visit never does. Both are the Mac's rules.
3. A new folder left unnamed is called "New Folder".
4. Rename changes the name only.
5. Move to… lists folders alphabetically, as the Mac's tree and Move menu do, rather than in stored order.
6. Add Bookmark stays one tap; its folder is chosen afterwards with Move to….
7. History stays available in a private tab, as on the Mac.
8. The two sheets are dark, like the menu, until step 5.
9. Captured site icons reach every phone view, the guide included.
10. Search lives on the top Bookmarks screen only. A folder found there opens on its own, and Back returns to the results.
11. Folder rows show no counts.

## 11. Honesty

- Nothing here has been validated with an observed user.
- **The phone's bookmarks and history are the phone's own.** Nothing from the Mac appears on the phone until import (step 6) or iCloud sync (after Developer Program enrolment). The empty states describe this device and imply nothing more.
- The by-hand checks in §8 are listed, not claimed.
