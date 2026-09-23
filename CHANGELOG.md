# Changelog

Limeghost's development record, assembled from the repository's own history.

The project has not made a public release. There are no version tags, and the app bundle carries `0.1.0` as a development placeholder. Everything below is pre-release work on `main`, grouped by the week it landed. Once a first release ships, this file should switch to versioned sections following [Keep a Changelog](https://keepachangelog.com/) and [semantic versioning](https://semver.org/).

Dates are commit dates. Test counts are the totals at the end of each period, verified by running the suites.

---

## Unreleased

### Week of September 17–23, 2026

**A deep audit of both browsers, September 22**

Each fix below has a test that was watched failing before the fix went in, except where an entry says no test covers it. The work sits on `fix/deep-audit-2026-09-22`.

*Profiles and private windows keep to themselves*

- "Clear local browsing data" emptied the original profile's WebKit store from whichever window it was chosen in: from a second profile's window it signed the original profile out of everything, left its own logins in place, and said the data had been cleared. It clears the window's own profile now.
- The address bar's site panel read, and its Remove button deleted, the original profile's data in every other profile, and the person's *saved* data for a site from inside a private tab. Settings' site list did the same. Both read the tab's own store now.
- "Save browsing history on this Mac" and "Load every restored tab at start" were written where only the original profile reads, so in any other profile turning history off changed nothing and visits went on being recorded. Both belong to the profile now.
- Deleting a profile asked WebKit to remove its store once, while the profile's window still held it, which WebKit refuses — so its cookies and logins stayed on disk. It left the profile's picture folder too, and closed only the window in front. Erasure now removes the whole profile folder and retries the store, and a record in the app's preferences lets the next launch finish what WebKit still refused. It closes every window of the profile, which no test covers, because the suite has no windows.
- A private window's last tab closing left an ordinary tab in a window still marked private, with persistent cookies and recorded history. A file opened into a private window did the same, and so did an address another app handed over. The reset's replacement tab is private in a private window too, by the same one-word change, which no test covers.
- A redirect a private tab followed reached disk in the site-icon table as soon as an ordinary visit wrote the table.
- Every save copies the previous value into a last-known-good backup. A visit deleted from history, a bookmark removed and a page unstarred stayed in that backup on disk until the next unrelated write. They go with the deletion now.

*Links, pages and titles*

- ⌘-click and a middle click on a link open it in a tab behind the page, and ⇧⌘-click opens it in front. Both used to replace the page being read. Only a clicked link moves; a script's navigation and a submitted form stay where they are. It is not a door: nothing is selected and the assistant stays put, and `CLAUDE.md` lists it with the deliberate exclusions.
- Reload after a failed load reloaded the page from *before* the failure, which WebKit still holds, and never asked for the failed address again. It retries now; on the phone this is the menu's Reload.
- A page with no title of its own — plain text, an image, a bare document — and one that names itself from a script after it finished were recorded in history as "Loading…" for good, on both platforms. An untitled page is named by its address (`example.com/docs/notes.txt`). The first real title after a page finished replaces the recorded one, once. A repeat visit within 30 seconds corrects the title rather than being dropped. The star refused neither "Loading…" nor "Opening …", which Add Bookmark already refused; it does now.
- An address typed without a scheme went over HTTPS even when it was this machine or the local network, so `localhost:3000`, `printer.local` and `192.168.1.1` were asked for over HTTPS, which a development server or a router rarely answers. Those go over HTTP now. Everything else still goes over HTTPS, and a test holds both.
- Extraction cuts a page at 48,000 UTF-16 units. A cut inside an emoji left half a surrogate pair, which WebKit cannot hand back, so Analyze Page, Copy for AI and Reader failed on any long page whose cut fell there. The cut steps back one unit instead, in the app and in the extension's own copy.
- The document under every start surface was a page from before the AI guide: the Clearframe "C", a ⇧⌘C hint a phone has no key for, and "the bar above" on a phone whose bar is below. It showed around the Mac's progress card and, on the phone, with nothing over it, while a new tab loaded. It is a blank page in the system's light or dark now.
- A window closed while comparing came back still comparing, with a second column whose conversation had been torn down. An assistant that had stepped aside for a narrow window came back by itself into the revived window, a panel nobody opened. A closed window's assistant starts clean now.
- New Tab in Group, from a tab group's menu, was a door that made no room for its page. It is the fourteenth door and was the only one with no row in the doors test; it has one now.

*Bookmarks, completion and import*

- Renaming a bookmark or changing its address moved it to the end of its folder: `updateBookmark` rebuilt the record without its position.
- Deleting a folder moved what it held up a level with the positions it had *inside* the folder, so they interleaved with the parent's: X, Y and the folder's A, B came back as A, X, B, Y.
- Deleting the folder open in the Bookmark Manager left the page on a folder that no longer existed. It showed nothing, as though every bookmark had been deleted. It goes to the parent now, or to everything when the folder went from somewhere else.
- A timestamp near `Int64.min` in a Chrome bookmarks file underflowed the importer's epoch subtraction, which Swift traps on, so importing that file quit the app. That field is dropped now and the import continues.
- A name typed with its own punctuation, `node.js`, found nothing: titles were split at every non-letter and the typed term only at spaces. Both split the same way now.
- With a pinned tab selected, the tab strip divided its width as if there were one more tab than there were. Every tab drew narrower than it needed to, and a strip that fitted could scroll.

*Risk signals: the app and the extension agree again*

- The phrase lists had drifted apart between Swift and JavaScript. The extension bounded words with `\b`, which is ASCII in JavaScript. It also counted its ±180-character windows and 30,000-character prefix in UTF-16 units where Swift counts characters. As a result, the same page could raise a signal in one runtime and not the other. The lists are one list now, every term is bounded with the lookarounds `CLAUDE.md` prescribes, and both runtimes count graphemes.
- `local-analysis-contract.json` gains eight `riskCases` and a new `riskWindowCases` key, which describes pages too long to write out: 20,000 emoji before a phrase that only a grapheme count reaches. 46 cases across 8 keys.

*Downloads and dialogs*

- A name a site suggests is reduced to a plain file name: folders, control characters and leading dots are removed. `../../etc/passwd` arrives as `passwd`. Replace in the save dialog no longer removes a folder that happens to have the chosen name, with everything in it.
- The downloads panel's empty state no longer promises a save dialog when "Ask where to save each file" is off.
- From a site's second JavaScript dialog on, both platforms offer to stop that site's dialogs (`PageDialogGuard`, shared). A page asking in a loop held the whole window, because each dialog must be answered before anything else can be touched. The guard and the phone's button are tested. The Mac's checkbox is an `NSAlert` suppression button, which no test presses.

*The phone*

- A page's `alert()`, `confirm()` or `prompt()` froze the page for the life of its tab whenever a sheet was up. The tab switcher, the menu, Bookmarks, History and the address sheet are all sheets. The dialog was presented from the window's root, UIKit refused that without a word, and nothing ever answered the page. Dialogs now go over whatever is on top and wait for a sheet still arriving or leaving. When they truly cannot be shown, they are answered as a dismissal would answer them. Each is answered exactly once.
- Touch and hold on a picture offers Save to Photos, and iOS ends an app that adds to the photo library without `NSPhotoLibraryAddUsageDescription`. The key was missing, so saving any picture crashed the app.
- Setting the application name for the user agent replaced WebKit's own `Mobile/15E148` token. The phone told websites it was desktop Safari, and sites that look for "Mobi" sent it their desktop pages. Proven by removing the fix and watching `navigator.userAgent` lose the token.
- A failed load drew nothing: the tab kept the previous page, or a blank one, under the failed address. It now says so in the Mac's words, with Try Again and Start Page.
- The address pill's outline fills as a page loads. The phone showed nothing while loading.
- A link to a file the phone cannot save did nothing at all, not even a message. It now says "This file was not downloaded: Limeghost cannot save files on this device yet."

*The test suite*

- `testAProfilePictureIsCopiedInAndCroppedSquare` copied a picture into the real `~/Library/Application Support/Limeghost/Profiles/<uuid>` and never removed it, so every run of the Mac suite left one more folder. The development Mac held 147. Three belong to real profiles and 144 to none; they were counted, not removed. The test removes its folder now: one run went from 147 to 148 before the fix and left 148 after it.

*Found and not fixed*

- A typed address on a port WebKit restricts, such as `:1`, commits `about:blank`, and the tab reads it as the AI guide.
- On the phone, a tab whose web content process iOS ended in the background is not reloaded on return. Reload and Try Again recover it now.
- Applying an import calls `BookmarkCollection.addBookmark` once per record, and each call scans every bookmark twice and inserts at the front, so the work grows with the square of the file. It has not been measured on a large file.
- The Bookmark Manager sorts by name or date, while the bar keeps the order somebody arranged. It is not decided which is intended.
- `IdentityColor` imports SwiftUI inside `LimeghostShared`, whose boundary promises none.
- Neither app declares location access: no usage description on either, and no location entitlement on the Mac. A page that asks where you are, such as a map or a store finder, cannot find out. Whether it should is a product decision.
- The phone's target includes iPad (`TARGETED_DEVICE_FAMILY = "1,2"`), and its plist lists three orientations. Apple's upload check requires all four for an iPad app that supports multitasking (ITMS-90474). Untested: nothing has been uploaded.
- When files save without asking, `decideDestinationUsing` never checks whether the download was cancelled a moment earlier; the save-dialog path does. A Cancel that lands there can end as "Failed" rather than "Cancelled". Not reproduced.

Tests: the Mac 590, up from 525; `LimeghostSharedLayer` 322 on both destinations, up from 276; the phone 92, up from 83; the extension's 14 and `validate` clean. On a fresh simulator, the first WebKit page took 64 seconds to load, so the shared tests wait up to 90 seconds for it.

### Week of September 10–16, 2026

**The phone gets your own assistant**

- A button in the bottom bar, lit while open, opens the person's own ChatGPT, Claude, Gemini, Le Chat or Grok over the page, on their own account. It has a grabber, a header with the assistant's menu, "your own account" and ×, and a swipe down to close. It is one layer in one place in the view tree, never a sheet. Designed on September 13 with a design canvas; the spec is `docs/superpowers/specs/2026-09-13-ios-assistant-design.md`.
- Every door makes it leave, and the button brings it back with the conversation still loaded. Reader and Find in Page from the menu make it leave too.
- A sign-in window a provider's page opens appears over the assistant instead of as a tab hidden behind it, and closes itself after signing in. `BrowserWorkspace` takes an `AssistantPopupPlacement` from its host; the Mac keeps tabs.
- A provider page that WebKit ended reopens its conversation: at once on screen, on the next show when hidden, and not again within 30 seconds. The Mac's assistant gets this too.
- The bar steps aside while the keyboard is up, and a page notice moves to its own strip above the bar while the assistant is open. The design canvas showed the banner landing on the provider's message box.
- The phone told websites it was Safari 26.5 on any iOS, a number that stands in for a Mac's. It now claims the version its own iOS carries.
- A test pushed with the assistant's model was left failing for one commit. It still watched the old "un-expand" proxy, and was fixed in the next.
- Tests: the Mac 525, up from 517; `LimeghostSharedLayer` 276, up from 268; the phone 83, up from 73. **Sign-in inside the phone's web view is untested.**

**The phone gets Bookmarks and History**

- Two rows in a third card of the page menu open sheets over the page. Bookmarks has folders to tap into, in the store's order; a search across every folder; Open in New Tab, Rename…, Move to…, delete by swipe or menu; and New Folder. History has visits by day, search, delete, and Clear History, which asks first and names this device rather than the Mac. Designed on September 13; the spec is `docs/superpowers/specs/2026-09-13-ios-bookmarks-history-design.md`.
- Both open pages through the workspace's existing `open(_:)` and `open(_:inNewTab:)`. The phone added no door.
- A folder holding anything asks before it is deleted, in the Mac's words, and its bookmarks move up a level rather than going with it. Choosing a new bookmark's folder, which the page menu left for this step, is Move to….
- `BookmarksHomeSearch` and `HistoryHomeSearch` moved out of the Mac's two page files into `LimeghostCore`, with their tests, so both platforms search through one copy.
- The phone never handed its captured site icons to its views, so every site icon it drew was the fallback square, the AI guide's included. It does now.
- `LimeghostIconView.swift` is the seventh Mac file the phone compiles by reference. It compiled for iOS unchanged.
- Tests: the Mac 517, the same total, with two moved from `BrowserBehaviorTests` to `LimeghostCoreTests`; `LimeghostSharedLayer` 268, up from 266; the phone 73, up from 50.

**The phone gets its page menu**

- A `•••` sheet in the bottom bar: Reader and Copy for AI as two large buttons, then Reload, Forward, New Tab, New Private Tab, Add Bookmark, Find in Page, Share and Request Desktop Site. On the AI guide the page rows are greyed and the two new-tab rows still work. Designed with the founder on September 11–12; the spec and a design canvas are in `docs/superpowers/specs/2026-09-12-ios-page-menu-design.md`.
- The sheet opens as tall as its rows. At the half-screen detent first designed, Share and Request Desktop Site would have opened below the fold on a 13 Pro Max, and most of the second card on an SE.
- Reader on the phone is the Mac's own `ReaderView`, now compiled by both apps, with a two-row header a finger can use. The Mac keeps its single row and a test holds it there — drawing the phone's rows on the Mac fails it at 39 points against 39.
- Copy for AI confirms each copy on the phone in words, because the menu closes as it copies and iOS shows nothing when an app writes to the clipboard. The Mac still says nothing about a clean copy, on purpose.
- Find in Page says “No results” or nothing at all. The first conversation about this menu promised “3 of 12”; WebKit reports no count, so none is shown.
- The page-load hook is now `BrowserSession.decide(…)`, a pure function tested branch by branch on both platforms — no test reached those branches before. Its delegate answers WebKit's `preferences:` form of the policy question, which is what carries the phone's per-tab Request Desktop Site. The Mac never turns that on, so its navigations are unchanged.
- Tests: the Mac 516, up from 504; `LimeghostSharedLayer` 266 on both destinations, up from 256; the phone 50, up from 28.

**The traffic lights stay inside the title bar on macOS 14 and 15**

- The chips' centre line needs a title bar at least 30 points tall; macOS 26 draws 32 and macOS 15 draws 27, so on macOS 14 and 15 the buttons had been set 3 points below their container since September 2 — hanging out of the superview, where AppKit delivers no clicks. Found by CI the first time it ran on macOS 15, with every local test green. `TabStripMetrics.trafficLightOrigin` now keeps them on the line where it fits and at the bar's bottom where it does not, and a test pins both.
- CI's `ios-simulator` job picks the newest iOS runtime rather than the first iPhone in dictionary order, and prints its choice, so a failure there names its own environment.

**The Mac's uncommitted week, committed, and the two platforms on one line again**

- Three sittings of Mac work from September 2–3 had been installed then and never committed. They became three commits, split by hunk. Each was tested alone in a clean copy of its own tree, at 477, 480 and 487 tests.
  - `ded3b37`: the traffic lights sit on the tab chips' centre line, and the chrome's controls share one height.
  - `c357511`: the AI home's repairs. They bring the real mark instead of Clearframe's "C", one opaque card surface, theme tokens throughout, and three dated trends quoted from Epoch AI under CC BY 4.0.
  - `d26e6d4`: the bookmarks home becomes a tree, and the page is named the Bookmark Manager.
- `feature/ios-pocket-browser` merged them (`49988cd`). One file conflicted as text; the other eight files both sides touched merged on their own.
- **The merge broke the phone without a single failing test anywhere.** `c357511` made `AIToolStartPage.swift`, which the iPhone app compiles by reference, depend on five things the iOS target lacked: `BrandMark`, `HomeSearchField`, `HomeEmptyNote`, `startSurfaceCard()` and a new `openReference` argument. `2718108` gives the phone all five:
  - `StartSurfaceChrome.swift` joins its build by reference.
  - `BrandMark` moves to a file of its own. It decodes with ImageIO and asks each app where its artwork lives, and the phone's bundle now carries the image.
  - The guide's third door goes through `workspace.open(_:)`.

  Each of the three new phone tests was watched failing first.
- **The phone's release gate got worse, as measured on the simulator.** The same Mac commit gave the guide's "Local guide · official links" badge `.fixedSize()`, which is right for the Mac. At 402pt the badge keeps its full width, and the headline beside it now breaks almost letter by letter; the search field is pushed off screen. The merge improved two things there: the real mark and the removed build string.
- A rule, now in `AGENTS.md` and `CLAUDE.md`: a change to any file the phone compiles by reference, or to `LimeghostCore` or `LimeghostShared`, runs the phone's suite too.
- **First install on a real iPhone**: the founder's own, on September 10.
  - Wi-Fi could not connect (`CoreDeviceError 4000`); a cable worked.
  - Free provisioning allows three self-installed apps per phone. The slots were taken, and the install succeeded once one was freed.
  - The app ran as `com.zincoo.limeghost.dev`, with the team passed on the command line so the project file never records one.
  - The seven-day certificate expires September 17.
- **The phone's release gate is fixed** (`2801f94`).
  - The guide's header holds the same four things in two arrangements and takes the first that fits: the Mac's one row where it fits, stacked anywhere narrower. The status line and the tool row follow the same rule.
  - `testTheGuidesHeaderFitsAPhonesFirstScreen` failed at 2,076, 1,304 and 631 points on three iPhone widths before the fix, and holds the header under 280 now.
  - A pixel comparison found the Mac's header unchanged, within rendering noise.
- 504 Mac tests, 2 skipped, 0 failures; 28 iOS tests, 0 failures. `LimeghostSharedLayer` (256 tests) passes on the iPhone simulator and on the Mac. No observed-user session has been run on either platform.

### Week of September 3–9, 2026

**A browser on the phone, and an honest account of how far it reaches**

- `ios/Limeghost.xcodeproj` is a real iOS app. It has tabs, a bottom bar within a thumb's reach, an address sheet with local-only completion, a tab switcher that keeps private tabs visibly apart, and the AI guide as the surface every new tab opens on. All of it drives the **Mac's own `BrowserWorkspace`** through `LimeghostShared` rather than a phone-shaped copy — which is the point of the shared layer, and the reason every door on the phone already calls `makeRoomForPage()`. The rule that a door uncovers the page half-shipped on the Mac once, when one door stepped aside and nine did not; writing the doors a second time for iOS is how that happens again.
- Three Mac SwiftUI files — `AIToolStartPage.swift`, `LimeghostTheme.swift`, `SiteIconView.swift` — are compiled into the iOS target *by reference*, from their existing paths under `macos/`, so there is one copy of each and the Mac build is untouched. They were chosen by measuring that these three, and only these three, typecheck together against the iOS SDK.
- **And that measurement was not enough, which is this week's lesson: typechecking is not fitness.** Run at 402pt, the AI guide's headline occupies eight lines from y≈300 to y≈1100 of an 874pt screen, breaking "Choose" mid-word into "Choo / se"; the catalog status wraps to "Catalog / 2026.08. / 24.1"; and nothing actionable — not the search field, not the first chips — is above the fold. The compiler has no opinion about a 402-point screen. It took looking at the thing running. `docs/ios-browser-foundation.md` records it as a named blocking release gate with the three sites (`AIToolStartPage.swift:73-104`, `:50-68`, `:190`), because the guide is the start surface and an unusable start surface makes the app unshippable at phone width. A container-level fix was investigated and none is clean; it needs the file edited or a seam added.
- **A privacy inconsistency, found while writing the rest of this down, and closed.** The phone's address sheet was completing a private tab from the ordinary profile's bookmarks and history. The Mac has never done that — `BrowserView.addressSuggestions` opens with `guard !session.isPrivate` — and `docs/privacy-and-safety.md` states it as a promise: nothing is written in a private tab either way, but reading a saved history back onto the screen would work against what a private tab is for. The sheet's own comment had recorded that there was no way to open a private tab when it was written and that the guard had to arrive with whichever task added one; the tab switcher added them and the note stayed a note. **A note left for a future task is not a guard**, and a documented privacy boundary that one platform keeps and the other does not is not a gate to record — it is a line to fix. The guard is in, and its test is one that can fail: it seeds a visit, proves the prefix completes in an ordinary tab, then asserts nothing comes back in a private one. Verified by mutation — remove the guard and it goes red at that assertion, restore it and the suite is green.
- Signing is now automatic with a deliberately **empty** `DEVELOPMENT_TEAM` — a team identifier belongs to the person holding the Apple ID, not in a shared repository. `CODE_SIGNING_ALLOWED` and `CODE_SIGNING_REQUIRED` became `[sdk=iphonesimulator*]`-conditional rather than unconditional `NO`: the Simulator path is unchanged and still needs no identity, which is what CI requires, while a device build signs normally, which an unsigned bundle could never do.
- **Nothing has been installed on a phone.** The device steps are written down in `docs/ios-browser-foundation.md` as a numbered procedure for the founder — sign in, pick the personal team, connect, run, then trust the developer on the phone — and stated as *not performed* rather than implied to be done. Free provisioning issues a **seven-day** certificate: the app stops launching after a week and comes back only by running it from Xcode again, and it reaches only the devices attached to that one Apple ID. Nobody but the founder can install it until Developer Program enrolment.
- **The iOS simulator platform is now installed here, which changes what a local check can claim.** Until this week the repository's own instructions said this machine had none and that an `xcrun swiftc -typecheck` against the iOS SDK stood in for a Simulator build. That was true when written and is no longer: iOS 26.5 was installed on September 3, `xcodebuild -showdestinations` lists iPhone 17 Pro as eligible rather than ineligible, and both the app's suite (24 tests) and `LimeghostSharedLayer` have been run on a simulator here. `AGENTS.md` and `CLAUDE.md` had been left saying the old thing and were corrected, because they are what the next agent reads first — an instruction file teaching the method this week disproved is worse than no instruction at all. **The CI job itself has still never run**, and that part stands unchanged.
- CI's existing `ios-simulator` job gained a second step that builds and tests the app on the simulator it already discovers. Not a second job, and `macos-browser` untouched. The project carries no checked-in scheme; `xcodebuild` autocreates one, which was verified from a tracked-files-only copy of the repository — 23 tests, `** TEST SUCCEEDED **` — rather than assumed, because a missing scheme is a failure with nothing in the diff to explain it. **The job itself has still never run**, since `ci.yml` triggers only on push to `main` and on pull requests.
- Two findings carried forward rather than lost. **History records "Loading…" as the title of every visited page**, so every address-completion row reads "Loading…": `BrowserSession.refreshState()` falls back to that placeholder when `webView.title` is empty, `didFinish` passes it straight to `onCompletedVisit`, and `recordVisit`'s 30-second dedupe drops the correction that would have fixed it — so it is permanent in history. Nothing in that chain is iOS-specific; it is a WebKit timing race observed on iOS in code both platforms share, and the follow-up must measure both before deciding where the fix belongs. And the shelf grid at `AIToolStartPage.swift:190` overflows arithmetically — six fixed columns of about 40.3pt holding hard-framed 44pt marks — which is arithmetic and not observation, because that grid sits below the fold.
- 492 Mac tests, 0 failures; 23 iOS tests, 0 failures. There is no assistant, no Reader, no Copy for AI and no bookmark import in the phone app, and no document says otherwise. **No observed-user session has been run for this project on either platform.**

### Week of September 1–3, 2026

**A shared layer, so a phone can run the same rules**

- iOS was a non-goal in `docs/product-foundation.md` until September 2, 2026, when the founder reversed it: the non-goal was written against the cost of a second rendering engine, and iOS mandates WebKit, which is already this browser's engine. The reasoning is recorded in `docs/project-context.md`; the sentence in `docs/limeghost-strategy.md` saying the next differentiated feature should not start "before an outside tester can install the app at all" stays, with iOS recorded as a conscious, dated exception to it, alongside the founder's August 24 decision to dogfood rather than recruit testers. Nobody but the founder can install this yet, on either platform.
- The first implementation step is a new SwiftPM target, `LimeghostShared`, sitting between the existing `LimeghostCore` (Foundation-only, unchanged) and `LimeghostBrowser` (macOS chrome, unchanged in kind). Across nine tasks, 23 files moved into it — `BrowserSession` and `BrowserWorkspace` behind new platform-seam protocols, the assistant (`AICompanion`), the bookmark/history/preference stores, site icons, content-blocking and search settings, page find, onboarding, and more — moved rather than rewritten, with `git log --follow` confirmed on every rename. `LimeghostShared` takes no `#if os(...)`: a platform difference is a protocol member (`BrowserSessionPlatform`; the workspace's `PageSharing`/`ClipboardWriting`) that macOS implements today and iOS will implement later, never a conditional inside the model.
- **The method for deciding what could move was wrong at the start, and stayed wrong for most of nine tasks before it was named.** The design had grouped files by whether they imported AppKit. `import SwiftUI` re-exports AppKit on macOS, so that test is wrong in both directions: `WebView.swift`, `TabStripViews.swift`, `LimeghostBrowserApp.swift`, and `SiteInformationViews.swift` use `NSViewRepresentable`, `NSEvent`, `NSApplicationDelegateAdaptor`, and `openSettings` while importing none of AppKit by name, and would have been counted portable; other files carried an unused `import AppKit` a grep would have flagged and cost nothing to delete. The check that held up instead: `xcrun --sdk iphonesimulator swiftc -typecheck`, against the real iOS 17 SDK. Portability is a compiler question, not a grep question — see [docs/ios-browser-foundation.md](docs/ios-browser-foundation.md).
- One file, `BookmarkImportSources.swift`, does not fit either fate cleanly, and the design had not anticipated that: it imports only `Foundation`, but `fileManager.homeDirectoryForCurrentUser` — used to find Safari's bookmarks export — is unavailable on iOS specifically, not an AppKit problem at all. It needs its own platform seam before an iOS bookmark-import bridge can be built.
- **A real, silent bug, found by moving code rather than by a test.** `BrowserSession`'s WebKit delegate method for `<input type="file">` moved into an app-target extension, and Objective-C's implicit `@objc` inference does not run for an extension member declared outside its type's own module — no selector was emitted at all, so file uploads would have quietly stopped working with every existing test still green. `testASessionAnswersWebKitsOpenPanelRequest` now guards the explicit `@objc(webView:runOpenPanelWithParameters:initiatedByFrame:completionHandler:)` this needed.
- The door rule (`testEveryWayOfAskingForAPageUncoversIt`) and the assistant's width thresholds (`AssistantLayout`, extracted from `AICompanion`'s `companionWidth`/`minimumReadableWidth` constants) now live in `LimeghostSharedTests` and run as the same tests on both platforms, not a second copy standing in for one. A CI job builds and tests them against a real iOS Simulator on GitHub's macos-15 runner, through a scheme (`LimeghostSharedLayer`) committed at `.swiftpm/xcode/xcshareddata/xcschemes/`, because SwiftPM's own per-product schemes carry no test action at all. **That job has never been observed passing here**: this machine has no iOS platform component installed. What was verified locally is narrower, and `docs/ios-browser-foundation.md` says so exactly that way — the scheme resolves, it passes on `platform=macOS` (249 of the suite's tests), and its own build graph names only the four portable targets.
- 492 tests, 0 failures. No document claims signing, notarization, TestFlight, App Store readiness, or user validation for iOS — there is no iOS app yet, only the shared ground under one.

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
