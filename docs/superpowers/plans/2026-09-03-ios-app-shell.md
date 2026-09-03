# Limeghost iOS App Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an iOS app you can actually browse with — tabs, an address bar, a bottom bar, a tab switcher, and the AI guide — on top of the `LimeghostShared` layer that Plan 1 delivered.

**Architecture:** A hand-written `ios/Limeghost.xcodeproj` consumes the existing Swift package by relative path, linking `LimeghostShared` (and `LimeghostCore` transitively). One SwiftUI scene hosts one `BrowserWorkspace` — the same workspace the Mac drives, so every door already calls `makeRoomForPage()` and the door test already passes on a phone. iOS supplies only what the platform protocol asks for; no browser logic is rewritten.

**Tech Stack:** Swift 6 toolchain in language mode 5, SwiftUI, WebKit, UIKit (only behind the platform protocol), XCTest. Xcode 26.6, iOS 26.5 simulator runtime, deployment target iOS 17.0. No third-party dependencies.

**Spec:** [docs/superpowers/specs/2026-09-03-ios-pocket-browser-design.md](../specs/2026-09-03-ios-pocket-browser-design.md) — §2 (scope), §4 (the shell), §6 (data and identity)

**Plan 2 of 3.** Plan 1 (`2026-09-03-limeghost-shared-layer.md`) is complete and merged into this branch. Plan 3 adds the assistant overlay, Reader, Copy for AI and the bookmark bridge — deliberately excluded here so that this plan ends with something you can hold.

## Global Constraints

- **Deployment target iOS 17.0**, Swift language mode 5, `TARGETED_DEVICE_FAMILY = "1,2"` (iPhone and iPad).
- **Bundle identifier `com.zincoo.limeghost`** for iOS. The Mac's `com.clearframe.browser` is untouched. (Spec §6.1)
- **Preference keys stay `clearframe.*`** on both platforms — they are read by shared code and renaming forks it. (Spec §6.2)
- **No `#if os(...)` in `Sources/LimeghostShared/`.** Platform differences enter through `BrowserSessionPlatform` and the workspace collaborator protocols only. iOS-only code lives in `ios/`.
- **No third-party dependencies**, including in tests. XCTest only — no snapshot library, no BDD framework, no project generator.
- **No browser logic is rewritten.** The workspace, session, tabs, doors and stores come from `LimeghostShared` unchanged. If iOS seems to need different behaviour, that is a protocol member, not a fork.
- **Never type into an assistant, never press its send button, never read its answers.** No assistant work happens in this plan at all, and nothing added here may make those easier.
- **v1 runs one profile** (the default) and has **no downloads**. (Spec §2)
- **Claim nothing about signing, notarization, TestFlight, App Store readiness or user validation.** The app runs under free provisioning on the founder's own device and the Simulator; nobody else can install it.
- **Verify portability with the compiler, never with grep.** `import SwiftUI` re-exports AppKit on macOS, so a file can use an AppKit type while importing none. Plan 1 learned this the hard way, five files over.
- **A test count is a check, not a target.** If correct work changes the count, change the count and say so. Never delete or skip a test to make a number match.

## Verified before this plan was written

Do not re-derive these; they were measured on September 3, 2026.

- **A hand-written `.pbxproj` builds a real iOS app.** `xcodebuild build -scheme Limeghost -destination 'platform=iOS Simulator,…'` → `** BUILD SUCCEEDED **`. No project generator is needed, which matters because every one of them is a third-party dependency this repo forbids.
- **That project links the local Swift package by relative path.** `XCLocalSwiftPackageReference` with `relativePath = "../macos/LimeghostBrowser"` from `ios/Limeghost.xcodeproj` resolves, builds `LimeghostCore` and `LimeghostShared` for `iphonesimulator`, and `import LimeghostShared` + `AssistantLayout.fitsBesidePage(width:)` compiles and links into the app. Task 1's project file is that proven file.
- **The shared layer's tests already pass on an iPhone simulator** — `WorkspaceDoorTests`, `AssistantLayoutTests`, `BrowserSessionPlatformTests`, `FaviconImageCodingTests`. The rules this app will drive are known good on the platform.
- **`BrowserSessionPlatform` has exactly 8 members** (Task 2 implements all of them): `openExternal(_:)`, `presentAlert(message:) async`, `presentConfirm(message:) async -> Bool`, `presentPrompt(message:defaultText:) async -> String?`, `chooseFiles(allowsMultiple:allowsDirectories:) async -> [URL]?`, `printPage(_:)`, `observeAppearance(_:) -> Any?`, `prepareWebView(_:)`.
- **The other three protocols** an app must satisfy: `DownloadTracking`, `PageSharing`, `ClipboardWriting`.
- **The workspace API the shell drives:** `addTab(url:select:isPrivate:)`, `selectTab(_:)`, `closeTab(_:)`, `reopenClosedTab()`, `canReopenClosedTab`, `visibleTabs`, `selectedTab`, `selectedTabID`, `goHome()`, `showBookmarksHome()`, `showHistoryHome()`, `makeRoomForPage()`, `focusAddressRequest`, `startSurface`.

## Build and test commands

```bash
# The iOS app
cd ios && xcodebuild build -scheme Limeghost \
  -destination "platform=iOS Simulator,id=$(xcrun simctl list devices available | grep -m1 'iPhone' | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"

# The shared layer's tests, on a simulator
cd macos/LimeghostBrowser && xcodebuild test -scheme LimeghostSharedLayer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# The Mac, which must stay green throughout
cd macos/LimeghostBrowser && swift test
```

The Mac baseline is **492 executed, 0 failures**. The skipped count varies 2–4 between runs because three tests skip on environment conditions (audio not starting; the runner not showing a window) — judge by the executed count and zero failures.

---

### Task 1: The Xcode project, and an app that launches

**Files:**
- Create: `ios/Limeghost.xcodeproj/project.pbxproj`
- Create: `ios/Sources/LimeghostApp.swift`
- Create: `ios/Tests/AppLaunchTests.swift`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: `LimeghostShared` (built by Plan 1).
- Produces: an `ios/` Xcode project with scheme `Limeghost`, bundle id `com.zincoo.limeghost`, deployment target 17.0; `LimeghostApp` as the `@main` entry point.

- [ ] **Step 1: Write the project file**

Create `ios/Limeghost.xcodeproj/project.pbxproj` with exactly this content. **This file is verified — it was built for an iOS Simulator before this plan was written.** Do not restructure it; if something seems missing, add rather than rewrite.

```
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 56;
	objects = {

/* Begin PBXBuildFile section */
		AA0000000000000000000101 /* LimeghostApp.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000201 /* LimeghostApp.swift */; };
		AA0000000000000000001101 /* LimeghostShared in Frameworks */ = {isa = PBXBuildFile; productRef = AA0000000000000000001001 /* LimeghostShared */; };
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		AA0000000000000000000201 /* LimeghostApp.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LimeghostApp.swift; sourceTree = "<group>"; };
		AA0000000000000000000301 /* Limeghost.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Limeghost.app; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		AA0000000000000000000401 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				AA0000000000000000001101 /* LimeghostShared in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		AA0000000000000000000501 = {
			isa = PBXGroup;
			children = (
				AA0000000000000000000601 /* Sources */,
				AA0000000000000000000701 /* Products */,
			);
			sourceTree = "<group>";
		};
		AA0000000000000000000601 /* Sources */ = {
			isa = PBXGroup;
			children = (
				AA0000000000000000000201 /* LimeghostApp.swift */,
			);
			path = Sources;
			sourceTree = "<group>";
		};
		AA0000000000000000000701 /* Products */ = {
			isa = PBXGroup;
			children = (
				AA0000000000000000000301 /* Limeghost.app */,
			);
			name = Products;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		AA0000000000000000000801 /* Limeghost */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = AA0000000000000000000901 /* Build configuration list for PBXNativeTarget "Limeghost" */;
			buildPhases = (
				AA0000000000000000000A01 /* Sources */,
				AA0000000000000000000401 /* Frameworks */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = Limeghost;
			packageProductDependencies = (
				AA0000000000000000001001 /* LimeghostShared */,
			);
			productName = Limeghost;
			productReference = AA0000000000000000000301 /* Limeghost.app */;
			productType = "com.apple.product-type.application";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		AA0000000000000000000B01 /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 2600;
				LastUpgradeCheck = 2600;
			};
			buildConfigurationList = AA0000000000000000000C01 /* Build configuration list for PBXProject "Limeghost" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = AA0000000000000000000501;
			productRefGroup = AA0000000000000000000701 /* Products */;
			packageReferences = (
				AA0000000000000000000F01 /* XCLocalSwiftPackageReference "LimeghostBrowser" */,
			);
			projectDirPath = "";
			projectRoot = "";
			targets = (
				AA0000000000000000000801 /* Limeghost */,
			);
		};
/* End PBXProject section */

/* Begin PBXSourcesBuildPhase section */
		AA0000000000000000000A01 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				AA0000000000000000000101 /* LimeghostApp.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		AA0000000000000000000D01 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				GCC_NO_COMMON_BLOCKS = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = iphoneos;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.0;
			};
			name = Debug;
		};
		AA0000000000000000000E01 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGNING_ALLOWED = NO;
				CODE_SIGNING_REQUIRED = NO;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.zincoo.limeghost;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Debug;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		AA0000000000000000000C01 /* Build configuration list for PBXProject "Limeghost" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				AA0000000000000000000D01 /* Debug */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Debug;
		};
		AA0000000000000000000901 /* Build configuration list for PBXNativeTarget "Limeghost" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				AA0000000000000000000E01 /* Debug */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Debug;
		};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
		AA0000000000000000000F01 /* XCLocalSwiftPackageReference "LimeghostBrowser" */ = {
			isa = XCLocalSwiftPackageReference;
			relativePath = "../macos/LimeghostBrowser";
		};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		AA0000000000000000001001 /* LimeghostShared */ = {
			isa = XCSwiftPackageProductDependency;
			productName = LimeghostShared;
		};
/* End XCSwiftPackageProductDependency section */
	};
	rootObject = AA0000000000000000000B01 /* Project object */;
}
```

- [ ] **Step 2: Write the app entry point**

Create `ios/Sources/LimeghostApp.swift`:

```swift
import SwiftUI
import LimeghostShared

/// Limeghost on iPhone.
///
/// The browser's rules — tabs, the doors that uncover a page, the assistant's
/// layout, extraction — all live in `LimeghostShared` and are the same code the
/// Mac runs. This target supplies only what a phone must supply itself: the
/// screen, the touch surfaces, and the handful of things `BrowserSessionPlatform`
/// asks the operating system for.
@main
struct LimeghostApp: App {
    var body: some Scene {
        WindowGroup {
            // Replaced in Task 3 by the real browser. Until then this proves the
            // app launches and that shared code reaches it.
            Text(verbatim: "Limeghost")
        }
    }
}
```

- [ ] **Step 3: Build it for a simulator**

```bash
cd ios
SIM=$(xcrun simctl list devices available | grep -m1 'iPhone' | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
xcodebuild build -scheme Limeghost -destination "platform=iOS Simulator,id=$SIM" 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`. If xcodebuild cannot find a scheme, confirm the file is at `ios/Limeghost.xcodeproj/project.pbxproj` exactly — Xcode auto-generates the `Limeghost` scheme from the target, so a missing scheme means the project file was not parsed.

- [ ] **Step 4: Prove the shared layer actually reaches the app**

Temporarily change the `Text` in `LimeghostApp.swift` to read a shared symbol:

```swift
            Text(verbatim: "beside a page at 1200pt? \(AssistantLayout.fitsBesidePage(width: 1200))")
```

Rebuild with the command from Step 3. Expected: `** BUILD SUCCEEDED **`, and the build log names `LimeghostCore` and `LimeghostShared` as targets it compiled. Then restore the plain `Text(verbatim: "Limeghost")`. This is a throwaway check, not a commit — its purpose is to fail loudly now if the package reference is wrong, rather than in Task 3.

- [ ] **Step 5: Ignore Xcode's per-user state**

Append to `.gitignore`:

```gitignore

# Xcode per-user state. The project file itself is committed; this is not.
ios/**/xcuserdata/
ios/**/*.xcworkspace/xcuserdata/
ios/.build/
```

Confirm the project file is still tracked and the user state is not:

```bash
git check-ignore -v ios/Limeghost.xcodeproj/project.pbxproj && echo "PROBLEM: project ignored" || echo "project tracked, good"
```

- [ ] **Step 6: Confirm the Mac is untouched**

```bash
cd macos/LimeghostBrowser && swift test 2>&1 | tail -3
```

Expected: **492 executed, 0 failures.** This task adds no Swift package code, so the count must not move.

- [ ] **Step 7: Commit**

```bash
git add ios .gitignore
git commit -m "Give the phone a project of its own, pointing at the shared layer

SwiftPM cannot build an iOS app and every project generator is a third-party
dependency this repository does not take, so the project file is written by
hand and committed. It links the existing package by relative path, which
means the phone builds from the same source the Mac does rather than a copy."
```

---

### Task 2: `IOSSessionPlatform` — the eight things a session asks the OS for

**Files:**
- Create: `ios/Sources/IOSSessionPlatform.swift`
- Create: `ios/Sources/IOSCollaborators.swift`
- Create: `ios/Tests/IOSSessionPlatformTests.swift`
- Modify: `ios/Limeghost.xcodeproj/project.pbxproj` (add the new sources and a test target)

**Interfaces:**
- Consumes: `BrowserSessionPlatform`, `DownloadTracking`, `PageSharing`, `ClipboardWriting` from `LimeghostShared`.
- Produces: `IOSSessionPlatform` (conforms to `BrowserSessionPlatform`), `IOSClipboard` (`ClipboardWriting`), `IOSPageSharing` (`PageSharing`), `NoDownloads` (`DownloadTracking`).

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/IOSSessionPlatformTests.swift`:

```swift
import XCTest
import WebKit
@testable import LimeghostShared

final class IOSSessionPlatformTests: XCTestCase {
    /// A `mailto:` link is not a page. The session hands it to the platform
    /// rather than trying to render it — the same contract the Mac has, which
    /// is why the session itself needed no change for a phone.
    @MainActor
    func testAnUnrenderableSchemeGoesToThePlatform() {
        let platform = IOSSessionPlatform()
        var opened: [URL] = []
        platform.openExternalForTesting = { opened.append($0) }

        platform.openExternal(URL(string: "mailto:hello@example.com")!)

        XCTAssertEqual(opened.map(\.scheme), ["mailto"])
    }

    /// WebKit presents its own document picker on iOS. If this returned a URL
    /// list, the app would put a second picker on top of WebKit's own.
    @MainActor
    func testTheAppPresentsNoFilePickerOfItsOwn() async {
        let platform = IOSSessionPlatform()
        let chosen = await platform.chooseFiles(allowsMultiple: true, allowsDirectories: false)
        XCTAssertNil(chosen)
    }

    /// iOS follows its trait collection, so there is nothing to observe and
    /// nothing to retain. Returning a token the caller then stored would be a
    /// leak with no purpose.
    @MainActor
    func testAppearanceNeedsNoObservationOnIOS() {
        let platform = IOSSessionPlatform()
        XCTAssertNil(platform.observeAppearance({ }))
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd ios
SIM=$(xcrun simctl list devices available | grep -m1 'iPhone' | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
xcodebuild test -scheme Limeghost -destination "platform=iOS Simulator,id=$SIM" 2>&1 | tail -5
```

Expected: failure — `cannot find 'IOSSessionPlatform' in scope`. If instead xcodebuild reports the scheme is "not currently configured for the test action", the test target is not wired into the scheme yet; that is Step 4's job, so continue.

- [ ] **Step 3: Write the platform**

Create `ios/Sources/IOSSessionPlatform.swift`:

```swift
import UIKit
import WebKit
import LimeghostShared

/// What a browsing session needs from iOS.
///
/// Every member here is one of the eight things `BrowserSessionPlatform`
/// declares, and three of them do nothing on a phone. That is the point of the
/// protocol: the session does not know which platform it is on, so a difference
/// shows up as an implementation that answers "nothing to do" rather than as a
/// conditional inside the browser.
@MainActor
final class IOSSessionPlatform: BrowserSessionPlatform {
    /// The web view this session owns, handed over by `prepareWebView` from
    /// inside the session's own initializer — before its delegates are wired,
    /// so a callback during the first load cannot find this nil.
    fileprivate weak var webView: WKWebView?

    /// Injected by tests so opening a `mailto:` can be observed without asking
    /// the system to launch Mail.
    var openExternalForTesting: ((URL) -> Void)?

    func openExternal(_ url: URL) {
        if let openExternalForTesting {
            openExternalForTesting(url)
            return
        }
        UIApplication.shared.open(url)
    }

    func presentAlert(message: String) async {
        await withCheckedContinuation { continuation in
            let alert = makeAlert(message: message)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                continuation.resume()
            })
            present(alert)
        }
    }

    func presentConfirm(message: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = makeAlert(message: message)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(returning: false)
            })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                continuation.resume(returning: true)
            })
            present(alert)
        }
    }

    func presentPrompt(message: String, defaultText: String?) async -> String? {
        await withCheckedContinuation { continuation in
            let alert = makeAlert(message: message)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(returning: nil)
            })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
                continuation.resume(returning: alert?.textFields?.first?.text)
            })
            present(alert)
        }
    }

    /// Nothing. WebKit presents its own document picker for `<input type="file">`
    /// on iOS, so an app-supplied one would appear on top of it.
    func chooseFiles(allowsMultiple: Bool, allowsDirectories: Bool) async -> [URL]? {
        nil
    }

    /// Nothing. Printing is not in v1 (spec §2), and a silent no-op is honest
    /// here in a way a half-built print sheet would not be.
    func printPage(_ webView: WKWebView) {}

    /// Nothing to observe. iOS hands a view its trait collection and updates it
    /// on a system appearance change, so there is no notification to watch and
    /// no token for the caller to retain.
    func observeAppearance(_ apply: @escaping () -> Void) -> Any? { nil }

    /// Called from inside `BrowserSession`'s designated initializer.
    func prepareWebView(_ webView: WKWebView) {
        self.webView = webView
    }

    // MARK: - Presenting

    private func makeAlert(message: String) -> UIAlertController {
        UIAlertController(
            title: webView?.url?.host.map { "Message from \($0)" } ?? "Message from this page",
            message: String(message.prefix(4_000)),
            preferredStyle: .alert
        )
    }

    /// A page's dialog belongs to the window the page is in. The scene's own
    /// root controller is that window, and reaching it through the connected
    /// scene rather than a stored reference means a dialog cannot outlive the
    /// screen it belongs to.
    private func present(_ alert: UIAlertController) {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard let root = scene?.keyWindow?.rootViewController else { return }
        root.present(alert, animated: true)
    }
}
```

- [ ] **Step 4: Write the three collaborators and wire the test target**

Create `ios/Sources/IOSCollaborators.swift`:

```swift
import UIKit
import WebKit
import LimeghostShared

/// The system pasteboard. Copy for AI is Plan 3's work; the workspace needs a
/// clipboard to exist before then, and this is it.
@MainActor
final class IOSClipboard: ClipboardWriting {
    func setString(_ string: String) {
        UIPasteboard.general.string = string
    }
}

/// Sharing a page. iOS has one share sheet and it takes the items directly, so
/// there is no separate save or export path the way macOS has.
@MainActor
enum IOSPageSharing: PageSharing {
    static func share(_ items: [Any], from anchor: Any?) {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard let root = scene?.keyWindow?.rootViewController else { return }
        controller.popoverPresentationController?.sourceView = root.view
        root.present(controller, animated: true)
    }
}

/// Downloads are deliberately not in v1 (spec §2): on iOS they are Files
/// integration, resumability and a list — a subsystem, not a button. The
/// workspace only needs the collaborator to exist.
@MainActor
final class NoDownloads: DownloadTracking {
    var hasActiveDownloads: Bool { false }
}
```

**`PageSharing` and `DownloadTracking` member signatures must match the protocols exactly.** Read them first and copy the signatures rather than trusting the sketch above:

```bash
sed -n '1,60p' macos/LimeghostBrowser/Sources/LimeghostShared/WorkspaceCollaborators.swift
sed -n '10,30p' macos/LimeghostBrowser/Sources/LimeghostShared/BrowserSession.swift
```

If a signature differs, follow the protocol and note the difference in your report.

Then add a test target to the project file. Append these objects, following the pattern already in the file — a `PBXNativeTarget` of `productType = "com.apple.product-type.bundle.unit-test"` named `LimeghostTests`, its own `PBXSourcesBuildPhase` containing the test file, an `XCConfigurationList` and `XCBuildConfiguration` with `TEST_HOST` unset (a pure logic test bundle needs no host app), and a `PBXTargetDependency` on `Limeghost`. Add the new source files to the app target's `PBXSourcesBuildPhase` too. Give every new object a unique 24-character identifier continuing the existing `AA00000000000000000000NN` scheme.

- [ ] **Step 5: Run the tests and watch them pass**

```bash
cd ios
SIM=$(xcrun simctl list devices available | grep -m1 'iPhone' | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
xcodebuild test -scheme Limeghost -destination "platform=iOS Simulator,id=$SIM" 2>&1 | grep -E "^\*\* TEST|error:" | head -5
```

Expected: `** TEST SUCCEEDED **`, 3 tests.

- [ ] **Step 6: Confirm the Mac is untouched**

```bash
cd macos/LimeghostBrowser && swift test 2>&1 | tail -3
```

Expected: **492 executed, 0 failures** — no shared code changed.

- [ ] **Step 7: Commit**

```bash
git add ios
git commit -m "Answer the eight questions a session asks its operating system

Three of the answers are 'nothing', and that is the protocol working rather
than failing: iOS follows its own trait collection, WebKit brings its own
file picker, and printing is not in this version. A phone that differs from
a Mac shows up here as an implementation, never as a conditional inside the
browser."
```

---

### Task 3: One tab, one web view, a page on screen

**Files:**
- Create: `ios/Sources/BrowserScreen.swift`
- Create: `ios/Sources/WebViewHost.swift`
- Create: `ios/Sources/WorkspaceHost.swift`
- Modify: `ios/Sources/LimeghostApp.swift`
- Create: `ios/Tests/WorkspaceHostTests.swift`
- Modify: `ios/Limeghost.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `IOSSessionPlatform`, `IOSClipboard`, `NoDownloads` (Task 2); `BrowserWorkspace`, `BrowserTab`, `BrowserSession` from `LimeghostShared`.
- Produces: `WorkspaceHost` (an `ObservableObject` owning one `BrowserWorkspace`), `WebViewHost` (a `UIViewRepresentable` wrapping the session's web view), `BrowserScreen` (the root view).

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/WorkspaceHostTests.swift`:

```swift
import XCTest
@testable import LimeghostShared

final class WorkspaceHostTests: XCTestCase {
    /// The app opens on the AI guide, not on a blank page — the first minute is
    /// a product acceptance criterion, not a default.
    @MainActor
    func testTheAppOpensOnTheAIGuide() throws {
        let host = WorkspaceHost.forTesting()
        let tab = try XCTUnwrap(host.workspace.selectedTab)
        XCTAssertEqual(tab.startSurface, .aiHome)
    }

    /// Asking for a page is the workspace's job, and it is the same method the
    /// Mac calls. If this ever stops routing through the workspace, the door
    /// rule stops applying to the phone.
    @MainActor
    func testOpeningAnAddressAddsATabThroughTheWorkspace() throws {
        let host = WorkspaceHost.forTesting()
        let before = host.workspace.visibleTabs.count

        host.workspace.addTab(url: URL(string: "https://example.com/")!)

        XCTAssertEqual(host.workspace.visibleTabs.count, before + 1)
        XCTAssertEqual(host.workspace.selectedTab?.session.currentURLString, "https://example.com/")
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run the Task 2 Step 5 command. Expected: `cannot find 'WorkspaceHost' in scope`.

- [ ] **Step 3: Write the workspace host**

Create `ios/Sources/WorkspaceHost.swift`:

```swift
import Combine
import SwiftUI
import WebKit
import LimeghostShared

/// Owns the one `BrowserWorkspace` this scene drives.
///
/// The workspace is the Mac's workspace, unchanged — it holds the tabs, and it
/// holds every door: every way a person can ask for a page. That is why the
/// phone gets it rather than a version of its own. The rule that asking for a
/// page uncovers the page half-shipped on the Mac once, when one door stepped
/// aside and nine did not, and writing the doors a second time here is exactly
/// how that would happen again.
@MainActor
final class WorkspaceHost: ObservableObject {
    let workspace: BrowserWorkspace

    private var cancellable: AnyCancellable?

    init(workspace: BrowserWorkspace) {
        self.workspace = workspace
        // SwiftUI observes this object; the workspace's own changes have to
        // reach it or the screen never redraws when a tab opens.
        cancellable = workspace.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    /// The app's workspace, built with the iOS platform and collaborators.
    static func live() -> WorkspaceHost {
        WorkspaceHost(workspace: makeWorkspace())
    }

    /// The same construction, so a test exercises what the app runs.
    static func forTesting() -> WorkspaceHost {
        WorkspaceHost(workspace: makeWorkspace())
    }

    private static func makeWorkspace() -> BrowserWorkspace {
        BrowserWorkspace(
            downloads: NoDownloads(),
            clipboard: IOSClipboard(),
            makeSessionPlatform: { IOSSessionPlatform() }
        )
    }
}
```

**The `BrowserWorkspace` initializer's exact parameter list must be read from the source, not copied from above** — Plan 1's Task 8 threaded a `makeSessionPlatform` factory through it and the label may differ:

```bash
grep -n "public init(" -A 20 macos/LimeghostBrowser/Sources/LimeghostShared/BrowserWorkspace.swift | head -30
```

Use what is actually there. If a required parameter has no iOS equivalent yet, pass the nearest no-op collaborator from Task 2 and say so in your report.

- [ ] **Step 4: Write the web view host and the screen**

Create `ios/Sources/WebViewHost.swift`:

```swift
import SwiftUI
import WebKit
import LimeghostShared

/// Hands SwiftUI a `BrowserSession`'s existing web view.
///
/// There is nothing to do in `updateUIView`: the web view is owned by the
/// session, not built here, and a representable cannot swap the view it already
/// returned. **Key this on the session's identity** where different sessions
/// appear in the same place, or SwiftUI keeps showing the first one it was
/// given. This is the iOS twin of the Mac's `WebView`, which is an
/// `NSViewRepresentable` and therefore could not be shared.
struct WebViewHost: UIViewRepresentable {
    let session: BrowserSession

    func makeUIView(context: Context) -> WKWebView { session.webView }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
```

Create `ios/Sources/BrowserScreen.swift`:

```swift
import SwiftUI
import LimeghostShared

/// The whole browser, one screen.
///
/// The selected tab's web view fills it. Task 4 adds the bottom bar beneath.
struct BrowserScreen: View {
    @ObservedObject var host: WorkspaceHost

    var body: some View {
        Group {
            if let tab = host.workspace.selectedTab {
                WebViewHost(session: tab.session)
                    .id(tab.session.instanceID)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                Color.clear
            }
        }
    }
}
```

**Check what identity `BrowserSession` exposes** before using `instanceID` — the Mac's rule is to key a web view on the session's own instance identity and never on its object address, because an address is reused after a free:

```bash
grep -n "instanceID\|public let id" macos/LimeghostBrowser/Sources/LimeghostShared/BrowserSession.swift | head -5
```

Use whatever that file actually provides.

Replace the body of `ios/Sources/LimeghostApp.swift`'s `WindowGroup` with:

```swift
        WindowGroup {
            BrowserScreen(host: host)
        }
```

and add `@StateObject private var host = WorkspaceHost.live()` to the `App` struct.

- [ ] **Step 5: Run the tests and watch them pass**

Run the Task 2 Step 5 command. Expected: `** TEST SUCCEEDED **`, 5 tests.

- [ ] **Step 6: Run it and look at it**

```bash
cd ios
SIM=$(xcrun simctl list devices available | grep -m1 'iPhone' | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
xcrun simctl boot "$SIM" 2>/dev/null || true
open -a Simulator
xcodebuild build -scheme Limeghost -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath .build 2>&1 | tail -2
xcrun simctl install "$SIM" .build/Build/Products/Debug-iphonesimulator/Limeghost.app
xcrun simctl launch "$SIM" com.zincoo.limeghost
```

**Look at the simulator.** A blank white screen means the app launched but the workspace produced no tab — report that rather than moving on. This is the first moment there is something to see; do not skip it because the tests are green.

- [ ] **Step 7: Confirm the Mac is untouched, then commit**

```bash
cd macos/LimeghostBrowser && swift test 2>&1 | tail -3
```

Expected: **492 executed, 0 failures.**

```bash
git add ios
git commit -m "Put a page on the phone, driven by the Mac's own workspace

The workspace holds every door -- every way of asking for a page -- and it
moves here as code rather than being written a second time. The one piece
that could not travel is the web view wrapper: the Mac's is an
NSViewRepresentable, and this is its UIViewRepresentable twin, which is the
whole of the difference."
```

---

### Task 4: The bottom bar

**Files:**
- Create: `ios/Sources/BottomBar.swift`
- Modify: `ios/Sources/BrowserScreen.swift`
- Create: `ios/Tests/BottomBarTests.swift`
- Modify: `ios/Limeghost.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `WorkspaceHost` (Task 3).
- Produces: `BottomBar` (a `View`), `BottomBarModel` with `canGoBack: Bool`, `tabCount: Int`, `addressLabel: String`.

Spec §4 places the controls at the bottom: back, the address pill, the assistant toggle, tabs, and a menu. **The assistant toggle is Plan 3's** — leave a gap for it rather than a dead button, and say so in a comment.

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/BottomBarTests.swift`:

```swift
import XCTest
@testable import LimeghostShared

final class BottomBarTests: XCTestCase {
    /// The address pill shows the host, not the whole URL. A phone has no room
    /// for a query string, and the host is the part that answers "where am I".
    @MainActor
    func testTheAddressPillShowsTheHost() {
        let model = BottomBarModel(urlString: "https://example.com/a/very/long/path?q=1", tabCount: 1, canGoBack: false)
        XCTAssertEqual(model.addressLabel, "example.com")
    }

    /// An empty tab has nothing to show, and "Search or enter a website" is what
    /// invites the first tap.
    @MainActor
    func testAnEmptyAddressInvitesTyping() {
        let model = BottomBarModel(urlString: "", tabCount: 1, canGoBack: false)
        XCTAssertEqual(model.addressLabel, "Search or enter a website")
    }

    /// The tab button carries the count, because on a phone the tabs are not
    /// otherwise visible.
    @MainActor
    func testTheTabButtonCountsTheTabs() {
        let model = BottomBarModel(urlString: "https://example.com/", tabCount: 4, canGoBack: true)
        XCTAssertEqual(model.tabCount, 4)
        XCTAssertTrue(model.canGoBack)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run the Task 2 Step 5 command. Expected: `cannot find 'BottomBarModel' in scope`.

- [ ] **Step 3: Write the bar**

Create `ios/Sources/BottomBar.swift`:

```swift
import SwiftUI
import LimeghostShared

/// What the bottom bar shows, separated from how it draws so a test can assert
/// it without standing up SwiftUI.
struct BottomBarModel {
    let urlString: String
    let tabCount: Int
    let canGoBack: Bool

    /// The host, or an invitation. A phone has no room for a query string, and
    /// the host is the part that answers "where am I".
    var addressLabel: String {
        guard let host = URL(string: urlString)?.host else {
            return urlString.isEmpty ? "Search or enter a website" : urlString
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// Back, the address, the tabs, and a menu — within a thumb's reach, and along
/// the bottom so the page's own top is left alone.
struct BottomBar: View {
    let model: BottomBarModel
    let goBack: () -> Void
    let openAddress: () -> Void
    let openTabs: () -> Void
    let openMenu: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: goBack) {
                Image(systemName: "chevron.backward")
            }
            .disabled(!model.canGoBack)
            .accessibilityLabel("Back")

            Button(action: openAddress) {
                Text(model.addressLabel)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.quaternary))
            }
            .accessibilityLabel("Address")

            // The assistant toggle belongs here, immediately left of the tab
            // button. It arrives with the assistant itself in Plan 3; a button
            // that did nothing would teach the wrong thing about where it lives.

            Button(action: openTabs) {
                Label("\(model.tabCount)", systemImage: "square.on.square")
                    .labelStyle(.titleOnly)
                    .frame(minWidth: 28)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke())
            }
            .accessibilityLabel("Tabs, \(model.tabCount) open")

            Button(action: openMenu) {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("Menu")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
```

- [ ] **Step 4: Put it on the screen**

In `ios/Sources/BrowserScreen.swift`, wrap the existing content in a `VStack(spacing: 0)` with the web view above and:

```swift
            BottomBar(
                model: BottomBarModel(
                    urlString: host.workspace.selectedTab?.session.currentURLString ?? "",
                    tabCount: host.workspace.visibleTabs.count,
                    canGoBack: host.workspace.selectedTab?.session.canGoBack ?? false
                ),
                goBack: { host.workspace.goBackInSelectedTab() },
                openAddress: { },   // Task 5
                openTabs: { },      // Task 6
                openMenu: { }       // Plan 3
            )
```

Confirm `canGoBack` and `goBackInSelectedTab()` exist with those names before using them:

```bash
grep -n "canGoBack\|func goBackInSelectedTab" macos/LimeghostBrowser/Sources/LimeghostShared/*.swift | head -5
```

- [ ] **Step 5: Run the tests and watch them pass**

Run the Task 2 Step 5 command. Expected: `** TEST SUCCEEDED **`, 8 tests.

- [ ] **Step 6: Run it and look at it**

Use the Task 3 Step 6 commands. **Look at the simulator**: the bar should sit at the bottom, back should be disabled on a fresh tab, and the tab button should read `1`.

- [ ] **Step 7: Confirm the Mac is untouched, then commit**

```bash
cd macos/LimeghostBrowser && swift test 2>&1 | tail -3
git add ios
git commit -m "Put the controls where a thumb reaches, and leave the page's top alone

Back, the address, the tabs and a menu, along the bottom. The address pill
shows the host rather than the URL because a phone has no room for a query
string and the host is what answers where you are. The assistant's toggle
has a place reserved beside the tab button and nothing in it yet -- a button
that did nothing would teach the wrong thing about where it lives."
```

---

### Task 5: The address bar

**Files:**
- Create: `ios/Sources/AddressSheet.swift`
- Modify: `ios/Sources/BrowserScreen.swift`
- Create: `ios/Tests/AddressSheetTests.swift`
- Modify: `ios/Limeghost.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `WorkspaceHost`; `AddressCompletion` from `LimeghostCore`.
- Produces: `AddressSheet` (a `View`), `AddressSheetModel` with `suggestions(for:) -> [AddressSuggestion]` and `submit(_:)`.

**Completion is local only.** It reads this profile's own history and bookmarks and nothing else — no suggestion service, no request while typing. That is a deliberate difference from Chrome and it is written into the privacy documents, so it must not acquire a network call here.

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/AddressSheetTests.swift`:

```swift
import XCTest
@testable import LimeghostShared

final class AddressSheetTests: XCTestCase {
    /// Typing a real address navigates rather than searching.
    @MainActor
    func testAnAddressNavigates() throws {
        let host = WorkspaceHost.forTesting()
        let model = AddressSheetModel(workspace: host.workspace)

        model.submit("example.com")

        XCTAssertEqual(host.workspace.selectedTab?.session.currentURLString.contains("example.com"), true)
    }

    /// Completion offers only what this profile already visited or saved. A
    /// prefix matching nothing completes to nothing rather than guessing a host,
    /// and nothing is sent anywhere while typing.
    @MainActor
    func testCompletionOffersNothingForAnUnknownPrefix() {
        let host = WorkspaceHost.forTesting()
        let model = AddressSheetModel(workspace: host.workspace)

        XCTAssertTrue(model.suggestions(for: "zzzzznotahost").isEmpty)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run the Task 2 Step 5 command. Expected: `cannot find 'AddressSheetModel' in scope`.

- [ ] **Step 3: Read what already exists, then write the model**

`AddressCompletion` lives in `LimeghostCore` and already implements the policy. Read its API and use it rather than writing matching logic:

```bash
grep -n "public " macos/LimeghostBrowser/Sources/LimeghostCore/AddressCompletion.swift | head -20
grep -n "addressCandidates" macos/LimeghostBrowser/Sources/LimeghostShared/BrowserDataStore.swift | head -5
```

Create `ios/Sources/AddressSheet.swift` with `AddressSheetModel` wrapping the workspace: `submit(_:)` calls `workspace.open(_:)` (confirm the name), and `suggestions(for:)` calls the completion type with the store's candidates. Then a `AddressSheet` view: a text field focused on appear, a list of suggestions, and a cancel button. Present it from `BottomBar`'s `openAddress` closure as a `.sheet`.

**Opening a page from here is a door**, so it must go through the workspace method that calls `makeRoomForPage()` — never `session.load` directly. Confirm which workspace method the Mac's address bar uses and use the same one.

- [ ] **Step 4: Run the tests and watch them pass**

Run the Task 2 Step 5 command. Expected: `** TEST SUCCEEDED **`, 10 tests.

- [ ] **Step 5: Run it and look at it**

Task 3 Step 6 commands. Type `example.com`, submit, confirm the page loads and the pill updates.

- [ ] **Step 6: Confirm the Mac is untouched, then commit**

```bash
cd macos/LimeghostBrowser && swift test 2>&1 | tail -3
git add ios
git commit -m "Let somebody type an address, and complete it from their own history

Completion reads this profile's history and bookmarks and nothing else. It
makes no request while typing and contacts no suggestion service, which is a
deliberate difference from Chrome and one the privacy documents state; a
prefix that matches nothing completes to nothing rather than guessing."
```

---

### Task 6: The tab switcher

**Files:**
- Create: `ios/Sources/TabSwitcher.swift`
- Modify: `ios/Sources/BrowserScreen.swift`
- Create: `ios/Tests/TabSwitcherTests.swift`
- Modify: `ios/Limeghost.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `WorkspaceHost`.
- Produces: `TabSwitcher` (a `View`), `TabSwitcherModel` with `rows: [TabRow]`, `privateRows: [TabRow]`, `canReopenClosed: Bool`.

- [ ] **Step 1: Write the failing test**

Create `ios/Tests/TabSwitcherTests.swift`:

```swift
import XCTest
@testable import LimeghostShared

final class TabSwitcherTests: XCTestCase {
    /// Private tabs are their own section. They are ephemeral and excluded from
    /// history, and mixing them into one list would blur a boundary the product
    /// makes deliberately.
    @MainActor
    func testPrivateTabsAreTheirOwnSection() {
        let host = WorkspaceHost.forTesting()
        host.workspace.addTab(url: URL(string: "https://example.com/")!, isPrivate: false)
        host.workspace.addTab(url: URL(string: "https://example.org/")!, isPrivate: true)

        let model = TabSwitcherModel(workspace: host.workspace)

        XCTAssertTrue(model.rows.allSatisfy { !$0.isPrivate })
        XCTAssertTrue(model.privateRows.allSatisfy(\.isPrivate))
        XCTAssertEqual(model.privateRows.count, 1)
    }

    /// Closing the last tab must not leave an empty browser with nothing to tap.
    @MainActor
    func testClosingEveryTabLeavesOneToLookAt() {
        let host = WorkspaceHost.forTesting()
        for tab in host.workspace.visibleTabs { host.workspace.closeTab(tab.id) }

        XCTAssertFalse(host.workspace.visibleTabs.isEmpty)
    }

    /// A closed tab can come back, and reopening it is a door — the page has to
    /// become visible, which is the workspace's job, not the switcher's.
    @MainActor
    func testAClosedTabCanBeReopened() {
        let host = WorkspaceHost.forTesting()
        host.workspace.addTab(url: URL(string: "https://example.com/")!)
        let id = try? XCTUnwrap(host.workspace.selectedTabID)
        if let id { host.workspace.closeTab(id) }

        XCTAssertTrue(host.workspace.canReopenClosedTab)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

Run the Task 2 Step 5 command. Expected: `cannot find 'TabSwitcherModel' in scope`.

- [ ] **Step 3: Write the switcher**

Create `ios/Sources/TabSwitcher.swift` with `TabRow` (id, title, host, isPrivate), `TabSwitcherModel` reading `workspace.visibleTabs`, and a `TabSwitcher` view: a `LazyVGrid` of cards, a private section below when non-empty, a `+` to add a tab, a close control per card, and "Reopen closed tab" at the bottom when `canReopenClosed`. Selecting a card calls `workspace.selectTab(_:)` and dismisses.

**Selecting an existing tab is deliberately not a door** — it is not a request for a *different* page, so it must not call `makeRoomForPage()`. Adding a tab and reopening a closed one are doors and go through the workspace methods that already handle that.

- [ ] **Step 4: Run the tests and watch them pass**

Run the Task 2 Step 5 command. Expected: `** TEST SUCCEEDED **`, 13 tests.

- [ ] **Step 5: Run it and look at it**

Task 3 Step 6 commands. Open three tabs, switch between them, close one, reopen it, open a private tab and confirm it appears in its own section.

- [ ] **Step 6: Confirm the Mac is untouched, then commit**

```bash
cd macos/LimeghostBrowser && swift test 2>&1 | tail -3
git add ios
git commit -m "Show the tabs, and keep the private ones apart

A grid, because a phone cannot show a strip. Private tabs get their own
section rather than being mixed in: they are ephemeral and excluded from
history, and a single list would blur a line the product draws on purpose.
Selecting a tab that already exists is not a request for a different page,
so it does not move anything."
```

---

### Task 7: The AI guide as the first thing you see

**Files:**
- Create: `ios/Sources/StartSurfaceScreen.swift`
- Modify: `ios/Sources/BrowserScreen.swift`, `ios/Limeghost.xcodeproj/project.pbxproj`
- Create: `ios/Tests/StartSurfaceTests.swift`

**Interfaces:**
- Consumes: `WorkspaceHost`; `AIToolCatalog` from `LimeghostCore`.
- Produces: `StartSurfaceScreen` (a `View`).

Spec §2: the AI guide is every new tab and the Home button. The catalogue is in `LimeghostCore` and is already platform-neutral, so this task is a view over data that exists.

- [ ] **Step 1: Measure which existing views can be reused — do not assume**

The Mac's `AIToolStartPage.swift` may be reusable by adding it to the iOS target's sources. **Verify with the compiler, not by reading imports** — `import SwiftUI` re-exports AppKit on macOS, so a file can use an AppKit type while importing none. Plan 1 was wrong about five files this way.

```bash
cd macos/LimeghostBrowser/Sources
mkdir -p /tmp/limeghost-t7
xcrun --sdk iphonesimulator swiftc -emit-module -module-name LimeghostCore \
  -swift-version 5 -target arm64-apple-ios17.0-simulator \
  -emit-module-path /tmp/limeghost-t7/LimeghostCore.swiftmodule LimeghostCore/*.swift
xcrun --sdk iphonesimulator swiftc -typecheck -swift-version 5 \
  -target arm64-apple-ios17.0-simulator -I /tmp/limeghost-t7 \
  LimeghostBrowser/AIToolStartPage.swift
```

Errors naming project types not in scope are expected noise from compiling one file alone. Errors naming `NS…` types, or reporting something "unavailable in iOS", are real. **Report what you find.** If the file is clean, add it to the iOS target's sources along with whatever it needs (`LimeghostTheme`, `ChromeIcons`, and any other file the compiler names) and write a thin wrapper. If it is not clean, write a fresh iOS view over `AIToolCatalog` instead — do not modify the Mac's file to make it portable, because that is a shared-surfaces refactor and belongs to its own task.

- [ ] **Step 2: Write the failing test**

Create `ios/Tests/StartSurfaceTests.swift`:

```swift
import XCTest
@testable import LimeghostShared

final class StartSurfaceTests: XCTestCase {
    /// A new tab opens the guide, not a blank page.
    @MainActor
    func testANewTabOpensTheGuide() throws {
        let host = WorkspaceHost.forTesting()
        host.workspace.addTab()
        let tab = try XCTUnwrap(host.workspace.selectedTab)
        XCTAssertEqual(tab.startSurface, .aiHome)
    }

    /// The guide is a local, bundled catalogue — no request is made to show it.
    /// Its task list is what the first minute is built on.
    func testTheCatalogueOffersTasksWithoutANetworkRequest() {
        XCTAssertFalse(AIToolCatalog.tasks.isEmpty)
    }
}
```

Confirm `AIToolCatalog.tasks` is the real accessor before relying on it:

```bash
grep -n "public static\|public var\|public let" macos/LimeghostBrowser/Sources/LimeghostCore/AIToolCatalog.swift | head -12
```

- [ ] **Step 3: Run it and watch it fail**, then write the view

Run the Task 2 Step 5 command, then implement `StartSurfaceScreen` per Step 1's finding, and show it in `BrowserScreen` when the selected tab's `startSurface == .aiHome`.

**The guide is a curated local directory of official links.** It must not gain live rankings, prices, availability claims, or any implication that Limeghost tested these tools or is paid by them. Opening a card is ordinary navigation and attaches no page content and no prompt.

- [ ] **Step 4: Run the tests and watch them pass**

Expected: `** TEST SUCCEEDED **`, 15 tests.

- [ ] **Step 5: Run it and look at it**

Task 3 Step 6 commands. **This is the first minute** — launch the app fresh and see whether the guide reads as a place to start. Note anything confusing in your report; that observation is worth more than the test count.

- [ ] **Step 6: Confirm the Mac is untouched, then commit**

```bash
cd macos/LimeghostBrowser && swift test 2>&1 | tail -3
git add ios
git commit -m "Open on the guide, so the first minute starts with a task

Every new tab and the Home button show the curated local directory, which is
bundled rather than fetched -- no request is made to display it, and opening
a card is ordinary navigation that attaches no page and no prompt."
```

---

### Task 8: CI, and the documents

**Files:**
- Modify: `.github/workflows/ci.yml`
- Modify: `docs/ios-browser-foundation.md`, `README.md`, `CHANGELOG.md`, `docs/project-context.md`
- Modify: `docs/superpowers/specs/2026-09-03-ios-pocket-browser-design.md` (§2 status)

- [ ] **Step 1: Add the app to CI**

Extend the existing `ios-simulator` job — do not add a second one, and do not touch `macos-browser`. It already discovers a simulator UDID at runtime; add a build of the app and a run of its tests using that same UDID:

```yaml
      - name: Build and test the iOS app
        working-directory: ios
        run: |
          xcodebuild test -scheme Limeghost \
            -destination "platform=iOS Simulator,id=$SIM_UDID"
```

- [ ] **Step 2: Update the documents to what is now true**

`docs/ios-browser-foundation.md` describes a shared layer with no app. There is now an app. Say what exists, what it does, how to build and run it, and — unchanged — that it installs on nobody's device but the founder's, that nothing is signed or notarized, and that no observed-user session has been run. **Do not describe Plan 3's features as present**: there is no assistant, no Reader, no Copy for AI and no bookmark import in this app yet.

Update `README.md`'s limits entry, add a `CHANGELOG.md` entry, and add one dated paragraph to `docs/project-context.md` recording that the phone shell exists.

- [ ] **Step 3: Verify everything, then commit**

```bash
cd macos/LimeghostBrowser && swift test 2>&1 | tail -3          # 492, 0 failures
cd macos/LimeghostBrowser && xcodebuild test -scheme LimeghostSharedLayer \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep "^\*\* TEST"
cd ios && xcodebuild test -scheme Limeghost \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" 2>&1 | grep "^\*\* TEST"
```

All three green.

```bash
git add -A
git commit -m "Run the phone app in CI, and write down what it is

The job that already runs the shared rules on a simulator now builds and
tests the app that uses them. The documents say what exists -- tabs, an
address bar, a switcher and the guide -- and, unchanged, that it installs on
nobody's device but the founder's, that nothing is signed or notarized, and
that no observed-user session has been run."
```

---

## Self-Review

**Spec coverage.** §2 in-v1 scope → Tasks 3–7 (tabs, private tabs, address bar with local completion, switcher, AI guide); *deferred* items are correctly absent (downloads, profile switcher, voice, pin/group creation). §4 the shell → Tasks 3, 4, 6, 7, with the assistant toggle's place reserved and empty. §6.1 bundle identifier → Task 1. §6.2 `clearframe.*` keys → Global Constraints. §6.3 one profile, default stores → Task 3's workspace construction. §3.2 platform protocol → Task 2. §9.4 XCTest only → Global Constraints.

**Not covered here, by design:** §5 the assistant overlay, Reader, Copy for AI (§2), the bookmark import/export bridge (§6.5), the privacy manifest (§6.7), and CloudKit (§6.6, blocked on enrolment). All belong to Plan 3.

**Placeholder scan.** No "TBD"/"TODO"/"similar to Task N". Tasks 5, 6 and 7 deliberately instruct the implementer to *read the real API before writing against it* rather than trusting a signature I transcribed — that is not a placeholder but the direct lesson of Plan 1, where the plan named a wrong file, a wrong scheme, a wrong constant location and a test that never existed. Every such step names the exact command to run.

**Type consistency.** `WorkspaceHost.forTesting()` is defined in Task 3 and used in Tasks 4–7. `BottomBarModel(urlString:tabCount:canGoBack:)` matches between its test and its implementation. `TabRow.isPrivate` is used consistently. `AddressSheetModel(workspace:)` matches. Where a shared-layer signature is uncertain — `BrowserWorkspace.init`, `canGoBack`, `instanceID`, `AIToolCatalog.tasks`, `PageSharing`, `DownloadTracking` — the step says to read it from source first, because Plan 1 proved I get these wrong from memory.

**Known risk.** Task 2 Step 4 and every later task edit `project.pbxproj` by hand to add sources and targets. That file is unforgiving and there is no generator available. If an edit corrupts it, `xcodebuild -list` stops reporting the scheme — that is the signal, and `git checkout ios/Limeghost.xcodeproj/project.pbxproj` is the recovery.
