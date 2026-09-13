# Limeghost for iPhone — Bookmarks and History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two rows in the phone's page menu, Bookmarks and History, each opening a sheet over the page. Bookmarks drills into folders and can open, delete, rename, move and create. History lists visits by day and can open, delete and clear.

**Architecture:** Every screen reads the Mac's own `BrowserDataStore` and opens pages through `BrowserWorkspace.open(_:inNewTab:)`, a door that already exists. A `@MainActor` model struct per sheet holds what the sheet shows and does, so tests call it without SwiftUI, the shape `TabSwitcherModel` and `PageMenuActions` already have. The Mac's two search filters move into `LimeghostCore`, so both platforms share one copy.

**Tech Stack:** SwiftUI (iOS 17: `NavigationStack`, `List`, `.searchable`, `.swipeActions`, `.contextMenu`, `ContentUnavailableView`), XCTest, SwiftPM (`LimeghostCore`, `LimeghostShared`), `ios/Limeghost.xcodeproj`.

**Spec:** [docs/superpowers/specs/2026-09-13-ios-bookmarks-history-design.md](../specs/2026-09-13-ios-bookmarks-history-design.md). Read it first; this plan argues from it.

## Global Constraints

- iOS deployment target 17.0, Swift 5 language mode. The Mac package's deployment target is macOS 14.
- No `#if os` in `LimeghostShared`. This plan does not touch that target.
- Colours come from `LimeghostTheme`. The one exception is a destructive swipe button's red, which is the system's destructive colour, not a brand colour.
- The phone opens pages only through `workspace.open(_:)` and `workspace.open(_:inNewTab: true)`: "an address or a bookmark" and "a bookmark in a new tab" in `testEveryWayOfAskingForAPageUncoversIt`. No new door, and never a session load directly.
- `DEVELOPMENT_TEAM` stays `""` in `project.pbxproj`. Never write a team ID into the repository.
- Storage identifiers (`com.clearframe.browser`, `clearframe.*`) are not touched.
- Phone labels use title case ("Open in New Tab", "Delete Folder"), as `PageMenuModel.title` does.
- A folder or bookmark name reaches `Text` as a `String` value, never interpolated into a string literal, so a name holding `*` or `_` is not read as Markdown.
- Watch each new test fail before its code exists, and break the fix on purpose once to see the test fail for its own reason.
- Never describe anything as validated with users. By-hand checks are listed, not claimed, until they have been done.
- Commit messages end with:
  ```
  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_014pJsUVUWJsmR3Xca4A1Tso
  ```
- Push directly to `feature/ios-pocket-browser` after each commit.

**Commands** (run from the worktree root unless stated):

- Mac package: `cd macos/LimeghostBrowser && swift test 2>&1 | grep -E "Executed [0-9]+ test|error:|failed \("`
- Mac test counts: `cd macos/LimeghostBrowser && swift test --list-tests 2>/dev/null | cut -d. -f1 | sort | uniq -c`
- Phone: `cd ios && xcodebuild test -scheme Limeghost -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|\*\* TEST|Executed [0-9]+ test|failed \("`
- Phone, one class: add `-only-testing:LimeghostTests/<ClassName>` to the line above.
- Shared layer on the simulator: `cd macos/LimeghostBrowser && xcodebuild test -scheme LimeghostSharedLayer -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|\*\* TEST"`

**Adding a file to the Xcode project.** Save this helper once, as `$TMPDIR/pbx_add.py`. It inserts the four entries a Swift file needs: build file, file reference, group child and Sources phase. Each goes directly after the matching entry for an existing file, keeping the tab indentation. It refuses an ID already in use.

```python
#!/usr/bin/env python3
"""pbx_add.py NAME PATH FILE_REF_ID BUILD_FILE_ID AFTER_NAME"""
import pathlib, sys

pbx = pathlib.Path("ios/Limeghost.xcodeproj/project.pbxproj")
name, path, ref, build, after = sys.argv[1:6]
text = pbx.read_text()
for identifier in (ref, build):
    if identifier in text:
        sys.exit(f"{identifier} is already used")
path_value = f'"{path}"' if "/" in path else path
lines = text.split("\n")

def insert_after(matches, new_line):
    for index, line in enumerate(lines):
        if matches(line):
            lines.insert(index + 1, new_line)
            return
    sys.exit(f"no anchor for: {new_line.strip()}")

insert_after(lambda l: f"/* {after} in Sources */ = {{isa = PBXBuildFile" in l,
             f"\t\t{build} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};")
insert_after(lambda l: f"/* {after} */ = {{isa = PBXFileReference" in l,
             f"\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {path_value}; sourceTree = \"<group>\"; }};")
insert_after(lambda l: l.strip().endswith(f"/* {after} */,"),
             f"\t\t\t\t{ref} /* {name} */,")
insert_after(lambda l: l.strip().endswith(f"/* {after} in Sources */,"),
             f"\t\t\t\t{build} /* {name} in Sources */,")
pbx.write_text("\n".join(lines))
print("added", name)
```

**Project IDs this plan uses** (all checked unused on September 13, 2026):

| File | File reference | Build file |
|---|---|---|
| `BookmarksSheet.swift` | `AA0000000000000000000211` | `AA0000000000000000000110` |
| `BookmarksSheetTests.swift` | `AA000000000000000000220A` | `AA000000000000000000210A` |
| `SheetLook.swift` | `AA0000000000000000000210` | `AA000000000000000000010F` |
| `BookmarkMovePicker.swift` | `AA0000000000000000000212` | `AA0000000000000000000111` |
| `BookmarkMovePickerTests.swift` | `AA000000000000000000220B` | `AA000000000000000000210B` |
| `LimeghostIconView.swift` (by reference) | `AA0000000000000000000668` | `AA0000000000000000000678` |
| `HistorySheet.swift` | `AA0000000000000000000213` | `AA0000000000000000000112` |
| `HistorySheetTests.swift` | `AA000000000000000000220C` | `AA000000000000000000210C` |

**Counts before this plan** (measured with `swift test --list-tests` on September 13, 2026): Mac 517 = `LimeghostCoreTests` 236 + `LimeghostSharedTests` 30 + `BrowserBehaviorTests` 251. `LimeghostSharedLayer` 266. Phone 50.

**Counts after it:** Mac 517 = 238 + 30 + 249. `LimeghostSharedLayer` 268. Phone 73.

## File Structure

| File | Responsibility |
|---|---|
| `macos/LimeghostBrowser/Sources/LimeghostCore/BookmarkAndHistorySearch.swift` (new) | `BookmarksHomeSearch` and `HistoryHomeSearch`, public, moved unchanged from the Mac's page files |
| `macos/LimeghostBrowser/Tests/LimeghostCoreTests/BookmarkAndHistorySearchTests.swift` (new) | Their two tests, moved unchanged from `BrowserBehaviorTests` |
| `ios/Sources/BookmarksSheet.swift` (new) | `BookmarksModel`, `BookmarkNameEdit`, `BookmarksSheet`, `BookmarkFolderScreen` |
| `ios/Sources/BookmarkMovePicker.swift` (new) | `BookmarkDestination`, `BookmarkDestinations`, `BookmarkMovePicker` |
| `ios/Sources/SheetLook.swift` (new) | `View.limeghostListSheet()`: the sheets' surfaces, dark appearance and accent |
| `ios/Sources/HistorySheet.swift` (new) | `HistoryModel`, `HistoryWording`, `HistorySheet` |
| `ios/Sources/PageMenu.swift` | Two new rows, a third card, `PageMenuDestination`, `PageMenuPresentation.destination` |
| `ios/Sources/BrowserScreen.swift` | Presents the destination sheet; hands the favicon store to every view |
| `ios/Tests/BookmarksSheetTests.swift`, `BookmarkMovePickerTests.swift`, `HistorySheetTests.swift` (new), `PageMenuTests.swift` | Model tests |
| `ios/Limeghost.xcodeproj/project.pbxproj` | The new files, and `LimeghostIconView.swift` by reference |

---

### Task 1: One search filter for both platforms

**Files:**
- Create: `macos/LimeghostBrowser/Sources/LimeghostCore/BookmarkAndHistorySearch.swift`
- Create: `macos/LimeghostBrowser/Tests/LimeghostCoreTests/BookmarkAndHistorySearchTests.swift`
- Modify: `macos/LimeghostBrowser/Sources/LimeghostBrowser/BookmarksHomePage.swift` (delete `enum BookmarksHomeSearch` and its doc comment)
- Modify: `macos/LimeghostBrowser/Sources/LimeghostBrowser/HistoryHomePage.swift` (delete `enum HistoryHomeSearch` and its doc comment)
- Modify: `macos/LimeghostBrowser/Tests/BrowserBehaviorTests/BrowserBehaviorTests.swift` (delete `testHistoryHomeSearchMatchesTitlesAndAddresses` and `testBookmarksHomeSearchMatchesFolderTitlesAndBookmarkTitlesOrAddresses`)

**Interfaces:**
- Produces: `public enum BookmarksHomeSearch { public static func folders(_: [BookmarkFolderRecord], matching: String) -> [BookmarkFolderRecord]; public static func bookmarks(_: [BookmarkRecord], matching: String) -> [BookmarkRecord] }` and `public enum HistoryHomeSearch { public static func visits(_: [HistoryRecord], matching: String) -> [HistoryRecord] }` in `LimeghostCore`.

- [ ] **Step 1: Write the tests in their new home**

Create `macos/LimeghostBrowser/Tests/LimeghostCoreTests/BookmarkAndHistorySearchTests.swift`:

```swift
import Foundation
import XCTest
@testable import LimeghostCore

/// The search filters both platforms share: the Mac's bookmarks and history
/// homes, and the phone's Bookmarks and History sheets. Moved here from
/// `BrowserBehaviorTests` with the filters themselves on September 13, 2026,
/// so they run on the simulator as well as the Mac.
final class BookmarkAndHistorySearchTests: XCTestCase {
    func testHistoryHomeSearchMatchesTitlesAndAddresses() {
        let visits = [
            HistoryRecord(title: "Garlic Chilli", url: "https://recipes.example/garlic"),
            HistoryRecord(title: "Swift Forums", url: "https://forums.swift.org/thread"),
            HistoryRecord(title: "", url: "https://example.com/untitled")
        ]

        XCTAssertEqual(HistoryHomeSearch.visits(visits, matching: "").count, 3, "an empty query keeps everything")
        XCTAssertEqual(HistoryHomeSearch.visits(visits, matching: "   ").count, 3, "so does whitespace")
        XCTAssertEqual(HistoryHomeSearch.visits(visits, matching: "garlic").map(\.title), ["Garlic Chilli"])
        XCTAssertEqual(
            HistoryHomeSearch.visits(visits, matching: "SWIFT.ORG").map(\.title), ["Swift Forums"],
            "the address matches too, case-insensitively"
        )
        XCTAssertEqual(HistoryHomeSearch.visits(visits, matching: "untitled").count, 1, "a visit with no title is still findable")
        XCTAssertTrue(HistoryHomeSearch.visits(visits, matching: "nothing here").isEmpty)
    }

    func testBookmarksHomeSearchMatchesFolderTitlesAndBookmarkTitlesOrAddresses() {
        let folders = [
            BookmarkFolderRecord(title: "Web Design", emoji: "🎨"),
            BookmarkFolderRecord(title: "Programming", emoji: "💻"),
            BookmarkFolderRecord(title: "Shopping", emoji: "🛍️")
        ]
        let bookmarks = [
            BookmarkRecord(title: "Swift documentation", url: "https://swift.org/documentation/"),
            BookmarkRecord(title: "Colour palettes", url: "https://example.com/palette")
        ]

        XCTAssertEqual(BookmarksHomeSearch.folders(folders, matching: "desi").map(\.title), ["Web Design"])
        XCTAssertEqual(BookmarksHomeSearch.folders(folders, matching: "PROGRAM").map(\.title), ["Programming"])
        XCTAssertTrue(BookmarksHomeSearch.folders(folders, matching: "photography").isEmpty)
        XCTAssertEqual(
            BookmarksHomeSearch.folders(folders, matching: "   ").count,
            folders.count,
            "a blank query filters nothing out"
        )

        XCTAssertEqual(BookmarksHomeSearch.bookmarks(bookmarks, matching: "SWIFT").map(\.title), ["Swift documentation"])
        XCTAssertEqual(
            BookmarksHomeSearch.bookmarks(bookmarks, matching: "example.com").map(\.title),
            ["Colour palettes"],
            "the web address matches as well as the title"
        )
        XCTAssertTrue(BookmarksHomeSearch.bookmarks(bookmarks, matching: "no such page").isEmpty)
        XCTAssertEqual(BookmarksHomeSearch.bookmarks(bookmarks, matching: "").count, bookmarks.count)
    }
}
```

These are the two existing test bodies, unchanged. Then delete both methods from `BrowserBehaviorTests.swift`, so neither test runs twice.

- [ ] **Step 2: Watch them fail where they now live**

Run: `cd macos/LimeghostBrowser && swift build --build-tests 2>&1 | grep -E "error:" | head -3`
Expected: `BookmarkAndHistorySearchTests.swift` fails with `error: cannot find 'HistoryHomeSearch' in scope`. `LimeghostCoreTests` cannot see a type that lives in `LimeghostBrowser`.

- [ ] **Step 3: Move the filters**

Create `macos/LimeghostBrowser/Sources/LimeghostCore/BookmarkAndHistorySearch.swift`:

```swift
import Foundation

/// Filtering bookmarks by what was typed. The Mac's bookmarks home and the
/// phone's Bookmarks sheet both search through this, so the two platforms
/// cannot come to disagree about what a search finds.
///
/// Pure and static, so it is tested without a view. Matching mirrors the
/// organizer: case-insensitive `contains` on the page title and web address,
/// plus the folder title.
public enum BookmarksHomeSearch {
    public static func folders(_ folders: [BookmarkFolderRecord], matching query: String) -> [BookmarkFolderRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return folders }
        return folders.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    public static func bookmarks(_ bookmarks: [BookmarkRecord], matching query: String) -> [BookmarkRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return bookmarks }
        return bookmarks.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || $0.url.localizedCaseInsensitiveContains(trimmed)
        }
    }
}

/// Filtering history by what was typed, for the Mac's history home and the
/// phone's History sheet alike. Pure and static, so it is tested without a
/// view.
public enum HistoryHomeSearch {
    public static func visits(_ visits: [HistoryRecord], matching search: String) -> [HistoryRecord] {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return visits }
        return visits.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) || $0.url.localizedCaseInsensitiveContains(trimmed)
        }
    }
}
```

Delete the old declarations:
- From `HistoryHomePage.swift`, the block from `/// Filtering history by what was typed. Pure and static so it can be tested` through the closing brace of `enum HistoryHomeSearch`.
- From `BookmarksHomePage.swift`, the block from `/// Pure filters behind the bookmarks-home search field, kept separate from the` through the closing brace of `enum BookmarksHomeSearch`.

Both files already `import LimeghostCore`, so their call sites compile unchanged.

- [ ] **Step 4: Run the moved tests, then everything**

Run: `cd macos/LimeghostBrowser && swift test --filter BookmarkAndHistorySearchTests 2>&1 | grep -E "Executed [0-9]+ test|error:"`
Expected: `Executed 2 tests, with 0 failures`.

Run: `cd macos/LimeghostBrowser && swift test 2>&1 | grep -E "Executed [0-9]+ test|error:|failed \("`
Expected: `Executed 517 tests, with 0 failures` (2–4 skipped).

Run the counts command. Expected: `LimeghostCoreTests` 238, `LimeghostSharedTests` 30, `BrowserBehaviorTests` 249.

- [ ] **Step 5: Commit**

```bash
git add macos/LimeghostBrowser/Sources/LimeghostCore/BookmarkAndHistorySearch.swift \
  macos/LimeghostBrowser/Tests/LimeghostCoreTests/BookmarkAndHistorySearchTests.swift \
  macos/LimeghostBrowser/Sources/LimeghostBrowser/BookmarksHomePage.swift \
  macos/LimeghostBrowser/Sources/LimeghostBrowser/HistoryHomePage.swift \
  macos/LimeghostBrowser/Tests/BrowserBehaviorTests/BrowserBehaviorTests.swift
git commit -m "Move the bookmark and history search filters into Core"   # plus the attribution lines
git push origin feature/ios-pocket-browser
```

---

### Task 2: What Bookmarks shows and does

**Files:**
- Create: `ios/Sources/BookmarksSheet.swift`
- Create: `ios/Tests/BookmarksSheetTests.swift`
- Modify: `ios/Limeghost.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `BookmarksHomeSearch` (Task 1); `BrowserDataStore`'s `bookmarkFolder(id:)`, `bookmarkFolders(in:)`, `bookmarks(in:)`, `bookmarkFolders`, `bookmarks`, `removeBookmark(_:)`, `bookmarkFolderContainsItems(_:)`, `deleteBookmarkFolderPreservingContents(_:)`, `updateBookmark(id:title:url:)`, `updateBookmarkFolder(id:title:iconID:colorID:)`, `moveBookmark(_:to:)`, `createBookmarkFolder(title:iconID:colorID:parentID:)`; `BrowserWorkspace.open(_:inNewTab:)`.
- Produces:
  - `@MainActor struct BookmarksModel { let workspace: BrowserWorkspace }` with `title(of: UUID?) -> String`, `folders(in: UUID?) -> [BookmarkFolderRecord]`, `bookmarks(in: UUID?) -> [BookmarkRecord]`, `folders(matching: String) -> [BookmarkFolderRecord]`, `bookmarks(matching: String) -> [BookmarkRecord]`, `open(_: BookmarkRecord, inNewTab: Bool = false)`, `delete(_: BookmarkRecord)`, `deletingAsksFirst(_: BookmarkFolderRecord) -> Bool`, `delete(_: BookmarkFolderRecord)`, `rename(_: BookmarkRecord, to: String)`, `rename(_: BookmarkFolderRecord, to: String)`, `move(_: BookmarkRecord, to: UUID?)`, `@discardableResult createFolder(named: String, in: UUID?) -> BookmarkFolderRecord?`.
  - `enum BookmarkNameEdit { case newFolder(parentID: UUID?), renameFolder(BookmarkFolderRecord), renameBookmark(BookmarkRecord) }` with `title`, `confirmLabel`, `startingName` (all `String`) and `@MainActor func commit(_ name: String, with model: BookmarksModel)`.

- [ ] **Step 1: Write the failing tests**

Create `ios/Tests/BookmarksSheetTests.swift`:

```swift
import XCTest
import LimeghostCore
@testable import Limeghost
@testable import LimeghostShared

@MainActor
final class BookmarksSheetTests: XCTestCase {
    /// A suite of its own, emptied afterwards, for the reason
    /// `StartSurfaceTests.makeHost()` gives: these tests run inside the app.
    private func makeHost() throws -> WorkspaceHost {
        let suiteName = "clearframe.iosBookmarks.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return WorkspaceHost.forTesting(defaults: defaults)
    }

    // MARK: - What it lists

    /// The top level is "Bookmarks"; a folder's screen carries its own name.
    func testScreensAreTitledByTheirFolder() throws {
        let host = try makeHost()
        let recipes = try host.workspace.dataStore.folder(named: "Recipes")
        let model = BookmarksModel(workspace: host.workspace)

        XCTAssertEqual(model.title(of: nil), "Bookmarks")
        XCTAssertEqual(model.title(of: recipes.id), "Recipes")
    }

    /// A folder lists what the store holds in it, in the store's order. The
    /// pages are rearranged before reading, so the order is provably the
    /// store's and not simply the order they were made in.
    func testAFolderListsWhatTheStoreHoldsInTheStoresOrder() throws {
        let host = try makeHost()
        let store = host.workspace.dataStore
        let recipes = try store.folder(named: "Recipes")
        let soups = try store.folder(named: "Soups", in: recipes.id)
        let bread = try store.page("Bread", at: "https://example.com/bread", in: recipes.id)
        let cake = try store.page("Cake", at: "https://example.com/cake", in: recipes.id)
        store.moveBookmark(cake.id, toIndex: 0)
        let model = BookmarksModel(workspace: host.workspace)

        XCTAssertEqual(model.folders(in: recipes.id).map(\.id), [soups.id])
        XCTAssertEqual(model.bookmarks(in: recipes.id).map(\.id), [cake.id, bread.id])
        XCTAssertEqual(model.folders(in: nil).map(\.id), [recipes.id], "a subfolder is not listed at the top")
    }

    /// Search looks through every folder, not only the one on screen: a page
    /// filed two folders down is found from the top, by its address.
    func testSearchFindsABookmarkFiledTwoFoldersDown() throws {
        let host = try makeHost()
        let store = host.workspace.dataStore
        let recipes = try store.folder(named: "Recipes")
        let soups = try store.folder(named: "Soups", in: recipes.id)
        _ = try store.page("Leek and potato", at: "https://soups.example/leek", in: soups.id)
        let model = BookmarksModel(workspace: host.workspace)

        XCTAssertEqual(model.bookmarks(matching: "SOUPS.EXAMPLE").map(\.title), ["Leek and potato"])
        XCTAssertEqual(model.folders(matching: "soup").map(\.title), ["Soups"])
    }

    // MARK: - What a tap does

    /// A bookmark opens in the tab in front. On the guide, that uncovers the
    /// page: no tab is added, and the guide steps aside for what was asked for.
    func testOpeningABookmarkLoadsItInTheTabInFront() throws {
        let host = try makeHost()
        let bookmark = try host.workspace.dataStore.page("Example", at: "https://example.com/saved")
        let tab = try XCTUnwrap(host.workspace.selectedTab)
        let tabsBefore = host.workspace.visibleTabs.count

        BookmarksModel(workspace: host.workspace).open(bookmark)

        XCTAssertEqual(host.workspace.visibleTabs.count, tabsBefore)
        XCTAssertEqual(host.workspace.selectedTab?.id, tab.id)
        XCTAssertEqual(tab.session.currentURLString, "https://example.com/saved")
        XCTAssertFalse(TabSurface(tab: tab, workspace: host.workspace).showsTheGuide)
    }

    /// Open in New Tab puts a new tab in front, holding the bookmark.
    func testOpenInNewTabPutsANewTabInFront() throws {
        let host = try makeHost()
        let bookmark = try host.workspace.dataStore.page("Example", at: "https://example.com/saved")
        let firstTab = try XCTUnwrap(host.workspace.selectedTab)
        let tabsBefore = host.workspace.visibleTabs.count

        BookmarksModel(workspace: host.workspace).open(bookmark, inNewTab: true)

        XCTAssertEqual(host.workspace.visibleTabs.count, tabsBefore + 1)
        XCTAssertNotEqual(host.workspace.selectedTab?.id, firstTab.id)
        XCTAssertEqual(host.workspace.selectedTab?.session.currentURLString, "https://example.com/saved")
    }

    // MARK: - Filing

    func testDeletingABookmarkRemovesIt() throws {
        let host = try makeHost()
        let store = host.workspace.dataStore
        let bookmark = try store.page("Example", at: "https://example.com/saved")

        BookmarksModel(workspace: host.workspace).delete(bookmark)

        XCTAssertFalse(store.isBookmarked("https://example.com/saved"))
    }

    /// An empty folder has nothing to lose, so it goes without asking. A
    /// folder holding a page asks first, and deleting it still loses nothing:
    /// the page moves up to where the folder was.
    func testAFolderAsksBeforeDeletingOnlyWhenItHoldsSomething() throws {
        let host = try makeHost()
        let store = host.workspace.dataStore
        let empty = try store.folder(named: "Empty")
        let recipes = try store.folder(named: "Recipes")
        let bread = try store.page("Bread", at: "https://example.com/bread", in: recipes.id)
        let model = BookmarksModel(workspace: host.workspace)

        XCTAssertFalse(model.deletingAsksFirst(empty))
        XCTAssertTrue(model.deletingAsksFirst(recipes))

        model.delete(recipes)

        XCTAssertNil(store.bookmarkFolder(id: recipes.id))
        XCTAssertEqual(
            store.bookmarks(in: nil).map(\.id), [bread.id],
            "the page moved up a level rather than going with its folder"
        )
    }

    /// Rename changes the name only: the address and the folder stay.
    func testRenamingABookmarkKeepsItsAddressAndFolder() throws {
        let host = try makeHost()
        let store = host.workspace.dataStore
        let recipes = try store.folder(named: "Recipes")
        let bread = try store.page("Bread", at: "https://example.com/bread", in: recipes.id)

        BookmarksModel(workspace: host.workspace).rename(bread, to: "Sourdough")

        let renamed = try XCTUnwrap(store.bookmark(for: "https://example.com/bread"))
        XCTAssertEqual(renamed.title, "Sourdough")
        XCTAssertEqual(renamed.id, bread.id)
        XCTAssertEqual(renamed.folderID, recipes.id)
    }

    /// The store's folder update takes an icon and a tint as well as a name.
    /// A rename hands it the folder's own, so both survive.
    func testRenamingAFolderKeepsItsIconAndTint() throws {
        let host = try makeHost()
        let store = host.workspace.dataStore
        let travel = try XCTUnwrap(store.createBookmarkFolder(title: "Travel", iconID: "palette", colorID: "amber", parentID: nil))

        BookmarksModel(workspace: host.workspace).rename(travel, to: "Holidays")

        let renamed = try XCTUnwrap(store.bookmarkFolder(id: travel.id))
        XCTAssertEqual(renamed.title, "Holidays")
        XCTAssertEqual(renamed.iconID, "palette")
        XCTAssertEqual(renamed.colorID, "amber")
    }

    /// Move to… files a bookmark in a folder, and back at the top level.
    func testMoveToFilesABookmarkAndBringsItBack() throws {
        let host = try makeHost()
        let store = host.workspace.dataStore
        let recipes = try store.folder(named: "Recipes")
        let bread = try store.page("Bread", at: "https://example.com/bread")
        let model = BookmarksModel(workspace: host.workspace)

        model.move(bread, to: recipes.id)
        XCTAssertEqual(store.bookmarks(in: recipes.id).map(\.id), [bread.id])

        model.move(try XCTUnwrap(store.bookmark(for: bread.url)), to: nil)
        XCTAssertEqual(store.bookmarks(in: nil).map(\.id), [bread.id])
        XCTAssertTrue(store.bookmarks(in: recipes.id).isEmpty)
    }

    /// New Folder makes a folder inside the one on screen, drawn with the
    /// plain folder. Left unnamed, it is called "New Folder".
    func testNewFolderLandsInsideTheFolderOnScreen() throws {
        let host = try makeHost()
        let recipes = try host.workspace.dataStore.folder(named: "Recipes")
        let model = BookmarksModel(workspace: host.workspace)

        let soups = try XCTUnwrap(model.createFolder(named: "  Soups ", in: recipes.id))
        let unnamed = try XCTUnwrap(model.createFolder(named: "   ", in: nil))

        XCTAssertEqual(soups.title, "Soups")
        XCTAssertEqual(soups.parentID, recipes.id)
        XCTAssertEqual(soups.iconID, LimeghostIconCatalog.defaultIconID)
        XCTAssertNil(soups.colorID)
        XCTAssertEqual(unnamed.title, "New Folder")
        XCTAssertNil(unnamed.parentID)
    }

    // MARK: - The name alert

    /// Each case says what it is for, starts from the right text, and its
    /// button does its own job.
    func testTheNameAlertSaysWhatItIsForAndDoesIt() throws {
        let host = try makeHost()
        let store = host.workspace.dataStore
        let recipes = try store.folder(named: "Recipes")
        let bread = try store.page("Bread", at: "https://example.com/bread")
        let model = BookmarksModel(workspace: host.workspace)

        let newFolder = BookmarkNameEdit.newFolder(parentID: recipes.id)
        XCTAssertEqual(newFolder.title, "New Folder")
        XCTAssertEqual(newFolder.confirmLabel, "Create")
        XCTAssertEqual(newFolder.startingName, "")
        newFolder.commit("Soups", with: model)
        XCTAssertEqual(store.bookmarkFolders(in: recipes.id).map(\.title), ["Soups"])

        let renameFolder = BookmarkNameEdit.renameFolder(recipes)
        XCTAssertEqual(renameFolder.title, "Rename Folder")
        XCTAssertEqual(renameFolder.confirmLabel, "Save")
        XCTAssertEqual(renameFolder.startingName, "Recipes")
        renameFolder.commit("Cooking", with: model)
        XCTAssertEqual(store.bookmarkFolder(id: recipes.id)?.title, "Cooking")

        let renameBookmark = BookmarkNameEdit.renameBookmark(bread)
        XCTAssertEqual(renameBookmark.title, "Rename Bookmark")
        XCTAssertEqual(renameBookmark.confirmLabel, "Save")
        XCTAssertEqual(renameBookmark.startingName, "Bread")
        renameBookmark.commit("Sourdough", with: model)
        XCTAssertEqual(store.bookmark(for: bread.url)?.title, "Sourdough")
    }
}

/// Folders and pages made the way the app makes them, through the store's
/// own calls.
private extension BrowserDataStore {
    func folder(named title: String, in parentID: UUID? = nil) throws -> BookmarkFolderRecord {
        try XCTUnwrap(createBookmarkFolder(title: title, iconID: LimeghostIconCatalog.defaultIconID, parentID: parentID))
    }

    func page(_ title: String, at address: String, in folderID: UUID? = nil) throws -> BookmarkRecord {
        try XCTUnwrap(addBookmark(title: title, url: address, folderID: folderID))
    }
}
```

- [ ] **Step 2: Add both files to the project, and watch the tests fail**

```bash
touch ios/Sources/BookmarksSheet.swift
python3 "$TMPDIR/pbx_add.py" BookmarksSheet.swift BookmarksSheet.swift AA0000000000000000000211 AA0000000000000000000110 NoticeBanner.swift
python3 "$TMPDIR/pbx_add.py" BookmarksSheetTests.swift BookmarksSheetTests.swift AA000000000000000000220A AA000000000000000000210A FindBarTests.swift
```

Run the phone suite with `-only-testing:LimeghostTests/BookmarksSheetTests`.
Expected: build fails with `error: cannot find 'BookmarksModel' in scope`.

- [ ] **Step 3: Write the model**

Write `ios/Sources/BookmarksSheet.swift`:

```swift
import LimeghostCore
import LimeghostShared
import SwiftUI

/// What the Bookmarks sheet shows and does, apart from how it draws, so a
/// test can call it: the shape `TabSwitcherModel` has. It holds only the
/// workspace and reads the store fresh on every call, because the sheet
/// observes the store and rebuilds this whenever the store changes.
///
/// Everything here is the store's or the workspace's own: the order, the
/// search filters, the filing calls and the two doors. The phone adds a list,
/// not a second set of rules.
@MainActor
struct BookmarksModel {
    let workspace: BrowserWorkspace

    private var store: BrowserDataStore { workspace.dataStore }

    // MARK: - Listing

    /// "Bookmarks" at the top level, and a folder's own name inside it.
    func title(of folderID: UUID?) -> String {
        guard let folderID, let folder = store.bookmarkFolder(id: folderID) else { return "Bookmarks" }
        return folder.title
    }

    /// A folder's subfolders, in the store's order: the order the Mac shows.
    func folders(in folderID: UUID?) -> [BookmarkFolderRecord] {
        store.bookmarkFolders(in: folderID)
    }

    /// A folder's bookmarks, in the store's order.
    func bookmarks(in folderID: UUID?) -> [BookmarkRecord] {
        store.bookmarks(in: folderID)
    }

    // MARK: - Search

    /// Folders from every level whose names match, through the filter the
    /// Mac's bookmarks home uses.
    func folders(matching query: String) -> [BookmarkFolderRecord] {
        BookmarksHomeSearch.folders(store.bookmarkFolders, matching: query)
    }

    /// Bookmarks from every folder whose names or addresses match.
    func bookmarks(matching query: String) -> [BookmarkRecord] {
        BookmarksHomeSearch.bookmarks(store.bookmarks, matching: query)
    }

    // MARK: - Doors

    /// Through `open(_:inNewTab:)`, the door table's "an address or a
    /// bookmark" and "a bookmark in a new tab". It makes room for the page
    /// before loading it; a session load directly would skip that.
    func open(_ bookmark: BookmarkRecord, inNewTab: Bool = false) {
        workspace.open(bookmark.url, inNewTab: inNewTab)
    }

    // MARK: - Filing

    func delete(_ bookmark: BookmarkRecord) {
        store.removeBookmark(bookmark)
    }

    /// Whether deleting this folder asks first: only when it holds something,
    /// which is the Mac's rule. An empty folder has nothing to lose.
    func deletingAsksFirst(_ folder: BookmarkFolderRecord) -> Bool {
        store.bookmarkFolderContainsItems(folder)
    }

    /// Deletes the folder itself. What it held moves up to its parent, so
    /// deleting a folder never deletes a saved page.
    func delete(_ folder: BookmarkFolderRecord) {
        store.deleteBookmarkFolderPreservingContents(folder)
    }

    /// Changes the name and nothing else: the address and the folder stay.
    /// An empty name becomes the site's host, which is the store's rule.
    func rename(_ bookmark: BookmarkRecord, to name: String) {
        store.updateBookmark(id: bookmark.id, title: name, url: bookmark.url)
    }

    /// Changes the name and nothing else. The store's update takes an icon and
    /// a tint too; handed the folder's own, it leaves both as they are. An
    /// empty icon ID leaves a folder that never chose one still resolving its
    /// old emoji. An empty name keeps the old one, which is the store's rule.
    func rename(_ folder: BookmarkFolderRecord, to name: String) {
        store.updateBookmarkFolder(id: folder.id, title: name, iconID: folder.iconID ?? "", colorID: folder.colorID)
    }

    /// Files a bookmark at the end of another folder, or of the top level.
    func move(_ bookmark: BookmarkRecord, to folderID: UUID?) {
        store.moveBookmark(bookmark, to: folderID)
    }

    /// A new folder at the end of the one on screen, drawn with the plain
    /// folder. The store refuses an empty name, but the person pressed Create
    /// and asked for a folder, so an empty name makes one called "New Folder".
    @discardableResult
    func createFolder(named name: String, in parentID: UUID?) -> BookmarkFolderRecord? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.createBookmarkFolder(
            title: trimmed.isEmpty ? "New Folder" : trimmed,
            iconID: LimeghostIconCatalog.defaultIconID,
            parentID: parentID
        )
    }
}

/// A name being typed into an alert: a new folder, or a new name for a folder
/// or a bookmark. One value, so each screen has one alert and a test can read
/// what each case shows and does.
enum BookmarkNameEdit {
    case newFolder(parentID: UUID?)
    case renameFolder(BookmarkFolderRecord)
    case renameBookmark(BookmarkRecord)

    var title: String {
        switch self {
        case .newFolder: return "New Folder"
        case .renameFolder: return "Rename Folder"
        case .renameBookmark: return "Rename Bookmark"
        }
    }

    var confirmLabel: String {
        switch self {
        case .newFolder: return "Create"
        case .renameFolder, .renameBookmark: return "Save"
        }
    }

    /// What the field holds when the alert opens: nothing for a new folder,
    /// the current name for a rename.
    var startingName: String {
        switch self {
        case .newFolder: return ""
        case .renameFolder(let folder): return folder.title
        case .renameBookmark(let bookmark): return bookmark.title
        }
    }

    @MainActor
    func commit(_ name: String, with model: BookmarksModel) {
        switch self {
        case .newFolder(let parentID): model.createFolder(named: name, in: parentID)
        case .renameFolder(let folder): model.rename(folder, to: name)
        case .renameBookmark(let bookmark): model.rename(bookmark, to: name)
        }
    }
}
```

- [ ] **Step 4: Run the tests**

Run the phone suite with `-only-testing:LimeghostTests/BookmarksSheetTests`.
Expected: `Executed 12 tests, with 0 failures`.

- [ ] **Step 5: Break it on purpose, twice**

1. In `rename(_ folder:to:)`, pass `iconID: LimeghostIconCatalog.defaultIconID`. Run the class. Expected: `testRenamingAFolderKeepsItsIconAndTint` fails, with `"folder"` against `"palette"`. Restore.
2. In `open(_:inNewTab:)`, pass `inNewTab: false`. Run the class. Expected: `testOpenInNewTabPutsANewTabInFront` fails on the tab count. Restore.

- [ ] **Step 6: Run the whole phone suite**

Expected: `Executed 62 tests, with 0 failures`.

- [ ] **Step 7: Commit**

```bash
git add ios/Sources/BookmarksSheet.swift ios/Tests/BookmarksSheetTests.swift ios/Limeghost.xcodeproj/project.pbxproj
git commit -m "Give the phone's Bookmarks a model: listing, search, doors and filing"   # plus the attribution lines
git push origin feature/ios-pocket-browser
```

---

### Task 3: Move to…, and the sheets' look

**Files:**
- Create: `ios/Sources/BookmarkMovePicker.swift`
- Create: `ios/Sources/SheetLook.swift`
- Create: `ios/Tests/BookmarkMovePickerTests.swift`
- Modify: `ios/Limeghost.xcodeproj/project.pbxproj` (three files, `LimeghostIconView.swift` by reference, and the "Reused from macOS" group's comment)

**Interfaces:**
- Consumes: `BookmarkTree.rows(folders:bookmarks:expanded:)` (Core); `BookmarkFolderIcon(folder:size:tinted:)` (`LimeghostIconView.swift`, by reference).
- Produces:
  - `struct BookmarkDestination: Identifiable, Equatable { let folder: BookmarkFolderRecord?; let depth: Int; var folderID: UUID?; var id: String; var title: String }`.
  - `enum BookmarkDestinations { static func rows(folders: [BookmarkFolderRecord]) -> [BookmarkDestination] }`.
  - `struct BookmarkMovePicker: View { let destinations: [BookmarkDestination]; let currentFolderID: UUID?; let choose: (UUID?) -> Void }`.
  - `extension View { func limeghostListSheet() -> some View }`.

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/BookmarkMovePickerTests.swift`:

```swift
import XCTest
import LimeghostCore
@testable import Limeghost

final class BookmarkMovePickerTests: XCTestCase {
    /// The top level first, then every folder with its children beneath it,
    /// alphabetical within a parent, each indented one step past its parent.
    /// The input is deliberately out of order.
    func testDestinationsListTheTopLevelThenTheTreeIndented() {
        let travel = BookmarkFolderRecord(title: "Travel")
        let recipes = BookmarkFolderRecord(title: "Recipes")
        let soups = BookmarkFolderRecord(title: "Soups", parentID: recipes.id)
        let bread = BookmarkFolderRecord(title: "Bread", parentID: recipes.id)

        let rows = BookmarkDestinations.rows(folders: [travel, soups, recipes, bread])

        XCTAssertEqual(rows.map(\.title), ["Bookmarks", "Recipes", "Bread", "Soups", "Travel"])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 2, 2, 1])
        XCTAssertNil(rows.first?.folderID, "the first row is the top level")
        XCTAssertEqual(rows[2].folderID, bread.id)
    }
}
```

- [ ] **Step 2: Add the files to the project, and watch the test fail**

```bash
touch ios/Sources/SheetLook.swift ios/Sources/BookmarkMovePicker.swift
python3 "$TMPDIR/pbx_add.py" SheetLook.swift SheetLook.swift AA0000000000000000000210 AA000000000000000000010F BookmarksSheet.swift
python3 "$TMPDIR/pbx_add.py" BookmarkMovePicker.swift BookmarkMovePicker.swift AA0000000000000000000212 AA0000000000000000000111 SheetLook.swift
python3 "$TMPDIR/pbx_add.py" BookmarkMovePickerTests.swift BookmarkMovePickerTests.swift AA000000000000000000220B AA000000000000000000210B BookmarksSheetTests.swift
python3 "$TMPDIR/pbx_add.py" LimeghostIconView.swift ../macos/LimeghostBrowser/Sources/LimeghostBrowser/LimeghostIconView.swift AA0000000000000000000668 AA0000000000000000000678 ReaderView.swift
```

In the "Reused from macOS" group's comment, change `header by name. The Mac's own copies are untouched: these` so that the sentence before it reads: "…and the phone asks for its touch header by name. Bookmarks brought folders to the phone, so `LimeghostIconView.swift` joined to draw them. The Mac's own copies are untouched: these are references, not duplicates." Keep the comment's existing tab-and-three-spaces line indentation.

Run the phone suite with `-only-testing:LimeghostTests/BookmarkMovePickerTests`.
Expected: build fails with `error: cannot find 'BookmarkDestinations' in scope`.

- [ ] **Step 3: Write the look, the destinations and the picker**

Write `ios/Sources/SheetLook.swift`:

```swift
import SwiftUI

extension View {
    /// How Bookmarks, History and Move to… sit over the page.
    ///
    /// They draw on Limeghost's surfaces, like the page menu they open from;
    /// a white sheet opening out of the dark menu would look broken. They ask
    /// for the dark appearance, so the system's own parts match those
    /// surfaces: bars, the search field, swipe buttons, alerts and menus. The
    /// rest of the app still follows the system until the phone's look is
    /// designed (step 5).
    func limeghostListSheet() -> some View {
        tint(LimeghostTheme.accent)
            .preferredColorScheme(.dark)
            .presentationBackground(LimeghostTheme.bg1)
    }
}
```

Write `ios/Sources/BookmarkMovePicker.swift`:

```swift
import LimeghostCore
import SwiftUI

/// One place a bookmark can be moved to: the top level, or a folder, with how
/// far to indent it.
struct BookmarkDestination: Identifiable, Equatable {
    /// Nil is the top level.
    let folder: BookmarkFolderRecord?
    let depth: Int

    var folderID: UUID? { folder?.id }
    var id: String { folder?.id.uuidString ?? "top-level" }
    var title: String { folder?.title ?? "Bookmarks" }
}

enum BookmarkDestinations {
    /// The top level first, then every folder with its children beneath it,
    /// alphabetical within a parent: Core's tree with every branch open, the
    /// order the Mac's own tree and Move menu use. The Mac labels each folder
    /// with its whole path instead, which is too wide to read on a phone.
    static func rows(folders: [BookmarkFolderRecord]) -> [BookmarkDestination] {
        let tree = BookmarkTree.rows(folders: folders, bookmarks: [], expanded: Set(folders.map(\.id)))
        return [BookmarkDestination(folder: nil, depth: 0)]
            + tree.map { BookmarkDestination(folder: $0.folder, depth: $0.depth + 1) }
    }
}

/// Move to…: every place a bookmark can go, with a checkmark where it is now.
/// A tap files it there and closes; Cancel closes without moving anything.
struct BookmarkMovePicker: View {
    let destinations: [BookmarkDestination]
    let currentFolderID: UUID?
    let choose: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(destinations) { destination in
                Button {
                    choose(destination.folderID)
                    dismiss()
                } label: {
                    row(destination)
                }
                .listRowBackground(LimeghostTheme.bg2)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Move to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .limeghostListSheet()
    }

    private func row(_ destination: BookmarkDestination) -> some View {
        HStack(spacing: 12) {
            if let folder = destination.folder {
                BookmarkFolderIcon(folder: folder)
            } else {
                Image(systemName: "book")
                    .font(.system(size: 15))
                    .foregroundStyle(LimeghostTheme.accent)
                    .frame(width: LimeghostTheme.siteIconSize, height: LimeghostTheme.siteIconSize)
            }
            Text(destination.title)
                .foregroundStyle(LimeghostTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 12)
            if destination.folderID == currentFolderID {
                Image(systemName: "checkmark")
                    .foregroundStyle(LimeghostTheme.accent)
                    .accessibilityLabel("Current place")
            }
        }
        .padding(.leading, CGFloat(destination.depth) * 16)
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step 4: Run the test**

Run the phone suite with `-only-testing:LimeghostTests/BookmarkMovePickerTests`.
Expected: `Executed 1 test, with 0 failures`. Its build is also the first proof that `LimeghostIconView.swift` compiles for iOS.

- [ ] **Step 5: Break it on purpose**

In `rows(folders:)`, use `depth: $0.depth` instead of `$0.depth + 1`. Expected: the test fails on the depths, `[0, 0, 1, 1, 0]`. Restore.

- [ ] **Step 6: Run the whole phone suite**

Expected: `Executed 63 tests, with 0 failures`.

- [ ] **Step 7: Commit**

```bash
git add ios/Sources/SheetLook.swift ios/Sources/BookmarkMovePicker.swift ios/Tests/BookmarkMovePickerTests.swift ios/Limeghost.xcodeproj/project.pbxproj
git commit -m "Add Move to… for the phone's bookmarks, drawn with the Mac's folder icons"   # plus the attribution lines
git push origin feature/ios-pocket-browser
```

---

### Task 4: The Bookmarks sheet

**Files:**
- Modify: `ios/Sources/BookmarksSheet.swift` (append the two views)

**Interfaces:**
- Consumes: `BookmarksModel`, `BookmarkNameEdit` (Task 2); `BookmarkDestinations`, `BookmarkMovePicker`, `limeghostListSheet()` (Task 3); `SiteIconView(urlString:)`, `BookmarkFolderIcon(folder:)`.
- Produces: `struct BookmarksSheet: View { init(workspace: BrowserWorkspace, dismiss: @escaping () -> Void) }`, which Task 6 presents.

No unit test: these are SwiftUI views over the tested model, checked by eye in Task 7.

- [ ] **Step 1: Append the views**

Append to `ios/Sources/BookmarksSheet.swift`:

```swift
/// Bookmarks, over the page: the top level, the folders beneath it, and a
/// search across all of them. Opened from the page menu. A bookmark opens and
/// the sheet closes; a folder opens on a screen of its own.
struct BookmarksSheet: View {
    let workspace: BrowserWorkspace
    let dismiss: () -> Void

    @State private var query = ""

    var body: some View {
        NavigationStack {
            BookmarkFolderScreen(workspace: workspace, folderID: nil, query: query, close: dismiss)
                .searchable(
                    text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search bookmarks"
                )
                .navigationDestination(for: UUID.self) { folderID in
                    BookmarkFolderScreen(workspace: workspace, folderID: folderID, query: "", close: dismiss)
                }
        }
        .limeghostListSheet()
    }
}

/// One folder's list, or, at the top while something is typed, the matches
/// from every folder, with everything a row can do.
struct BookmarkFolderScreen: View {
    @ObservedObject private var store: BrowserDataStore
    private let workspace: BrowserWorkspace
    /// Nil is the top level.
    private let folderID: UUID?
    /// What the search field holds. Only the top screen has one.
    private let query: String
    private let close: () -> Void

    @State private var nameEdit: BookmarkNameEdit?
    @State private var typedName = ""
    @State private var folderToConfirm: BookmarkFolderRecord?
    @State private var bookmarkToMove: BookmarkRecord?

    init(workspace: BrowserWorkspace, folderID: UUID?, query: String, close: @escaping () -> Void) {
        self.store = workspace.dataStore
        self.workspace = workspace
        self.folderID = folderID
        self.query = query
        self.close = close
    }

    private var model: BookmarksModel { BookmarksModel(workspace: workspace) }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        let folders = isSearching ? model.folders(matching: query) : model.folders(in: folderID)
        let bookmarks = isSearching ? model.bookmarks(matching: query) : model.bookmarks(in: folderID)

        List {
            if isSearching {
                if !folders.isEmpty {
                    Section("Folders") {
                        ForEach(folders) { folderRow($0) }
                    }
                }
                if !bookmarks.isEmpty {
                    Section("Bookmarks") {
                        ForEach(bookmarks) { bookmarkRow($0) }
                    }
                }
            } else {
                ForEach(folders) { folderRow($0) }
                ForEach(bookmarks) { bookmarkRow($0) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .overlay {
            if folders.isEmpty && bookmarks.isEmpty {
                emptyState
            }
        }
        .navigationTitle(model.title(of: folderID))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: close)
            }
            ToolbarItem(placement: .bottomBar) {
                Button {
                    beginNaming(.newFolder(parentID: folderID))
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        .alert(nameEdit?.title ?? "", isPresented: isNaming, presenting: nameEdit) { edit in
            TextField("Name", text: $typedName)
            Button("Cancel", role: .cancel) {}
            Button(edit.confirmLabel) { edit.commit(typedName, with: model) }
        }
        .alert("Delete folder?", isPresented: isConfirmingDeletion, presenting: folderToConfirm) { folder in
            Button("Delete Folder", role: .destructive) { model.delete(folder) }
            Button("Cancel", role: .cancel) {}
        } message: { folder in
            Text(Self.deletionMessage(for: folder))
        }
        .sheet(item: $bookmarkToMove) { bookmark in
            BookmarkMovePicker(
                destinations: BookmarkDestinations.rows(folders: store.bookmarkFolders),
                currentFolderID: bookmark.folderID
            ) { destination in
                model.move(bookmark, to: destination)
            }
        }
    }

    private func folderRow(_ folder: BookmarkFolderRecord) -> some View {
        NavigationLink(value: folder.id) {
            HStack(spacing: 12) {
                BookmarkFolderIcon(folder: folder)
                Text(folder.title)
                    .foregroundStyle(LimeghostTheme.textPrimary)
                    .lineLimit(1)
            }
        }
        .listRowBackground(LimeghostTheme.bg2)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Not `role: .destructive`: a destructive swipe button animates its
            // row away at once, before a folder that asks first has its answer.
            Button {
                requestDeletion(folder)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
        .contextMenu {
            Button {
                beginNaming(.renameFolder(folder))
            } label: {
                Label("Rename…", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                requestDeletion(folder)
            } label: {
                Label("Delete Folder", systemImage: "trash")
            }
        }
    }

    private func bookmarkRow(_ bookmark: BookmarkRecord) -> some View {
        Button {
            model.open(bookmark)
            close()
        } label: {
            HStack(spacing: 12) {
                SiteIconView(urlString: bookmark.url)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bookmark.title)
                        .foregroundStyle(LimeghostTheme.textPrimary)
                        .lineLimit(1)
                    Text(URL(string: bookmark.url)?.host ?? bookmark.url)
                        .font(.caption)
                        .foregroundStyle(LimeghostTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .listRowBackground(LimeghostTheme.bg2)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                model.delete(bookmark)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                model.open(bookmark, inNewTab: true)
                close()
            } label: {
                Label("Open in New Tab", systemImage: "plus.square.on.square")
            }
            Button {
                beginNaming(.renameBookmark(bookmark))
            } label: {
                Label("Rename…", systemImage: "pencil")
            }
            Button {
                bookmarkToMove = bookmark
            } label: {
                Label("Move to…", systemImage: "folder")
            }
            Divider()
            Button(role: .destructive) {
                model.delete(bookmark)
            } label: {
                Label("Delete Bookmark", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if isSearching {
            ContentUnavailableView.search(text: query)
        } else if folderID == nil {
            ContentUnavailableView(
                "No Bookmarks Yet",
                systemImage: "book",
                description: Text("Add Bookmark in the menu saves the page you're on.")
            )
        } else {
            ContentUnavailableView(
                "This Folder Is Empty",
                systemImage: "folder",
                description: Text("To file a bookmark here, touch and hold it, then choose Move to…")
            )
        }
    }

    private var isNaming: Binding<Bool> {
        Binding(get: { nameEdit != nil }, set: { if !$0 { nameEdit = nil } })
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding(get: { folderToConfirm != nil }, set: { if !$0 { folderToConfirm = nil } })
    }

    /// The field starts from the current name for a rename, and empty for a
    /// new folder.
    private func beginNaming(_ edit: BookmarkNameEdit) {
        typedName = edit.startingName
        nameEdit = edit
    }

    /// An empty folder goes at once. One holding anything asks first.
    private func requestDeletion(_ folder: BookmarkFolderRecord) {
        if model.deletingAsksFirst(folder) {
            folderToConfirm = folder
        } else {
            model.delete(folder)
        }
    }

    /// The Mac's words for the same question, in `BookmarksHomePage`. Built
    /// as a `String`, so a folder name is never read as Markdown.
    private static func deletionMessage(for folder: BookmarkFolderRecord) -> String {
        "\(folder.title) contains saved items. Its bookmarks and subfolders will move to the parent folder; nothing will be deleted."
    }
}
```

- [ ] **Step 2: Build and run the whole phone suite**

Expected: `** TEST SUCCEEDED **` and `Executed 63 tests, with 0 failures`.

- [ ] **Step 3: Commit**

```bash
git add ios/Sources/BookmarksSheet.swift
git commit -m "Draw the phone's Bookmarks: folders, search, swipe, menus and New Folder"   # plus the attribution lines
git push origin feature/ios-pocket-browser
```

---

### Task 5: History

**Files:**
- Create: `ios/Sources/HistorySheet.swift`
- Create: `ios/Tests/HistorySheetTests.swift`
- Modify: `ios/Limeghost.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `HistoryHomeSearch` (Task 1); `HistoryDayGrouping.groups(_:calendar:now:)` and `HistoryDayGroup` (Core); `BrowserDataStore.history`, `removeHistory(_:)`, `clearHistory()`; `limeghostListSheet()` (Task 3).
- Produces:
  - `@MainActor struct HistoryModel { let workspace: BrowserWorkspace }` with `days(matching: String, calendar: Calendar = .current, now: Date = Date()) -> [HistoryDayGroup]`, `canClear: Bool`, `open(_: HistoryRecord, inNewTab: Bool = false)`, `delete(_: HistoryRecord)`, `clear()`.
  - `enum HistoryWording` with `clearTitle`, `clearLabel`, `footnote` (static `String`s), `clearMessage(visitCount: Int) -> String`, `title(of: HistoryRecord) -> String` and `detail(of: HistoryRecord) -> String`.
  - `struct HistorySheet: View { init(workspace: BrowserWorkspace, dismiss: @escaping () -> Void) }`, which Task 6 presents.

- [ ] **Step 1: Write the failing tests**

Create `ios/Tests/HistorySheetTests.swift`:

```swift
import XCTest
import LimeghostCore
@testable import Limeghost
@testable import LimeghostShared

@MainActor
final class HistorySheetTests: XCTestCase {
    /// A suite of its own, emptied afterwards: these tests run inside the app.
    private func makeHost() throws -> WorkspaceHost {
        let suiteName = "clearframe.iosHistory.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return WorkspaceHost.forTesting(defaults: defaults)
    }

    /// A fixed calendar, as Core's own grouping tests use, so "today" does not
    /// depend on when or where the suite runs.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Bucharest")!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }()

    private func september(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    /// Visits come back as days, newest first. A search filters them before
    /// they are grouped, so a day with nothing matching does not appear.
    func testVisitsComeBackAsDaysFilteredBeforeGrouping() throws {
        let host = try makeHost()
        let store = host.workspace.dataStore
        store.recordVisit(title: "Bread", url: "https://example.com/bread", at: september(12, 9))
        store.recordVisit(title: "Soup", url: "https://example.com/soup", at: september(13, 9))
        store.recordVisit(title: "Cake", url: "https://example.com/cake", at: september(13, 11))
        let model = HistoryModel(workspace: host.workspace)
        let now = september(13, 17)

        let everything = model.days(matching: "", calendar: calendar, now: now)
        XCTAssertEqual(everything.map(\.title), ["Today", "Yesterday"])
        XCTAssertEqual(everything.first?.visits.map(\.title), ["Cake", "Soup"])

        let bread = model.days(matching: "BREAD", calendar: calendar, now: now)
        XCTAssertEqual(bread.map(\.title), ["Yesterday"])
        XCTAssertEqual(bread.first?.visits.map(\.title), ["Bread"])
    }

    /// A visit opens in the tab in front, through the same door as a bookmark.
    func testOpeningAVisitLoadsItInTheTabInFront() throws {
        let host = try makeHost()
        host.workspace.dataStore.recordVisit(title: "Example", url: "https://example.com/visited")
        let visit = try XCTUnwrap(host.workspace.dataStore.history.first)
        let tabsBefore = host.workspace.visibleTabs.count

        HistoryModel(workspace: host.workspace).open(visit)

        XCTAssertEqual(host.workspace.visibleTabs.count, tabsBefore)
        XCTAssertEqual(host.workspace.selectedTab?.session.currentURLString, "https://example.com/visited")
    }

    /// Open in New Tab puts a new tab in front, holding the visit.
    func testOpenInNewTabAddsATab() throws {
        let host = try makeHost()
        host.workspace.dataStore.recordVisit(title: "Example", url: "https://example.com/visited")
        let visit = try XCTUnwrap(host.workspace.dataStore.history.first)
        let tabsBefore = host.workspace.visibleTabs.count

        HistoryModel(workspace: host.workspace).open(visit, inNewTab: true)

        XCTAssertEqual(host.workspace.visibleTabs.count, tabsBefore + 1)
        XCTAssertEqual(host.workspace.selectedTab?.session.currentURLString, "https://example.com/visited")
    }

    /// Delete takes one visit and Clear takes them all. Clear is offered only
    /// while there is something to clear.
    func testDeleteRemovesOneVisitAndClearRemovesThemAll() throws {
        let host = try makeHost()
        let store = host.workspace.dataStore
        store.recordVisit(title: "Bread", url: "https://example.com/bread")
        store.recordVisit(title: "Soup", url: "https://example.com/soup")
        let model = HistoryModel(workspace: host.workspace)
        XCTAssertTrue(model.canClear)

        model.delete(try XCTUnwrap(store.history.first { $0.title == "Soup" }))
        XCTAssertEqual(store.history.map(\.title), ["Bread"])

        model.clear()
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertFalse(model.canClear)
    }

    /// The confirmation counts what it will remove and names this device. It
    /// never names the Mac, whose wording it was adapted from.
    func testClearingSaysHowManyVisitsAndWhere() {
        XCTAssertEqual(
            HistoryWording.clearMessage(visitCount: 1),
            "This removes 1 stored visit from this device and cannot be undone. Your bookmarks and open tabs are not affected."
        )
        XCTAssertTrue(HistoryWording.clearMessage(visitCount: 3).contains("3 stored visits"))
        XCTAssertFalse(HistoryWording.clearMessage(visitCount: 3).contains("Mac"))
    }

    /// A visit with no title shows its address, so no row is blank.
    func testAVisitWithNoTitleShowsItsAddress() {
        XCTAssertEqual(
            HistoryWording.title(of: HistoryRecord(title: "", url: "https://example.com/untitled")),
            "https://example.com/untitled"
        )
        XCTAssertEqual(HistoryWording.title(of: HistoryRecord(title: "Soup", url: "https://example.com/soup")), "Soup")
    }
}
```

- [ ] **Step 2: Add both files to the project, and watch the tests fail**

```bash
touch ios/Sources/HistorySheet.swift
python3 "$TMPDIR/pbx_add.py" HistorySheet.swift HistorySheet.swift AA0000000000000000000213 AA0000000000000000000112 BookmarkMovePicker.swift
python3 "$TMPDIR/pbx_add.py" HistorySheetTests.swift HistorySheetTests.swift AA000000000000000000220C AA000000000000000000210C BookmarkMovePickerTests.swift
```

Run the phone suite with `-only-testing:LimeghostTests/HistorySheetTests`.
Expected: build fails with `error: cannot find 'HistoryModel' in scope`.

- [ ] **Step 3: Write the model, the wording and the view**

Write `ios/Sources/HistorySheet.swift`:

```swift
import LimeghostCore
import LimeghostShared
import SwiftUI

/// What the History sheet shows and does, apart from how it draws, so a test
/// can call it. Reads the store fresh on every call, like `BookmarksModel`.
@MainActor
struct HistoryModel {
    let workspace: BrowserWorkspace

    private var store: BrowserDataStore { workspace.dataStore }

    /// The visits matching what was typed, as days, newest first: the Mac's
    /// search filter, then Core's day grouping. The calendar and "now" are for
    /// tests, as they are in the grouping itself.
    func days(matching query: String, calendar: Calendar = .current, now: Date = Date()) -> [HistoryDayGroup] {
        HistoryDayGrouping.groups(HistoryHomeSearch.visits(store.history, matching: query), calendar: calendar, now: now)
    }

    /// Clear History is offered only while there is something to clear, as
    /// on the Mac.
    var canClear: Bool { !store.history.isEmpty }

    /// The same two doors as a bookmark's.
    func open(_ visit: HistoryRecord, inNewTab: Bool = false) {
        workspace.open(visit.url, inNewTab: inNewTab)
    }

    func delete(_ visit: HistoryRecord) {
        store.removeHistory(visit)
    }

    func clear() {
        store.clearHistory()
    }
}

/// The History sheet's words.
///
/// The confirmation follows the Mac's `ClearHistoryConfirmation` with two
/// differences. It names this device rather than the Mac, because the target
/// builds for iPad as well as iPhone. It does not mention downloaded files,
/// because the phone has none.
enum HistoryWording {
    static let clearTitle = "Clear all local history?"
    static let clearLabel = "Clear History"

    static func clearMessage(visitCount: Int) -> String {
        let visits = visitCount == 1 ? "1 stored visit" : "\(visitCount) stored visits"
        return "This removes \(visits) from this device and cannot be undone. Your bookmarks and open tabs are not affected."
    }

    /// Both already true. The workspace records a visit only when its tab is
    /// not private, and history never syncs.
    static let footnote = "Stored only on this device. Private tabs are never recorded."

    /// A visit with no title shows its address, so no row is blank.
    static func title(of visit: HistoryRecord) -> String {
        visit.title.isEmpty ? visit.url : visit.title
    }

    /// When, then where: "14:05 · example.com".
    static func detail(of visit: HistoryRecord) -> String {
        let time = visit.visitedAt.formatted(date: .omitted, time: .shortened)
        let host = URL(string: visit.url)?.host ?? visit.url
        return "\(time) · \(host)"
    }
}

/// History, over the page: visits by day, a search, and a way to clear them.
/// Opened from the page menu. A visit opens and the sheet closes.
struct HistorySheet: View {
    @ObservedObject private var store: BrowserDataStore
    private let workspace: BrowserWorkspace
    private let dismiss: () -> Void

    @State private var query = ""
    @State private var isConfirmingClear = false

    init(workspace: BrowserWorkspace, dismiss: @escaping () -> Void) {
        self.store = workspace.dataStore
        self.workspace = workspace
        self.dismiss = dismiss
    }

    private var model: HistoryModel { HistoryModel(workspace: workspace) }

    var body: some View {
        let days = model.days(matching: query)

        NavigationStack {
            List {
                ForEach(days) { day in
                    Section(day.title) {
                        ForEach(day.visits) { visit in
                            row(visit)
                        }
                    }
                }
                if !days.isEmpty {
                    Section {
                    } footer: {
                        Text(HistoryWording.footnote)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .overlay {
                if days.isEmpty {
                    emptyState
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search history"
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss)
                }
                if model.canClear {
                    ToolbarItem(placement: .bottomBar) {
                        Button(HistoryWording.clearLabel, role: .destructive) {
                            isConfirmingClear = true
                        }
                    }
                }
            }
            .confirmationDialog(
                HistoryWording.clearTitle,
                isPresented: $isConfirmingClear,
                titleVisibility: .visible
            ) {
                Button(HistoryWording.clearLabel, role: .destructive) { model.clear() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(HistoryWording.clearMessage(visitCount: store.history.count))
            }
        }
        .limeghostListSheet()
    }

    private func row(_ visit: HistoryRecord) -> some View {
        Button {
            model.open(visit)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                SiteIconView(urlString: visit.url)
                VStack(alignment: .leading, spacing: 2) {
                    Text(HistoryWording.title(of: visit))
                        .foregroundStyle(LimeghostTheme.textPrimary)
                        .lineLimit(1)
                    Text(HistoryWording.detail(of: visit))
                        .font(.caption)
                        .foregroundStyle(LimeghostTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .listRowBackground(LimeghostTheme.bg2)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                model.delete(visit)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                model.open(visit, inNewTab: true)
                dismiss()
            } label: {
                Label("Open in New Tab", systemImage: "plus.square.on.square")
            }
            Divider()
            Button(role: .destructive) {
                model.delete(visit)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView(
                "No History Yet",
                systemImage: "clock",
                description: Text("Pages you visit appear here. Private tabs are never recorded.")
            )
        } else {
            ContentUnavailableView.search(text: query)
        }
    }
}
```

- [ ] **Step 4: Run the tests**

Run the phone suite with `-only-testing:LimeghostTests/HistorySheetTests`.
Expected: `Executed 6 tests, with 0 failures`.

- [ ] **Step 5: Break it on purpose**

In `days(matching:calendar:now:)`, pass `store.history` straight to the grouping, skipping the search. Expected: `testVisitsComeBackAsDaysFilteredBeforeGrouping` fails on `["Today", "Yesterday"]` against `["Yesterday"]`. Restore.

- [ ] **Step 6: Run the whole phone suite**

Expected: `Executed 69 tests, with 0 failures`.

- [ ] **Step 7: Commit**

```bash
git add ios/Sources/HistorySheet.swift ios/Tests/HistorySheetTests.swift ios/Limeghost.xcodeproj/project.pbxproj
git commit -m "Give the phone History: visits by day, search, delete and clear"   # plus the attribution lines
git push origin feature/ios-pocket-browser
```

---

### Task 6: The menu's two new rows open the sheets

**Files:**
- Modify: `ios/Sources/PageMenu.swift`
- Modify: `ios/Sources/BrowserScreen.swift`
- Modify: `ios/Tests/PageMenuTests.swift`
- Modify: `ios/Tests/StartSurfaceTests.swift` (one comment)

**Interfaces:**
- Consumes: `BookmarksSheet(workspace:dismiss:)` (Task 4), `HistorySheet(workspace:dismiss:)` (Task 5), `\.faviconStore` (`SiteIconView.swift`), `BrowserWorkspace.favicons`.
- Produces: `PageMenuItem.bookmarks`, `PageMenuItem.history`; `enum PageMenuDestination: Identifiable { case bookmarks, history }`; `PageMenuPresentation.destination: PageMenuDestination?`.

- [ ] **Step 1: Write the failing tests**

In `ios/Tests/PageMenuTests.swift`, replace `testOnTheGuideOnlyTheNewTabRowsWork` with:

```swift
    /// On the AI guide there is no page to act on. The rows that need no page
    /// work: the two that open a new tab, and the two that open a list. The
    /// rest stay in place, greyed, and light up when a page opens.
    func testOnTheGuideOnlyTheRowsThatNeedNoPageWork() {
        let guide = model(hasPage: false)
        XCTAssertEqual(PageMenuItem.allCases.filter(guide.isEnabled), [.newTab, .newPrivateTab, .bookmarks, .history])
    }
```

Add, after `testTheLabelsSayWhatATapWillDoNext`:

```swift
    /// The two list rows say where they go.
    func testTheListRowsSayWhereTheyGo() {
        XCTAssertEqual(model().title(.bookmarks), "Bookmarks")
        XCTAssertEqual(model().symbol(.bookmarks), "book")
        XCTAssertEqual(model().title(.history), "History")
        XCTAssertEqual(model().symbol(.history), "clock")
    }
```

Add, at the end of the `When a row acts` section:

```swift
    /// Bookmarks is a sheet of its own, and SwiftUI presents one sheet at a
    /// time. Choosing it closes the menu, and Bookmarks opens only once the
    /// menu has gone. There is nothing left to run.
    func testChoosingBookmarksOpensItOnceTheMenuHasGone() {
        var presentation = PageMenuPresentation()
        presentation.open()
        presentation.choose(.bookmarks)

        XCTAssertFalse(presentation.isPresented)
        XCTAssertNil(presentation.destination, "not while the menu is still closing")
        XCTAssertNil(presentation.didDismiss(), "a list is opened, not run")
        XCTAssertEqual(presentation.destination, .bookmarks)
    }

    /// History likewise.
    func testChoosingHistoryOpensItOnceTheMenuHasGone() {
        var presentation = PageMenuPresentation()
        presentation.open()
        presentation.choose(.history)

        XCTAssertNil(presentation.destination)
        XCTAssertNil(presentation.didDismiss())
        XCTAssertEqual(presentation.destination, .history)
    }

    /// Every other row runs as before and opens no list.
    func testEveryOtherRowRunsAndOpensNoList() {
        for item in PageMenuItem.allCases where item != .bookmarks && item != .history {
            var presentation = PageMenuPresentation()
            presentation.open()
            presentation.choose(item)

            XCTAssertEqual(presentation.didDismiss(), item)
            XCTAssertNil(presentation.destination, "\(item) opened a list")
        }
    }
```

- [ ] **Step 2: Watch them fail**

Run the phone suite with `-only-testing:LimeghostTests/PageMenuTests`.
Expected: build fails with `error: type 'PageMenuItem' has no member 'bookmarks'`.

- [ ] **Step 3: Add the rows**

In `ios/Sources/PageMenu.swift`:

1. Replace the enum and its comment:

```swift
/// Everything the page menu offers, in the order it shows them: the two large
/// buttons, then the three cards.
enum PageMenuItem: CaseIterable, Hashable {
    case reader, copyForAI
    case reload, forward, newTab, newPrivateTab
    case bookmark, find, share, desktopSite
    case bookmarks, history
}
```

2. In `isEnabled`, replace `case .newTab, .newPrivateTab:` with `case .newTab, .newPrivateTab, .bookmarks, .history:`.

3. In `title(_:)`, before its closing brace, add:

```swift
        case .bookmarks: return "Bookmarks"
        case .history: return "History"
```

4. In `symbol(_:)`, before its closing brace, add:

```swift
        case .bookmarks: return "book"
        case .history: return "clock"
```

5. Directly above `struct PageMenuPresentation`, add:

```swift
/// The two rows that open a list over the page rather than act on it.
enum PageMenuDestination: Identifiable {
    case bookmarks, history

    var id: Self { self }
}
```

6. In `PageMenuPresentation`, add the property after `chosen`:

```swift
    /// Bookmarks or History, open over the page. Set only once the menu has
    /// gone, because SwiftUI presents one sheet at a time; the list's sheet
    /// clears it again when it closes.
    var destination: PageMenuDestination?
```

Replace `didDismiss()` and its comment with:

```swift
    /// The sheet has gone. Hands back the row to act on, once. Bookmarks and
    /// History are lists rather than actions: those open instead, and nothing
    /// is handed back.
    mutating func didDismiss() -> PageMenuItem? {
        defer { chosen = nil }
        switch chosen {
        case .bookmarks?:
            destination = .bookmarks
            return nil
        case .history?:
            destination = .history
            return nil
        default:
            return chosen
        }
    }
```

7. In `PageMenuActions.perform(_:)`, before its closing brace, add:

```swift
        case .bookmarks, .history: break // Lists, which `PageMenuPresentation` opens.
```

8. In `PageMenu.body`, after the second card's `.padding(.top, 16)`, add:

```swift
                card([.bookmarks, .history])
                    .padding(.top, 16)
```

and change the view's comment from "then two cards of rows" to "then three cards of rows".

- [ ] **Step 4: Present the sheets, and hand down the site icons**

In `ios/Sources/BrowserScreen.swift`, after the page menu's `.sheet(isPresented: $menu.isPresented, …) { … }` modifier, add:

```swift
        .sheet(item: $menu.destination) { destination in
            switch destination {
            case .bookmarks:
                BookmarksSheet(workspace: host.workspace) { menu.destination = nil }
            case .history:
                HistorySheet(workspace: host.workspace) { menu.destination = nil }
            }
        }
        // Handed down once, as the Mac's `BrowserView` does, so every site icon
        // on the phone draws what a visit captured rather than its fallback
        // square: the guide's, and both lists'. The phone had never done this.
        .environment(\.faviconStore, host.workspace.favicons)
```

In the same file's comment on `showsGuide`, replace "iOS has no Home button and no bookmarks or history home yet to reset it" with "iOS has no Home button, and its Bookmarks and History are sheets rather than start surfaces, so nothing resets it". In `ios/Tests/StartSurfaceTests.swift`, make the same replacement in the comment on `testTheGateHidesTheGuideOnceAPageIsLoaded`.

- [ ] **Step 5: Run the tests**

Run the phone suite with `-only-testing:LimeghostTests/PageMenuTests`.
Expected: `Executed 19 tests, with 0 failures`.

- [ ] **Step 6: Break it on purpose**

In `didDismiss()`, delete the `case .bookmarks?:` branch. Expected: `testChoosingBookmarksOpensItOnceTheMenuHasGone` fails, because `didDismiss()` now hands back `.bookmarks` and sets no destination. `testEveryOtherRowRunsAndOpensNoList` skips `.bookmarks`, so it still passes. Restore.

- [ ] **Step 7: Run the whole phone suite**

Expected: `Executed 73 tests, with 0 failures`.

- [ ] **Step 8: Commit**

```bash
git add ios/Sources/PageMenu.swift ios/Sources/BrowserScreen.swift ios/Tests/PageMenuTests.swift ios/Tests/StartSurfaceTests.swift
git commit -m "Open Bookmarks and History from the phone's page menu"   # plus the attribution lines
git push origin feature/ios-pocket-browser
```

---

### Task 7: Look at it

Nothing here is committed. The goal is to see the sheets before the founder does.

- [ ] **Step 1: Draw the sheets with seeded data (throwaway)**

Create `ios/Tests/SheetLookHarness.swift`, and add it to the project with `pbx_add.py` using IDs `AA00000000000000000022FF` / `AA00000000000000000021FF`, after `HistorySheetTests.swift`:

```swift
import SwiftUI
import UIKit
import XCTest
import LimeghostCore
@testable import Limeghost
@testable import LimeghostShared

/// Throwaway: draws the new sheets over seeded data into PNGs. Never committed.
@MainActor
final class SheetLookHarness: XCTestCase {
    func testDrawTheSheets() async throws {
        let suiteName = "clearframe.iosLook.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let host = WorkspaceHost.forTesting(defaults: defaults)
        let store = host.workspace.dataStore
        let out = URL(fileURLWithPath: try XCTUnwrap(ProcessInfo.processInfo.environment["LOOK_DIR"]))

        try await draw(BookmarksSheet(workspace: host.workspace, dismiss: {}), to: out.appendingPathComponent("bookmarks-empty.png"))
        try await draw(HistorySheet(workspace: host.workspace, dismiss: {}), to: out.appendingPathComponent("history-empty.png"))

        let recipes = try XCTUnwrap(store.createBookmarkFolder(title: "Recipes", iconID: "folder", parentID: nil))
        _ = store.createBookmarkFolder(title: "Work", iconID: "briefcase", colorID: "blue", parentID: nil)
        _ = store.createBookmarkFolder(title: "Soups", iconID: "folder", parentID: recipes.id)
        store.addBookmark(title: "BBC News", url: "https://www.bbc.com/news", folderID: nil)
        store.addBookmark(title: "Swift Forums, a long title that has to stop at the edge of a phone", url: "https://forums.swift.org/", folderID: nil)
        store.addBookmark(title: "Sourdough", url: "https://example.com/bread", folderID: recipes.id)
        store.recordVisit(title: "MacRumors", url: "https://www.macrumors.com/", at: Date().addingTimeInterval(-600))
        store.recordVisit(title: "Apple", url: "https://www.apple.com/", at: Date().addingTimeInterval(-3_600))
        store.recordVisit(title: "Wikipedia", url: "https://en.wikipedia.org/", at: Date().addingTimeInterval(-90_000))

        try await draw(BookmarksSheet(workspace: host.workspace, dismiss: {}), to: out.appendingPathComponent("bookmarks.png"))
        try await draw(HistorySheet(workspace: host.workspace, dismiss: {}), to: out.appendingPathComponent("history.png"))
        try await draw(
            BookmarkMovePicker(destinations: BookmarkDestinations.rows(folders: store.bookmarkFolders), currentFolderID: recipes.id) { _ in },
            to: out.appendingPathComponent("move-to.png")
        )
    }

    /// Presents the view as a real sheet in a window of its own, so the
    /// presentation modifiers apply, then draws the window.
    private func draw<Content: View>(_ content: Content, to url: URL) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: Color.black.sheet(isPresented: .constant(true)) { content })
        window.makeKeyAndVisible()
        try await Task.sleep(for: .seconds(2))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try XCTUnwrap(image.pngData()).write(to: url)
        window.isHidden = true
    }
}
```

Run: `cd ios && TEST_RUNNER_LOOK_DIR="$LOOK_DIR" xcodebuild test -scheme Limeghost -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:LimeghostTests/SheetLookHarness 2>&1 | grep -E "error:|\*\* TEST"`, with `LOOK_DIR` set to an existing temporary directory. Open each PNG.

Check:
- dark surfaces;
- rows on `bg2`;
- readable text;
- folder icons drawn, not blank;
- long titles truncated;
- the search field present;
- New Folder and Clear History in the bottom bar;
- the empty states centred;
- Move to…'s indentation and checkmark.

- [ ] **Step 2: Remove the harness**

```bash
rm ios/Tests/SheetLookHarness.swift
git checkout -- ios/Limeghost.xcodeproj/project.pbxproj
git status --short   # expect nothing
```

- [ ] **Step 3: On the founder's iPhone**

If the phone is connected and unlocked, install as `docs/ios-browser-foundation.md` records: team read from `defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier` and passed on the command line; bundle `com.zincoo.limeghost.dev`. Hand the founder the spec §8 by-hand list. Record only what was actually seen.

---

### Task 8: Documents, and CI

**Files:**
- Modify: `docs/ios-browser-foundation.md`, `AGENTS.md`, `CLAUDE.md`, `CHANGELOG.md`, `docs/project-context.md`, `docs/superpowers/specs/2026-09-03-ios-pocket-browser-design.md`

- [ ] **Step 1: Re-run every suite, and take the counts**

- Mac: expect 517 executed, 0 failures.
- Counts command: expect 238 / 30 / 249.
- `LimeghostSharedLayer` on the simulator: expect `** TEST SUCCEEDED **`.
- Phone: expect 73 executed, 0 failures.

- [ ] **Step 2: Update the documents to what is now true**

- `docs/ios-browser-foundation.md`:
  - Drop "no bookmarks or history surface," from the does-not-exist sentence.
  - "Fourteen source files … six Swift files" becomes "Eighteen source files … seven Swift files".
  - Add Bookmarks and History to the page-menu bullet, and give each a bullet of its own (what it does; that it opens through `open(_:)` and `open(_:inNewTab:)`; that the phone's data is its own).
  - Add `LimeghostIconView.swift` to the by-reference bullet, with one sentence on why it joined.
  - "**50 tests**" becomes "**73 tests**", naming Bookmarks' model, Move to…'s rows and History's model.
  - The Mac count becomes 517; `LimeghostSharedLayer` 268 = 238 + 30; `BrowserBehaviorTests` 249.
- `AGENTS.md` (the "A Mac change can break the phone" paragraph) and `CLAUDE.md` (the portability bullet): "six Mac SwiftUI files" becomes "seven", adding `LimeghostIconView.swift` to AGENTS.md's list.
- `CHANGELOG.md`, top of "Week of September 10–16, 2026": an entry "**The phone gets Bookmarks and History**", with:
  - the two sheets;
  - the doors;
  - the filters moved to Core;
  - the site-icon fix;
  - the seventh by-reference file;
  - counts: Mac 517, `LimeghostSharedLayer` 268 (up from 266), phone 73 (up from 50).
- `docs/project-context.md`, at the end of the iOS section: a dated note of the three approved choices, the pointer to the spec's §10 judgment calls, and which by-hand checks have and have not been done.
- `docs/superpowers/specs/2026-09-03-ios-pocket-browser-design.md`, directly below the component table: "*Amended September 13, 2026:* the phone does not reference `BookmarksHomePage` or `HistoryHomePage`; it has phone-shaped Bookmarks and History sheets over the same store, filters and grouping (see [the Bookmarks and History spec](2026-09-13-ios-bookmarks-history-design.md), §9). `LimeghostIconView` is referenced as planned."

- [ ] **Step 3: Commit, push, open the pull request**

```bash
git add docs AGENTS.md CLAUDE.md CHANGELOG.md
git commit -m "Record Bookmarks and History on the phone"   # plus the attribution lines
git push origin feature/ios-pocket-browser
gh pr create --base main --head feature/ios-pocket-browser --title "The phone gets Bookmarks and History" --body "…"   # summary, test counts, by-hand status, then the PR attribution lines
gh pr checks --watch
```

Expected: `extension`, `macos-browser`, `ios-simulator` and `cef-contract` all pass. Merging waits for the founder's word.
