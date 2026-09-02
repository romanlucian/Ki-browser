# Limeghost Shared Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract every platform-neutral model, store and controller out of the macOS UI target into a new `LimeghostShared` target that compiles for both macOS and iOS, so the browser's rules exist once and are tested once.

**Architecture:** `Package.swift` declares `.iOS(.v17)` alongside `.macOS(.v14)` and gains `LimeghostShared` (depending on `LimeghostCore`) plus `LimeghostSharedTests`. `LimeghostBrowser` depends on Shared and keeps only AppKit-bound chrome. The two files with real AppKit contact — `BrowserSession` and `BrowserWorkspace` — move behind small protocols whose macOS implementations are the existing code relocated, so behaviour does not change. No iOS app is built by this plan; its deliverable is the boundary plus proof it compiles and tests green for the iOS Simulator.

**Tech Stack:** Swift 6 toolchain in language mode 5, SwiftPM, XCTest, WebKit, Combine. Xcode 26.6, iPhoneSimulator 26.5 SDK, iOS 26.2 simulator runtime. No third-party dependencies.

**Spec:** [docs/superpowers/specs/2026-09-03-ios-pocket-browser-design.md](../specs/2026-09-03-ios-pocket-browser-design.md)

**Plan 1 of 3.** Plan 2 builds `ios/Limeghost.xcodeproj` and the phone shell; Plan 3 builds the assistant overlay, Reader, Copy for AI and the bookmark bridge. Neither can start until this one lands.

## Global Constraints

- **No `#if os(iOS)` in `LimeghostShared`.** Platform differences enter through protocols only. (Spec §3.5)
- **Preference keys stay `clearframe.*`** on both platforms. Do not rename them. (Spec §6.2, CLAUDE.md)
- **The bundle identifier `com.clearframe.browser` does not change** in this plan. (CLAUDE.md)
- **Behaviour must not change on macOS.** Every one of the 476 existing tests passes at every commit. A moved file is moved, not rewritten.
- **Swift language mode 5** (`swiftLanguageModes: [.v5]`), targets `.macOS(.v14)` and `.iOS(.v17)`.
- **No third-party dependencies**, including in tests. (`docs/ip-and-ownership.md`)
- **See a test fail before you make it pass.** Every behaviour step here has an explicit "run it and watch it fail" step; do not skip it.
- **The other session is editing the desktop branch.** Before starting, confirm with the user that `feature/remove-judgment-layer` has landed or that these files are not open there: `AIToolStartPage.swift`, `BookmarkBarViews.swift`, `BrowserView.swift`, `HistoryHomePage.swift`, `LimeghostTheme.swift`, `StartSurfaceChrome.swift`, `TabStripLayout.swift`, `TabStripViews.swift`, `WindowChromeSupport.swift`, `BrowserBehaviorTests.swift`.
- **Verified baseline, measured September 3, 2026** (do not re-derive):
  - `LimeghostCore` typechecks clean for `arm64-apple-ios17.0-simulator` — 31 files, exit 0.
  - 29 of 60 UI files are already iOS-clean; 4 more become clean by deleting a stale `import AppKit`.
  - `import SwiftUI` re-exports AppKit on macOS, so "does not import AppKit" is **not** evidence of portability. Verify with the compiler, never with grep.

- **How to verify iOS portability on this machine.** Xcode 26.6's **iOS platform is not
  installed** — `xcodebuild -showdestinations` lists iOS under "Ineligible destinations"
  (`iOS 26.5 is not installed`), and a leftover iOS 26.2 simulator runtime does not
  satisfy it. So `xcodebuild` cannot build or test for iOS here, while the SDK stub on
  disk means the compiler can. Every iOS check in this plan therefore uses:

  ```bash
  cd macos/LimeghostBrowser/Sources
  xcrun --sdk iphonesimulator swiftc -typecheck -swift-version 5 \
    -target arm64-apple-ios17.0-simulator LimeghostCore/*.swift
  ```

  Expected: exit 0, no output. To check `LimeghostShared` as well, first emit a Core
  module and pass it with `-I`:

  ```bash
  cd macos/LimeghostBrowser/Sources
  xcrun --sdk iphonesimulator swiftc -emit-module -module-name LimeghostCore \
    -swift-version 5 -target arm64-apple-ios17.0-simulator \
    -emit-module-path /tmp/limeghost-ios/LimeghostCore.swiftmodule LimeghostCore/*.swift
  xcrun --sdk iphonesimulator swiftc -typecheck -swift-version 5 \
    -target arm64-apple-ios17.0-simulator -I /tmp/limeghost-ios LimeghostShared/*.swift
  ```

  Create `/tmp/limeghost-ios` first. **Do not** use `xcodebuild` for any iOS step in this
  plan; it will fail with a misleading destination error. Running the shared tests on a
  real Simulator waits on the platform download and belongs to CI (Task 9), whose runner
  has it installed.

---

### Task 1: Declare iOS and create the empty shared target

**Files:**
- Modify: `macos/LimeghostBrowser/Package.swift`
- Create: `macos/LimeghostBrowser/Sources/LimeghostShared/PlatformSurface.swift`
- Create: `macos/LimeghostBrowser/Tests/LimeghostSharedTests/PlatformSurfaceTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: the `LimeghostShared` target and the `LimeghostSharedTests` target; `LimeghostShared.frameworkIsReachable` as a smoke symbol proving the target links on both platforms.

- [ ] **Step 1: Write the failing test**

Create `macos/LimeghostBrowser/Tests/LimeghostSharedTests/PlatformSurfaceTests.swift`:

```swift
import XCTest
@testable import LimeghostShared

final class PlatformSurfaceTests: XCTestCase {
    /// The shared target exists and links on whichever platform is running
    /// this test. It is deliberately trivial: its job is to fail the build
    /// when the target is missing, not to assert anything about behaviour.
    func testTheSharedTargetLinks() {
        XCTAssertTrue(LimeghostShared.frameworkIsReachable)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd macos/LimeghostBrowser && swift test --filter PlatformSurfaceTests
```

Expected: FAIL — `no such module 'LimeghostShared'`.

- [ ] **Step 3: Add the target and the symbol**

Create `macos/LimeghostBrowser/Sources/LimeghostShared/PlatformSurface.swift`:

```swift
import Foundation

/// The browser's platform-neutral layer: models, stores, the session, the
/// workspace and the assistant. Everything here compiles for macOS and iOS.
///
/// **There is no `#if os(...)` in this target.** Where a platform differs, the
/// difference enters through a protocol whose implementation lives in that
/// platform's own target. A conditional here would mean two behaviours behind
/// one name, which is what this boundary exists to prevent.
public enum LimeghostShared {
    /// Linked and reachable. Asserted by `PlatformSurfaceTests` so a missing or
    /// misconfigured target fails as a test rather than as a mystery later.
    public static let frameworkIsReachable = true
}
```

In `macos/LimeghostBrowser/Package.swift`, change the `platforms` array and add two targets. The file becomes:

```swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LimeghostBrowser",
    platforms: [
        .macOS(.v14),
        // iOS 17 is the floor: `WKWebsiteDataStore(forIdentifier:)`,
        // `.focusable` on iOS, and `onChange(of:initial:)` all arrive there.
        .iOS(.v17)
    ],
    products: [
        .executable(name: "LimeghostBrowser", targets: ["LimeghostBrowser"]),
        // The iOS app is an Xcode target that consumes these two as a local
        // package; SwiftPM cannot build an iOS app itself.
        .library(name: "LimeghostShared", targets: ["LimeghostShared"])
    ],
    targets: [
        .target(name: "LimeghostCore"),
        .target(
            name: "LimeghostShared",
            dependencies: ["LimeghostCore"],
            linkerSettings: [
                .linkedFramework("WebKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech")
            ]
        ),
        .executableTarget(
            name: "LimeghostBrowser",
            dependencies: ["LimeghostCore", "LimeghostShared"],
            // The brand mark, so the address bar can draw it. The copy under
            // `Resources/` is exactly the small mark from
            // `docs/brand/limeghost-mark-2026-08-31/`, which stays the source of
            // truth — replace both together, and keep the *small* one here: the
            // full mark's ring turns to mud below 32 px.
            resources: [.process("Resources")],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech"),
                .linkedFramework("WebKit"),
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "LimeghostCoreTests",
            dependencies: ["LimeghostCore"],
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "LimeghostSharedTests",
            dependencies: ["LimeghostShared", "LimeghostCore"]
        ),
        .testTarget(
            name: "BrowserBehaviorTests",
            dependencies: ["LimeghostBrowser", "LimeghostCore", "LimeghostShared"]
        )
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 4: Run it and watch it pass**

```bash
cd macos/LimeghostBrowser && swift test --filter PlatformSurfaceTests
```

Expected: PASS, 1 test.

- [ ] **Step 5: Prove the whole Mac suite is unchanged**

```bash
cd macos/LimeghostBrowser && swift test 2>&1 | tail -5
```

Expected: `Executed 477 tests, with 2 tests skipped and 0 failures` (476 before, plus the new one).

- [ ] **Step 6: Prove Core and Shared compile for iOS**

```bash
mkdir -p /tmp/limeghost-ios
cd macos/LimeghostBrowser/Sources
xcrun --sdk iphonesimulator swiftc -emit-module -module-name LimeghostCore \
  -swift-version 5 -target arm64-apple-ios17.0-simulator \
  -emit-module-path /tmp/limeghost-ios/LimeghostCore.swiftmodule LimeghostCore/*.swift
xcrun --sdk iphonesimulator swiftc -typecheck -swift-version 5 \
  -target arm64-apple-ios17.0-simulator -I /tmp/limeghost-ios LimeghostShared/*.swift
echo "exit: $?"
```

Expected: `exit: 0` with no diagnostics. See the iOS-verification note in Global Constraints for why this is a typecheck rather than an `xcodebuild` invocation.

- [ ] **Step 7: Commit**

```bash
git add macos/LimeghostBrowser/Package.swift \
        macos/LimeghostBrowser/Sources/LimeghostShared \
        macos/LimeghostBrowser/Tests/LimeghostSharedTests
git commit -m "Declare iOS, and open a target for the rules both platforms share

Nothing moves into it yet. The empty target and its one linking test are
the boundary itself: from here, a file that compiles here compiles for a
phone, and a file that cannot has to say why."
```

---

### Task 2: Delete four stale AppKit imports

Four files import AppKit and use nothing from it. Deleting the import is the whole change, and it makes each of them compile for iOS.

**Files:**
- Modify: `macos/LimeghostBrowser/Sources/LimeghostBrowser/BrowserPreferences.swift:1`
- Modify: `macos/LimeghostBrowser/Sources/LimeghostBrowser/AISettingsView.swift:1`
- Modify: `macos/LimeghostBrowser/Sources/LimeghostBrowser/BookmarkLibraryViews.swift:1`
- Modify: `macos/LimeghostBrowser/Sources/LimeghostBrowser/DownloadViews.swift:1`

**Interfaces:**
- Consumes: nothing.
- Produces: `BrowserPreferences` becomes movable in Task 6.

- [ ] **Step 1: Confirm each file really uses no AppKit**

```bash
cd macos/LimeghostBrowser/Sources/LimeghostBrowser
for f in BrowserPreferences AISettingsView BookmarkLibraryViews DownloadViews; do
  echo "$f: $(grep -c 'NS[A-Z][A-Za-z]*' $f.swift) NS-symbol lines"
done
```

Expected: `0` for all four. If any is non-zero, stop — that file is not in this task; report it.

- [ ] **Step 2: Delete the import from each**

Remove the single line `import AppKit` from the top of each of the four files. Change nothing else.

- [ ] **Step 3: Run the whole suite**

```bash
cd macos/LimeghostBrowser && swift test 2>&1 | tail -5
```

Expected: `Executed 477 tests … 0 failures`. If a file fails to compile, it used AppKit through SwiftUI's macOS re-export; restore its import and report which one.

- [ ] **Step 4: Commit**

```bash
git add -A macos/LimeghostBrowser/Sources/LimeghostBrowser
git commit -m "Drop four AppKit imports nothing was using

Each of these four files imported AppKit and referenced nothing from it.
On macOS that costs nothing and hides something: SwiftUI re-exports AppKit,
so an unused import is indistinguishable from a real dependency until you
compile for a phone and find out."
```

---

### Task 3: `AssistantLayout` — one home for the width rule

The thresholds live on `BrowserTabContent`, a macOS view, so an iOS view cannot read them and no test can assert them without standing up SwiftUI.

**Files:**
- Create: `macos/LimeghostBrowser/Sources/LimeghostShared/AssistantLayout.swift`
- Create: `macos/LimeghostBrowser/Tests/LimeghostSharedTests/AssistantLayoutTests.swift`
- Modify: `macos/LimeghostBrowser/Sources/LimeghostBrowser/BrowserView.swift:51-53,128-130`

**Interfaces:**
- Consumes: nothing.
- Produces: `AssistantLayout.companionWidth: CGFloat`, `.minimumReadableWidth: CGFloat`, `.fitsBesidePage(width:) -> Bool`, `.fitsTwoAssistants(width:) -> Bool`.

- [ ] **Step 1: Write the failing test**

Create `macos/LimeghostBrowser/Tests/LimeghostSharedTests/AssistantLayoutTests.swift`:

```swift
import XCTest
@testable import LimeghostShared

final class AssistantLayoutTests: XCTestCase {
    /// A phone can never show the assistant beside a page, so the assistant
    /// fills the screen there and Compare is not offered at all.
    func testAPhoneNeverFitsTheAssistantBesideThePage() {
        for width in [390.0, 430.0] {   // iPhone 17 and 17 Pro Max, points
            XCTAssertFalse(AssistantLayout.fitsBesidePage(width: width), "\(width)")
            XCTAssertFalse(AssistantLayout.fitsTwoAssistants(width: width), "\(width)")
        }
    }

    /// An iPad in portrait is a phone as far as this rule is concerned.
    func testAnIPadInPortraitAlsoFillsTheScreen() {
        XCTAssertFalse(AssistantLayout.fitsBesidePage(width: 744))
    }

    /// The band the Mac already has: two assistants fit before an assistant
    /// and a readable page do. Compare is offered; the docked panel is not.
    func testBetweenTheThresholdsCompareIsOfferedButTheDockedPanelIsNot() {
        XCTAssertTrue(AssistantLayout.fitsTwoAssistants(width: 1024))
        XCTAssertFalse(AssistantLayout.fitsBesidePage(width: 1024))
    }

    /// A current iPad in landscape docks the panel by the same rule that
    /// docks it on a Mac. Nothing is special-cased for iPad.
    func testACurrentIPadInLandscapeDocksThePanel() {
        XCTAssertTrue(AssistantLayout.fitsBesidePage(width: 1133))
        XCTAssertTrue(AssistantLayout.fitsTwoAssistants(width: 1133))
    }

    /// The boundary itself, so a refactor cannot drift it by a point.
    func testTheThresholdIsExactlyOneThousandOneHundred() {
        XCTAssertFalse(AssistantLayout.fitsBesidePage(width: 1099))
        XCTAssertTrue(AssistantLayout.fitsBesidePage(width: 1100))
        XCTAssertEqual(AssistantLayout.companionWidth, 500)
        XCTAssertEqual(AssistantLayout.minimumReadableWidth, 600)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd macos/LimeghostBrowser && swift test --filter AssistantLayoutTests
```

Expected: FAIL — `cannot find 'AssistantLayout' in scope`.

- [ ] **Step 3: Write the implementation**

Create `macos/LimeghostBrowser/Sources/LimeghostShared/AssistantLayout.swift`:

```swift
import CoreGraphics

/// How much room the window has, and what that means for the assistant.
///
/// These two numbers used to live on the macOS `BrowserTabContent` view, where
/// an iOS view could not read them and a test could not assert them without
/// standing up SwiftUI. They are the same numbers; only their address changed.
///
/// **One rule serves every screen.** A phone is not a special case — it is a
/// window that never reaches `minimumBesidePage`, so the assistant always fills
/// it, which is what "stepping aside means leaving, not shrinking" already says
/// on a narrow Mac window.
public enum AssistantLayout {
    /// Wide enough for an assistant's own page without forcing its phone layout.
    /// Below the ~640-point breakpoint where providers show their own sidebar,
    /// which suits a side panel. The per-provider breakpoints have never been
    /// measured; do not defend this number as evidenced.
    public static let companionWidth: CGFloat = 500

    /// Below this a page is too narrow to read beside anything.
    public static let minimumReadableWidth: CGFloat = 600

    /// The width at which an assistant and a readable page both fit.
    public static var minimumBesidePage: CGFloat { companionWidth + minimumReadableWidth }

    /// Two readable columns and nothing else.
    public static var minimumForTwoAssistants: CGFloat { companionWidth * 2 }

    /// Can the assistant sit beside the page in a window this wide?
    public static func fitsBesidePage(width: CGFloat) -> Bool {
        width >= minimumBesidePage
    }

    /// Can two assistants sit side by side in a window this wide?
    public static func fitsTwoAssistants(width: CGFloat) -> Bool {
        width >= minimumForTwoAssistants
    }
}
```

- [ ] **Step 4: Run it and watch it pass**

```bash
cd macos/LimeghostBrowser && swift test --filter AssistantLayoutTests
```

Expected: PASS, 5 tests.

- [ ] **Step 5: Point the Mac view at the shared numbers**

In `macos/LimeghostBrowser/Sources/LimeghostBrowser/BrowserView.swift`, delete the two `static let` declarations on `BrowserTabContent` (currently lines 51–53) and replace every use. There are five: two declarations, and `Self.companionWidth` / `Self.minimumReadableWidth` in the `fitsBesidePage` and `fitsTwoAssistants` expressions plus the two `.frame(width:)` calls.

Replace the predicate lines (currently 128–130) with:

```swift
                let fitsBesidePage = AssistantLayout.fitsBesidePage(width: geometry.size.width)
                // Two assistants need two readable columns and nothing else.
                let fitsTwoAssistants = AssistantLayout.fitsTwoAssistants(width: geometry.size.width)
```

and each `Self.companionWidth` with `AssistantLayout.companionWidth`. Add `import LimeghostShared` at the top of the file if it is not already there.

Verify none are left:

```bash
grep -n "Self.companionWidth\|Self.minimumReadableWidth\|static let companionWidth\|static let minimumReadableWidth" \
  macos/LimeghostBrowser/Sources/LimeghostBrowser/BrowserView.swift
```

Expected: no output.

- [ ] **Step 6: Prove the Mac behaviour is unchanged**

```bash
cd macos/LimeghostBrowser && swift test 2>&1 | tail -5
```

Expected: `Executed 482 tests … 0 failures`.

- [ ] **Step 7: Commit**

```bash
git add -A macos/LimeghostBrowser
git commit -m "Give the assistant's width rule one address both platforms can read

500 and 600 lived on a macOS view, so a phone could not read them and no
test could assert them without building SwiftUI. Same numbers, one home,
and now a test states what each screen size means -- including that an
iPhone never fits the panel beside a page, which is why a phone needs no
second layout mode."
```

---

### Task 4: `modifiedAt`, so sync has something to resolve on

Spec §6.6: last-writer-wins needs a timestamp, and adding it in v1 saves v1.1 a migration. Optional, so records written before today still decode.

**Files:**
- Modify: `macos/LimeghostBrowser/Sources/LimeghostCore/BrowserDataModels.swift:215-230,267-284`
- Modify: `macos/LimeghostBrowser/Sources/LimeghostBrowser/BrowserDataStore.swift` (every write site)
- Create: `macos/LimeghostBrowser/Tests/LimeghostCoreTests/BookmarkModifiedAtTests.swift`

**Interfaces:**
- Consumes: `BookmarkRecord`, `BookmarkFolderRecord` from `LimeghostCore`.
- Produces: `BookmarkRecord.modifiedAt: Date?`, `BookmarkFolderRecord.modifiedAt: Date?`.

- [ ] **Step 1: Write the failing test**

Create `macos/LimeghostBrowser/Tests/LimeghostCoreTests/BookmarkModifiedAtTests.swift`:

```swift
import XCTest
@testable import LimeghostCore

final class BookmarkModifiedAtTests: XCTestCase {
    /// Exactly the JSON the app was writing before `modifiedAt` existed. A
    /// record saved yesterday must still decode today, or somebody opens the
    /// browser to an empty bookmarks bar. This is the profile-face precedent:
    /// new fields are optional, and a test decodes the real old bytes.
    func testARecordWrittenBeforeThisFieldExistedStillDecodes() throws {
        let json = """
        {"id":"3F2504E0-4F89-41D3-9A0C-0305E82C3301",
         "title":"Limeghost",
         "url":"https://example.com/",
         "createdAt":768000000,
         "position":0}
        """.data(using: .utf8)!

        let record = try JSONDecoder().decode(BookmarkRecord.self, from: json)

        XCTAssertEqual(record.title, "Limeghost")
        XCTAssertNil(record.modifiedAt, "an absent timestamp must decode as absent, not as now")
    }

    /// The same for folders, which carry the icon and colour a person chose.
    func testAFolderWrittenBeforeThisFieldExistedStillDecodes() throws {
        let json = """
        {"id":"3F2504E0-4F89-41D3-9A0C-0305E82C3302",
         "title":"Reading",
         "emoji":"📁",
         "createdAt":768000000}
        """.data(using: .utf8)!

        let folder = try JSONDecoder().decode(BookmarkFolderRecord.self, from: json)

        XCTAssertEqual(folder.title, "Reading")
        XCTAssertNil(folder.modifiedAt)
    }

    /// And it survives a round trip once set, because sync compares it.
    func testTheTimestampSurvivesARoundTrip() throws {
        let when = Date(timeIntervalSince1970: 800_000_000)
        let record = BookmarkRecord(
            id: UUID(),
            title: "Limeghost",
            url: "https://example.com/",
            createdAt: Date(timeIntervalSince1970: 768_000_000),
            folderID: nil,
            position: 0,
            modifiedAt: when
        )

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(BookmarkRecord.self, from: data)

        XCTAssertEqual(decoded.modifiedAt, when)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd macos/LimeghostBrowser && swift test --filter BookmarkModifiedAtTests
```

Expected: FAIL — `value of type 'BookmarkRecord' has no member 'modifiedAt'`.

- [ ] **Step 3: Add the field to both records**

In `macos/LimeghostBrowser/Sources/LimeghostCore/BrowserDataModels.swift`, add to `BookmarkRecord` (after `position`) and to `BookmarkFolderRecord` (after `parentID`):

```swift
    /// When this record last changed, for the sync that resolves two devices
    /// editing the same bookmark. Optional because every record written before
    /// September 3, 2026 has no such field and must still decode; a decode test
    /// holds the exact old bytes. Nothing reads it yet.
    public var modifiedAt: Date?
```

Add `modifiedAt: Date? = nil` as the last parameter of each memberwise initializer, defaulted so no existing call site changes, and assign it in the body.

- [ ] **Step 4: Run it and watch it pass**

```bash
cd macos/LimeghostBrowser && swift test --filter BookmarkModifiedAtTests
```

Expected: PASS, 3 tests.

- [ ] **Step 5: Stamp it on every write**

In `BrowserDataStore.swift`, find every method that creates or mutates a `BookmarkRecord` or `BookmarkFolderRecord` and set `modifiedAt = Date()` there. Find them with:

```bash
grep -n "BookmarkRecord(\|BookmarkFolderRecord(\|\.title = \|\.folderID = \|\.parentID = \|\.position = \|\.iconID = \|\.colorID = \|\.emoji = " \
  macos/LimeghostBrowser/Sources/LimeghostBrowser/BrowserDataStore.swift
```

Do not stamp it during *load*, migration, or last-known-good recovery — those are reads, and stamping them would make every record look edited on first launch.

- [ ] **Step 6: Run the whole suite**

```bash
cd macos/LimeghostBrowser && swift test 2>&1 | tail -5
```

Expected: `Executed 485 tests … 0 failures`.

- [ ] **Step 7: Commit**

```bash
git add -A macos/LimeghostBrowser
git commit -m "Record when a bookmark last changed, for the sync that will need it

Optional, so the bookmarks somebody saved yesterday still decode -- the
same shape the profile avatars used, and a test holds the exact bytes the
app was writing before this field existed. Nothing reads it yet: iCloud
bookmark sync is designed and waits on Developer Program enrolment, and
adding the field now is what saves that work a migration."
```

---

### Task 5: Move the leaf models and stores

Thirteen files that are already iOS-clean and depend on nothing outside `LimeghostCore` and each other.

**Files:**
- Move into `macos/LimeghostBrowser/Sources/LimeghostShared/`: `BrowserUserAgent.swift`, `BookmarkDragPayload.swift`, `SearchSettingsStore.swift`, `WebFeatureSettingsStore.swift`, `ContentBlockingSettingsStore.swift`, `ContentRuleListProvider.swift`, `PageFindController.swift`, `OnboardingController.swift`, `SiteDataInventory.swift`, `VoiceInputController.swift`, `BrowserPreferences.swift`, `BrowserDataStore.swift`, `AICompanion.swift`

**Interfaces:**
- Consumes: `LimeghostCore` models; `AssistantLayout` from Task 3.
- Produces: all thirteen types visible to both app targets via `import LimeghostShared`.

- [ ] **Step 1: Move the files that have no internal dependents first**

```bash
cd macos/LimeghostBrowser/Sources
for f in BrowserUserAgent BookmarkDragPayload SearchSettingsStore WebFeatureSettingsStore \
         ContentBlockingSettingsStore ContentRuleListProvider PageFindController \
         OnboardingController SiteDataInventory VoiceInputController; do
  git mv LimeghostBrowser/$f.swift LimeghostShared/$f.swift
done
```

- [ ] **Step 2: Build and read the errors**

```bash
cd macos/LimeghostBrowser && swift build 2>&1 | grep "error:" | head -20
```

Expected: errors of the form `cannot find type 'X' in scope` in `LimeghostBrowser` files. Each names a type that is now in Shared.

- [ ] **Step 3: Make the moved types public and add the imports**

For each moved file, add `public` to the type declaration and to every member the app target uses. Add `import LimeghostShared` to each `LimeghostBrowser` file the build named. Repeat build-and-fix until clean.

`ContentRuleListProvider` and `AICompanion` are `@MainActor`; keep that annotation. `public` on a `@MainActor` class requires `public init`, so add explicit public initializers matching the existing ones exactly.

- [ ] **Step 4: Move the three with dependents**

```bash
cd macos/LimeghostBrowser/Sources
git mv LimeghostBrowser/BrowserPreferences.swift LimeghostShared/BrowserPreferences.swift
git mv LimeghostBrowser/BrowserDataStore.swift   LimeghostShared/BrowserDataStore.swift
git mv LimeghostBrowser/AICompanion.swift        LimeghostShared/AICompanion.swift
```

`AICompanion` references `BrowserSession`, which is still in the app target. Until Task 7 moves it, make `AICompanion` generic over its session type is **not** the approach — instead, leave `AICompanion.swift` in the app target for now and move it in Task 7 with `BrowserSession`. Revert just that one move:

```bash
git mv LimeghostShared/AICompanion.swift LimeghostBrowser/AICompanion.swift
```

- [ ] **Step 5: Run the whole suite**

```bash
cd macos/LimeghostBrowser && swift test 2>&1 | tail -5
```

Expected: `Executed 485 tests … 0 failures`.

- [ ] **Step 6: Prove the moved files build for iOS**

```bash
mkdir -p /tmp/limeghost-ios
cd macos/LimeghostBrowser/Sources
xcrun --sdk iphonesimulator swiftc -emit-module -module-name LimeghostCore \
  -swift-version 5 -target arm64-apple-ios17.0-simulator \
  -emit-module-path /tmp/limeghost-ios/LimeghostCore.swiftmodule LimeghostCore/*.swift
xcrun --sdk iphonesimulator swiftc -typecheck -swift-version 5 \
  -target arm64-apple-ios17.0-simulator -I /tmp/limeghost-ios LimeghostShared/*.swift
echo "exit: $?"
```

Expected: `BUILD SUCCEEDED`. This is the first moment the phone has real Limeghost behaviour in it.

- [ ] **Step 7: Commit**

```bash
git add -A macos/LimeghostBrowser
git commit -m "Move twelve settled stores and controllers to the shared target

Tracker blocking, the search choice, find-in-page, the introduction's state,
site data, dictation, preferences and the bookmark store now compile for a
phone. None of them changed; they were already platform-neutral and were
only sitting in a macOS target. The Mac suite is unchanged at 485."
```

---

### Task 6: `FaviconStore` without AppKit

Spec §6.4. Six AppKit lines: an `NSCache<NSString, NSImage>`, two `NSImage(data:)` decodes, one `NSBitmapImageRep` PNG encode. ImageIO is already imported.

**Files:**
- Modify then move: `macos/LimeghostBrowser/Sources/LimeghostBrowser/FaviconStore.swift:57,118,127,132,194,552`
- Create: `macos/LimeghostBrowser/Tests/LimeghostSharedTests/FaviconImageCodingTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `FaviconStore.icon(forHost:) -> CGImage?` (was `NSImage?`); `FaviconStore.pngData(from: CGImage) -> Data?`.

- [ ] **Step 1: Write the failing test**

Create `macos/LimeghostBrowser/Tests/LimeghostSharedTests/FaviconImageCodingTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import LimeghostShared

final class FaviconImageCodingTests: XCTestCase {
    /// A 2×2 opaque square, encoded and decoded, keeps its size. The point is
    /// not the pixels: it is that encoding and decoding go through ImageIO on
    /// both platforms rather than through AppKit on one of them.
    func testAnIconRoundTripsThroughImageIO() throws {
        let context = CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        let source = try XCTUnwrap(context?.makeImage())

        let data = try XCTUnwrap(FaviconStore.pngData(from: source))
        let decoded = try XCTUnwrap(FaviconStore.image(from: data))

        XCTAssertEqual(decoded.width, 2)
        XCTAssertEqual(decoded.height, 2)
    }

    /// Bytes that are not an image return nil rather than throwing, because a
    /// site can serve anything at /favicon.ico and a browser must not crash on it.
    func testGarbageBytesDecodeToNothing() {
        XCTAssertNil(FaviconStore.image(from: Data([0x00, 0x01, 0x02, 0x03])))
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd macos/LimeghostBrowser && swift test --filter FaviconImageCodingTests
```

Expected: FAIL — `cannot find 'FaviconStore' in scope` (still in the app target).

- [ ] **Step 3: Replace the six AppKit lines**

In `FaviconStore.swift`: change `import AppKit` to `import CoreGraphics` and `import ImageIO` (ImageIO is already there). Replace:

```swift
    private let memory = NSCache<NSString, CGImage>()
```

Add two static helpers and route the decode/encode sites through them:

```swift
    /// Decode with ImageIO, which exists on both platforms. `NSImage(data:)`
    /// did this on the Mac and has no iOS twin; `UIImage` would be the iOS
    /// twin and has no Mac one, so neither belongs in a shared file.
    static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Encode with ImageIO, for the same reason.
    static func pngData(from image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, "public.png" as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
```

Change `icon(forHost:)` and `storedIcon(forNormalizedHost:)` to return `CGImage?`.

- [ ] **Step 4: Fix the Mac call sites**

SwiftUI's `Image` takes a `CGImage` directly on both platforms:

```bash
grep -rn "\.icon(forHost:\|Image(nsImage:" macos/LimeghostBrowser/Sources/LimeghostBrowser
```

Replace each `Image(nsImage: icon)` with `Image(decorative: icon, scale: 2)`. Run the suite and confirm site icons still resolve — `BrowserBehaviorTests` covers the store's policy, not its pixels.

- [ ] **Step 5: Move it and run everything**

```bash
cd macos/LimeghostBrowser/Sources && git mv LimeghostBrowser/FaviconStore.swift LimeghostShared/FaviconStore.swift
cd .. && swift test 2>&1 | tail -5
```

Expected: `Executed 487 tests … 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add -A macos/LimeghostBrowser
git commit -m "Decode site icons with ImageIO, so the icon policy exists once

NSImage has no iOS twin and UIImage has no Mac one, so neither belongs in a
file both platforms compile. ImageIO is on both and was already imported
here. What moves with it is the part that matters: fetched only during a
visit, only from the page's own origin or a host that page already loaded
from, memory-only in a private tab, wiped by the reset."
```

---

### Task 7: `BrowserSession` behind a platform protocol

The largest single move: 1,286 lines, six AppKit edges. Spec §3.2.

**Files:**
- Create: `macos/LimeghostBrowser/Sources/LimeghostShared/BrowserSessionPlatform.swift`
- Create: `macos/LimeghostBrowser/Sources/LimeghostBrowser/MacSessionPlatform.swift`
- Modify then move: `macos/LimeghostBrowser/Sources/LimeghostBrowser/BrowserSession.swift:105,194,365-371,561,1189,1238-1259`
- Move: `macos/LimeghostBrowser/Sources/LimeghostBrowser/AICompanion.swift`
- Create: `macos/LimeghostBrowser/Tests/LimeghostSharedTests/BrowserSessionPlatformTests.swift`

**Interfaces:**
- Consumes: `LimeghostCore`, the stores moved in Task 5.
- Produces: `protocol BrowserSessionPlatform`; `BrowserSession.platform: BrowserSessionPlatform`; `AICompanion` in Shared.

- [ ] **Step 1: Write the failing test**

Create `macos/LimeghostBrowser/Tests/LimeghostSharedTests/BrowserSessionPlatformTests.swift`:

```swift
import XCTest
import WebKit
@testable import LimeghostShared

/// Records what the session asked the platform to do, so a test can assert the
/// request without a window, a panel, or a person to dismiss one.
final class RecordingPlatform: BrowserSessionPlatform {
    var openedExternally: [URL] = []
    func openExternal(_ url: URL) { openedExternally.append(url) }
    func presentAlert(message: String) async {}
    func presentConfirm(message: String) async -> Bool { false }
    func presentPrompt(message: String, defaultText: String?) async -> String? { nil }
    func chooseFiles(allowsMultiple: Bool) async -> [URL]? { nil }
    func printPage(_ webView: WKWebView) {}
    func observeAppearance(_ apply: @escaping () -> Void) -> Any? { nil }
}

final class BrowserSessionPlatformTests: XCTestCase {
    /// A `mailto:` link is not a page. The session must hand it to the platform
    /// rather than try to load it, on a phone exactly as on a Mac.
    @MainActor
    func testASchemeTheBrowserDoesNotRenderGoesToThePlatform() throws {
        let platform = RecordingPlatform()
        let session = makeTestSession(platform: platform)

        session.openExternalScheme(URL(string: "mailto:hello@example.com")!)

        XCTAssertEqual(platform.openedExternally.map(\.scheme), ["mailto"])
    }
}
```

Add a `makeTestSession(platform:)` helper to the same file building a `BrowserSession` with the same defaults `makeSurfaceTestWorkspace` uses.

- [ ] **Step 2: Run it and watch it fail**

```bash
cd macos/LimeghostBrowser && swift test --filter BrowserSessionPlatformTests
```

Expected: FAIL — `cannot find type 'BrowserSessionPlatform' in scope`.

- [ ] **Step 3: Declare the protocol**

Create `macos/LimeghostBrowser/Sources/LimeghostShared/BrowserSessionPlatform.swift`:

```swift
import Foundation
import WebKit

/// The handful of things a browsing session needs from the operating system
/// that macOS and iOS do differently: opening an address this browser does not
/// render, the three dialogs a page can raise, a file picker, printing, and
/// following the system's light/dark choice.
///
/// This exists so `BrowserSession` itself contains no AppKit and no UIKit. Its
/// macOS implementation is the code that used to be inline in the session,
/// moved rather than rewritten.
@MainActor
public protocol BrowserSessionPlatform: AnyObject {
    /// A `mailto:`, `tel:` or other scheme the browser does not render.
    func openExternal(_ url: URL)

    /// `window.alert`. Returns when the person has dismissed it.
    func presentAlert(message: String) async

    /// `window.confirm`. `true` only if the person accepted.
    func presentConfirm(message: String) async -> Bool

    /// `window.prompt`. `nil` if the person cancelled.
    func presentPrompt(message: String, defaultText: String?) async -> String?

    /// `<input type="file">`. iOS returns `nil`: WebKit presents its own
    /// picker there, so the app must not present a second one.
    func chooseFiles(allowsMultiple: Bool) async -> [URL]?

    /// Print this page. iOS does nothing in v1; printing is not in scope.
    func printPage(_ webView: WKWebView)

    /// Call `apply` whenever the system's appearance changes. The returned
    /// value is the observation to retain, or `nil` where the platform needs
    /// none — iOS follows its trait collection without being asked.
    func observeAppearance(_ apply: @escaping () -> Void) -> Any?
}
```

- [ ] **Step 4: Implement it for macOS**

Create `macos/LimeghostBrowser/Sources/LimeghostBrowser/MacSessionPlatform.swift` containing an `@MainActor final class MacSessionPlatform: BrowserSessionPlatform`. Move the bodies out of `BrowserSession.swift` unchanged: `NSWorkspace.shared.open` (line 105), the `NSApp.effectiveAppearance` observation (194, 561), `NSPrintInfo` printing (365–371), `NSOpenPanel` (1189), and the `NSAlert`/`NSTextField` dialogs (1238–1259).

- [ ] **Step 5: Give the session a platform and move it**

Add `private let platform: BrowserSessionPlatform` to `BrowserSession`, take it as an initializer parameter, and replace each removed body with a call. Then:

```bash
cd macos/LimeghostBrowser/Sources
git mv LimeghostBrowser/BrowserSession.swift LimeghostShared/BrowserSession.swift
git mv LimeghostBrowser/AICompanion.swift    LimeghostShared/AICompanion.swift
```

Build and fix visibility until clean.

- [ ] **Step 6: Run everything, then prove it on iOS**

```bash
cd macos/LimeghostBrowser && swift test 2>&1 | tail -5
```

Expected: `Executed 488 tests … 0 failures`.

```bash
mkdir -p /tmp/limeghost-ios
cd macos/LimeghostBrowser/Sources
xcrun --sdk iphonesimulator swiftc -emit-module -module-name LimeghostCore \
  -swift-version 5 -target arm64-apple-ios17.0-simulator \
  -emit-module-path /tmp/limeghost-ios/LimeghostCore.swiftmodule LimeghostCore/*.swift
xcrun --sdk iphonesimulator swiftc -typecheck -swift-version 5 \
  -target arm64-apple-ios17.0-simulator -I /tmp/limeghost-ios LimeghostShared/*.swift
echo "exit: $?"
```

Expected: `BUILD SUCCEEDED`. The assistant's whole model — the two-session cap, park and restore, `canShareWindow`, `makeRoomForPage` — now compiles for a phone.

- [ ] **Step 7: Commit**

```bash
git add -A macos/LimeghostBrowser
git commit -m "Put the six things a session wants from the OS behind one protocol

Opening a mailto:, the three dialogs a page can raise, a file picker,
printing, and following the system's appearance. Six edges, and every other
line of the session is platform-neutral -- so the session and the assistant
that owns them now compile for a phone. The macOS implementations are the
same code in a new file, not new code."
```

---

### Task 8: `BrowserWorkspace` and the door rule

Spec §3.3. The spike promised in the spec is Step 1: if the seams are more than a handful, stop and report rather than pressing on.

**Files:**
- Create: `macos/LimeghostBrowser/Sources/LimeghostShared/WorkspaceCollaborators.swift`
- Modify then move: `macos/LimeghostBrowser/Sources/LimeghostBrowser/BrowserWorkspace.swift:176,703-726,1439`
- Modify: `macos/LimeghostBrowser/Sources/LimeghostBrowser/BrowserServices.swift`

**Interfaces:**
- Consumes: `BrowserSession` and `AICompanion` from Task 7.
- Produces: `protocol DownloadCoordinating`, `PageSharing`, `ClipboardWriting`; `BrowserWorkspace` and `BrowserTab` in Shared.

- [ ] **Step 1: Run the spike and decide**

```bash
grep -n "NSPasteboard\|NSApp\|NSWindow\|BrowserServices\|DownloadCenter\|PageFileCommands" \
  macos/LimeghostBrowser/Sources/LimeghostBrowser/BrowserWorkspace.swift
```

Measured September 3, 2026: **three seams** — `NSPasteboard.general` (176), `NSApp.keyWindow` for the share sheet (1439), and the `services:` convenience initializer (703–726). The primary initializer at 352 already takes plain dependencies and mentions no window. Three is a handful; proceed.

If the grep now shows substantially more, stop and report: the spec's fallback is an iOS `MobileWorkspace` that ports the doors and duplicates the door test.

- [ ] **Step 2: Write the failing test**

Add to `macos/LimeghostBrowser/Tests/LimeghostSharedTests/`, a new file `WorkspaceDoorTests.swift`, the door test moved verbatim from `BrowserBehaviorTests.swift:1700-1745` (`testEveryWayOfAskingForAPageUncoversIt`), with its `makeSurfaceTestWorkspace()` helper and a `NoDownloads` stub in the `DownloadCenter` slot:

```swift
/// Nothing to download in a unit test, and downloads are the one collaborator
/// that is still macOS-only. The workspace only needs it to exist.
final class NoDownloads: DownloadCoordinating {
    func begin(_ download: WKDownload) {}
    var hasActiveDownloads: Bool { false }
}
```

- [ ] **Step 3: Run it and watch it fail**

```bash
cd macos/LimeghostBrowser && swift test --filter WorkspaceDoorTests
```

Expected: FAIL — `cannot find type 'DownloadCoordinating' in scope`.

- [ ] **Step 4: Declare the three collaborator protocols**

Create `macos/LimeghostBrowser/Sources/LimeghostShared/WorkspaceCollaborators.swift` with `DownloadCoordinating`, `PageSharing` and `ClipboardWriting`, each carrying only the members `BrowserWorkspace` calls. Conform the existing `DownloadCenter`, `PageFileCommands` and a new tiny `MacClipboard` in the app target; none of their bodies change.

- [ ] **Step 5: Move the workspace**

Leave the `services:` convenience initializer behind in the app target as an extension on `BrowserWorkspace` — it is the one genuinely window-and-profile-shaped seam, and `BrowserServices` stays macOS-only in this plan.

```bash
cd macos/LimeghostBrowser/Sources && git mv LimeghostBrowser/BrowserWorkspace.swift LimeghostShared/BrowserWorkspace.swift
```

- [ ] **Step 6: Run everything, then iOS**

```bash
cd macos/LimeghostBrowser && swift test 2>&1 | tail -5
```

Expected: `Executed 488 tests … 0 failures` — the door test moved rather than being added, so the count does not rise.

```bash
mkdir -p /tmp/limeghost-ios
cd macos/LimeghostBrowser/Sources
xcrun --sdk iphonesimulator swiftc -emit-module -module-name LimeghostCore \
  -swift-version 5 -target arm64-apple-ios17.0-simulator \
  -emit-module-path /tmp/limeghost-ios/LimeghostCore.swiftmodule LimeghostCore/*.swift
xcrun --sdk iphonesimulator swiftc -typecheck -swift-version 5 \
  -target arm64-apple-ios17.0-simulator -I /tmp/limeghost-ios LimeghostShared/*.swift
echo "exit: $?"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Commit**

```bash
git add -A macos/LimeghostBrowser
git commit -m "Share the workspace, so the door rule is one rule on both platforms

Every way of asking for a page has to uncover it, and that rule half-shipped
once already -- new tab stepped aside and nine other doors did not. Writing
it a second time for a phone is how that happens again, so the workspace
moves instead, behind protocols for downloads, sharing and the clipboard.
The door test moves with it and now runs on the Simulator too."
```

---

### Task 9: Move the rest of the tests, and add the iOS CI job

**Files:**
- Modify: `macos/LimeghostBrowser/Tests/BrowserBehaviorTests/BrowserBehaviorTests.swift`
- Create: `macos/LimeghostBrowser/Tests/LimeghostSharedTests/CompanionBehaviorTests.swift`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: everything moved in Tasks 5–8.
- Produces: an `ios-simulator` CI job.

- [ ] **Step 1: Move the tests whose subjects moved**

Move from `BrowserBehaviorTests.swift` into `LimeghostSharedTests/CompanionBehaviorTests.swift`: `testWithNoRoomForBothTheAssistantLeavesAndReturnsWhenTheRoomDoes`, `testAnAssistantClosedByHandStaysClosedWhenTheWindowWidens`, `testLeavingCompareKeepsTheAssistantStillOnScreen`, `testTheAIHomesOwnDoorsAlsoMakeRoomForThePage`, and the data-store recovery and session tests. Move the `makeSurfaceTestWorkspace` helper and `TestSuiteCleanup` with them.

- [ ] **Step 2: Run both suites on macOS**

```bash
cd macos/LimeghostBrowser && swift test 2>&1 | tail -5
```

Expected: total still 488, redistributed between targets.

- [ ] **Step 3: Confirm the moved tests still compile for iOS**

Running them on a real Simulator waits on the iOS platform download (see Global Constraints), so locally this step is a typecheck of the test sources against the iOS SDK:

```bash
mkdir -p /tmp/limeghost-ios
cd macos/LimeghostBrowser/Sources
xcrun --sdk iphonesimulator swiftc -emit-module -module-name LimeghostCore \
  -swift-version 5 -target arm64-apple-ios17.0-simulator \
  -emit-module-path /tmp/limeghost-ios/LimeghostCore.swiftmodule LimeghostCore/*.swift
xcrun --sdk iphonesimulator swiftc -typecheck -swift-version 5 \
  -target arm64-apple-ios17.0-simulator -I /tmp/limeghost-ios LimeghostShared/*.swift
echo "exit: $?"
```

Expected: `exit: 0`. The CI job added in Step 4 is what actually *runs* them on a Simulator, on a runner that has the platform installed. If the iOS platform has since been installed locally (`xcodebuild -downloadPlatform iOS`), also run:

```bash
cd macos/LimeghostBrowser && xcodebuild test -scheme LimeghostShared \
  -destination "platform=iOS Simulator,name=$(xcrun simctl list devices available | grep -m1 'iPhone' | sed 's/ (.*//;s/^ *//')" \
  -derivedDataPath /tmp/limeghost-ios-dd 2>&1 | tail -8
```

Expected if run: `TEST SUCCEEDED`. Skip without comment if the platform is still absent.

- [ ] **Step 4: Add the CI job**

In `.github/workflows/ci.yml`, after the existing `macos-15` job, add a job that selects Xcode as the existing one does, runs `xcodebuild test -scheme LimeghostShared` and `-scheme LimeghostCore` against an iOS Simulator destination, and does not touch the Mac job. Choose the destination from `xcrun simctl list devices available` on the runner rather than hard-coding a device, because GitHub's image ships different runtimes than this machine:

```yaml
      - name: Pick an available iOS simulator
        run: |
          UDID=$(xcrun simctl list devices available --json \
            | python3 -c "import json,sys;d=json.load(sys.stdin)['devices'];print(next(v['udid'] for k in d for v in d[k] if 'iPhone' in v['name']))")
          echo "SIM_UDID=$UDID" >> "$GITHUB_ENV"
```

- [ ] **Step 5: Commit**

```bash
git add -A macos/LimeghostBrowser .github/workflows/ci.yml
git commit -m "Run the shared rules on a phone in CI, as the same tests

The door rule, the narrow-window rule and the assistant's session cap now
run on an iOS Simulator and on a Mac from one source. That is the whole
point of the boundary: a phone that behaves differently from the Mac fails
here rather than in somebody's hand."
```

---

### Task 10: Documentation

Spec §7.5, restricted to what this plan changed. The rest lands with Plans 2 and 3.

**Files:**
- Create: `docs/ios-browser-foundation.md`
- Modify: `docs/project-context.md`, `CLAUDE.md`, `AGENTS.md`, `README.md`, `CHANGELOG.md`
- Modify: `docs/superpowers/specs/2026-09-03-ios-pocket-browser-design.md` §3.1

- [ ] **Step 1: Correct the spec's portability table**

§3.1 grouped files by whether they import AppKit. That is not evidence: `import SwiftUI` re-exports AppKit on macOS. Replace the table's Evidence column with the measured result and add the five files that are macOS-only without importing AppKit: `WebView.swift` (`NSViewRepresentable`), `TabStripViews.swift` (`NSEvent`), `LimeghostBrowserApp.swift` (`NSApplicationDelegateAdaptor`), `SiteInformationViews.swift` (`openSettings` unavailable on iOS), `BookmarkImportSources.swift` (`homeDirectoryForCurrentUser` unavailable on iOS). Note that `BookmarkImportSources` therefore needs a platform seam in Plan 3, which §6.5 did not anticipate.

- [ ] **Step 2: Write `docs/ios-browser-foundation.md`**

Cover: the target layout, the build and test commands used above including the destination caveat, what is shared and what is not, what waits on Developer Program enrolment, and the device-only checklist from spec §9.8.

- [ ] **Step 3: Add the constraints agents would otherwise break**

To `CLAUDE.md` and `AGENTS.md`: the shared-target boundary; no `#if os` in `LimeghostShared`; preference keys stay `clearframe.*`; verify portability with the compiler and never with grep, because SwiftUI re-exports AppKit.

- [ ] **Step 4: Record the decision**

One dated entry in `docs/project-context.md`: the four decisions and two amendments from spec §1, that sync is designed and waits on enrolment, and that no claim of validation is made.

- [ ] **Step 5: Commit**

```bash
git add -A docs CLAUDE.md AGENTS.md README.md CHANGELOG.md
git commit -m "Write down the boundary, and correct how it was measured

The spec grouped files by whether they import AppKit. That was the wrong
test: SwiftUI re-exports AppKit on macOS, so five files that import none of
it are still macOS-only -- the web view representable, the tab strip's
pointer reads, the app delegate adaptor, and two calls unavailable on iOS.
The compiler says which files port. Grep does not."
```

---

## Self-Review

**Spec coverage.** §3.1 → Tasks 2, 5, 6, 7, 8 (and its correction in Task 10). §3.2 → Task 7. §3.3 → Task 8. §3.4 → Tasks 1, 9. §3.5 → Global Constraints. §5.2 `AssistantLayout` → Task 3. §6.2 keys → Global Constraints. §6.4 favicons → Task 6. §6.6 `modifiedAt` → Task 4. §9.1–9.2 test movement → Task 9. §9.3 → Task 3. §7.5 docs → Task 10.

**Not covered here, by design:** §4 the shell, §5.1/5.3/5.4 the overlay, §6.5 the bookmark bridge, §6.1 the iOS bundle identifier, §6.7 the privacy manifest, §9.4/9.5 the iOS target's own tests and memory instrument. All belong to Plans 2 and 3, which have no home until this boundary exists.

**Type consistency.** `AssistantLayout.fitsBesidePage(width:)`/`fitsTwoAssistants(width:)` are used identically in Tasks 3 and 9. `BrowserSessionPlatform`'s seven members are declared in Task 7 Step 3 and implemented by `RecordingPlatform` in Step 1 with matching signatures. `DownloadCoordinating` is named consistently in Task 8 Steps 2, 4 and 5. `FaviconStore.image(from:)`/`pngData(from:)` match between Task 6's test and implementation.

**Known risk.** Task 5 Step 4 discovers that `AICompanion` cannot move before `BrowserSession`; the step says so and defers it to Task 7 rather than leaving the executor to find out. Task 8's spike may fail, and its Step 1 says to stop and report rather than continue.
