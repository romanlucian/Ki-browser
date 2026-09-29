import XCTest
import WebKit
@testable import Limeghost
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

    // MARK: - A page's dialogs

    /// A page's `alert()` stops its script until somebody answers it. The
    /// dialog was presented from the window's root, which UIKit refuses while
    /// the root is already presenting — the tab switcher, the menu, Bookmarks,
    /// History and the address sheet are all sheets — and a refused dialog was
    /// never answered, so the page froze for as long as the tab lived.
    @MainActor
    func testAPageDialogAppearsOverASheetThatIsAlreadyUp() async throws {
        let sheet = try await sheetOverTheWindow()

        // Asked at once, while the sheet is still arriving: a page does not
        // wait for a sheet's animation before it calls `alert()`.
        let platform = IOSSessionPlatform()
        Task { @MainActor in await platform.presentAlert(message: "Still there?") }
        let shown = await eventually { sheet.presentedViewController is UIAlertController }

        XCTAssertTrue(shown, "the dialog was refused, and the page waits on it forever")
    }

    /// With nowhere to show it — the app in the background, no window — a
    /// dialog is answered as a person dismissing it would answer, at once,
    /// rather than never.
    @MainActor
    func testAPageDialogWithNowhereToAppearIsAnsweredAtOnce() async {
        let platform = IOSSessionPlatform()
        platform.presenter = { nil }

        let confirmed = await answer { await platform.presentConfirm(message: "Leave this page?") }
        let typed = await answer { await platform.presentPrompt(message: "Your name?", defaultText: "Ada") }
        let alerted = await answer { () async -> Bool in
            await platform.presentAlert(message: "Hello")
            return true
        }

        XCTAssertEqual(confirmed, .some(false))
        XCTAssertEqual(typed, .some(nil))
        XCTAssertNotNil(alerted, "an alert with nowhere to appear never returned")
    }

    /// A controller UIKit will not present from — one that is not in a window —
    /// is the same as having none.
    @MainActor
    func testAPageDialogUIKitRefusesIsAnsweredAtOnce() async {
        let platform = IOSSessionPlatform()
        let detached = UIViewController()
        platform.presenter = { detached }

        let confirmed = await answer { await platform.presentConfirm(message: "Leave this page?") }

        XCTAssertEqual(confirmed, .some(false), "a refused dialog was never answered")
    }

    /// A page can ask in a loop, and each dialog has to be answered before
    /// anything else on the screen can be touched. From a site's second
    /// dialog on, the person is offered a way to stop them.
    @MainActor
    func testASecondDialogOffersAWayToStopThem() async throws {
        let sheet = try await sheetOverTheWindow()
        let platform = IOSSessionPlatform()
        let stop = "Don’t Allow More Dialogs"

        Task { @MainActor in await platform.presentAlert(message: "One") }
        _ = await eventually { sheet.presentedViewController is UIAlertController }
        let first = try XCTUnwrap(sheet.presentedViewController as? UIAlertController)
        XCTAssertFalse(first.actions.contains { $0.title == stop }, "the first dialog offered to stop them")

        Task { @MainActor in await platform.presentAlert(message: "Two") }
        _ = await eventually { first.presentedViewController is UIAlertController }
        let second = try XCTUnwrap(first.presentedViewController as? UIAlertController, "the second dialog never appeared")
        XCTAssertTrue(second.actions.contains { $0.title == stop }, "the second dialog offered no way to stop them")
    }

    // MARK: - What the phone tells websites

    /// WebKit's own application name on an iPhone is the `Mobile/…` token,
    /// and setting ours replaced it: the phone told sites it was Safari with
    /// no "Mobile" in it, and sites that look for "Mobi" — MDN's advice — sent
    /// it their desktop pages.
    @MainActor
    func testThePhoneStillTellsSitesItIsMobile() async throws {
        let suiteName = "clearframe.iosUserAgent.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let session = BrowserSession(
            platform: IOSSessionPlatform(),
            downloadCenter: NoDownloads(),
            searchSettings: SearchSettingsStore(defaults: defaults)
        )
        addTeardownBlock { @MainActor in session.teardown() }
        _ = await eventually { session.hasCommittedNavigation && !session.webView.isLoading }

        let userAgent = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            session.webView.evaluateJavaScript("navigator.userAgent") { value, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: value as? String ?? "") }
            }
        }

        XCTAssertTrue(userAgent.contains("Mobile/"), "the phone's user agent lost its Mobile token: \(userAgent)")
        XCTAssertTrue(userAgent.contains("Version/"), "and must still carry Safari's version: \(userAgent)")
    }

    // MARK: - What the app declares

    /// A long press on a picture offers "Save to Photos", and iOS ends an app
    /// that touches the photo library without saying why it wants to. The key
    /// that says why was missing, so saving a picture from any page crashed
    /// Limeghost (Apple Developer Forums thread 772243).
    func testSavingAPictureFromAPageIsDeclared() {
        let reason = Bundle.main.object(forInfoDictionaryKey: "NSPhotoLibraryAddUsageDescription") as? String
        XCTAssertFalse((reason ?? "").isEmpty, "saving a picture from a page would crash the app")
    }

    /// The phone had **no app icon at all** until September 27, 2026: no asset
    /// catalog, no `ASSETCATALOG_COMPILER_APPICON_NAME`, nothing in the bundle
    /// but the in-app brand mark. iOS drew its grey placeholder on the home
    /// screen, and an app cannot be submitted without one either.
    ///
    /// Two assertions because they fail apart: the name can be set while the
    /// catalog compiles nothing, which is a build that looks configured and
    /// still shows a placeholder.
    func testTheAppHasAnIconForTheHomeScreen() throws {
        // The top-level key, which the asset catalog does not write when the
        // Info.plist is supplied rather than generated — and whose absence
        // App Store Connect rejects an upload for, while the home screen
        // looks perfectly correct. Nothing short of a submission notices.
        let named = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String
        XCTAssertEqual(named, "AppIcon", "an upload would be rejected for a missing CFBundleIconName")

        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        let files = primary?["CFBundleIconFiles"] as? [String] ?? []
        XCTAssertFalse(files.isEmpty, "the catalog named an icon it did not compile")
    }

    // MARK: - What an upload is checked for

    /// The app's Info.plist as it was built, every key in it. `Bundle`'s own
    /// lookups resolve device-suffixed keys for the device they run on, so on
    /// an iPhone Simulator they cannot see a `~ipad` key at all.
    private func builtInfoPlist() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Info", withExtension: "plist"))
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try XCTUnwrap(plist as? [String: Any])
    }

    /// Without this every TestFlight build waits in App Store Connect on the
    /// export-compliance question. Limeghost's only encryption is the system's
    /// own HTTPS, through WebKit, which is exempt; it has no cipher of its own.
    func testTheAppSaysItUsesNoEncryptionOfItsOwn() throws {
        XCTAssertEqual(
            try builtInfoPlist()["ITSAppUsesNonExemptEncryption"] as? Bool, false,
            "every upload would wait on the export-compliance question"
        )
    }

    /// The target builds for iPad as well as iPhone, and App Store Connect
    /// rejects an iPad app that cannot take all four orientations
    /// (ITMS-90474), because iPad multitasking needs them. The iPhone keeps
    /// its own three.
    func testAnIPadMayTurnTheAppAnyWayUp() throws {
        let iPad = try builtInfoPlist()["UISupportedInterfaceOrientations~ipad"] as? [String] ?? []
        XCTAssertEqual(Set(iPad), [
            "UIInterfaceOrientationPortrait",
            "UIInterfaceOrientationPortraitUpsideDown",
            "UIInterfaceOrientationLandscapeLeft",
            "UIInterfaceOrientationLandscapeRight",
        ], "an upload would be rejected for iPad multitasking without all four")
    }

    /// Apple requires a privacy manifest naming a reason for each of the
    /// "required reason" APIs an app calls, and the phone calls exactly one:
    /// `UserDefaults`, for its own settings, bookmarks and history (CA92.1,
    /// data only this app reads). Audited against every file the target
    /// compiles on September 29, 2026 — no file dates, disk space, boot time
    /// or keyboard lists. And it declares nothing collected and nobody
    /// tracked, because Limeghost sends nothing to its maker.
    func testThePrivacyManifestIsBundledAndSaysOnlyWhatIsTrue() throws {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            "the app ships no privacy manifest"
        )
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        let manifest = try XCTUnwrap(plist as? [String: Any])
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((manifest["NSPrivacyTrackingDomains"] as? [String])?.isEmpty, true)
        XCTAssertEqual((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty, true, "the manifest claims data is collected")
        let apis = manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        XCTAssertEqual(apis.map { $0["NSPrivacyAccessedAPIType"] as? String }, ["NSPrivacyAccessedAPICategoryUserDefaults"])
        XCTAssertEqual(apis.first?["NSPrivacyAccessedAPITypeReasons"] as? [String], ["CA92.1"])
    }

    /// Apple grants the default-browser entitlement only to an app that
    /// declares web links. Without the entitlement iOS still sends every http
    /// and https link to the default browser; with it, they can come here.
    func testTheAppDeclaresWebLinks() throws {
        let types = try builtInfoPlist()["CFBundleURLTypes"] as? [[String: Any]] ?? []
        let schemes = Set(types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] })
        XCTAssertTrue(schemes.isSuperset(of: ["http", "https"]), "the default-browser request requires both")
    }

    /// The home-screen name comes from `APP_DISPLAY_NAME`, one per
    /// configuration, so the cable build and a TestFlight build — two apps on
    /// one phone — need not be two identical icons. The cable build (Debug,
    /// which the tests run) stays "Limeghost" while TestFlight waits: the
    /// founder paused it on September 29, 2026, and the cable app is the only
    /// one on the phone. When TestFlight starts, Debug becomes "Dev Limeghost"
    /// — "Dev" first, because the home screen cuts a label from the end and
    /// "Limeghost Dev" showed as "Limegh…" on a 375-point screen — and this
    /// expectation changes with it.
    ///
    /// Asserting the value is what proves the setting reaches the bundle: an
    /// unset `APP_DISPLAY_NAME` builds an empty name, and iOS then falls back
    /// to `CFBundleName` with nothing failing anywhere.
    func testTheHomeScreenNameComesFromTheBuildSettings() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "Limeghost")
    }

    /// A site with a background video looked broken on the phone and correct
    /// in every other browser: it would not start on its own, and the tap that
    /// started it pulled the video out of the page into iOS's own player, with
    /// a scrubber, a pause button and a mute button laid over the design.
    ///
    /// Both are iOS defaults on a fresh `WKWebViewConfiguration`, and neither
    /// can be changed once the web view is built — which is why this is set on
    /// the configuration rather than in `prepareWebView`.
    @MainActor
    func testAPageMayPlayItsOwnVideoInThePage() {
        let configuration = WKWebViewConfiguration()
        IOSSessionPlatform().prepareConfiguration(configuration)

        XCTAssertTrue(
            configuration.allowsInlineMediaPlayback,
            "a page's video would be taken out of the page into iOS's own player"
        )
        // `.audio`, not `[]`: a muted video starts by itself and anything that
        // would make a sound still waits to be asked, which is Safari's rule.
        // `[]` would let any page start talking on its own.
        XCTAssertEqual(configuration.mediaTypesRequiringUserActionForPlayback, .audio)
        XCTAssertTrue(
            configuration.mediaTypesRequiringUserActionForPlayback.contains(.audio),
            "a page could start making a sound nobody asked for"
        )
    }

    // MARK: - Helpers

    /// A sheet over the window's root, the way the tab switcher or the menu
    /// sits over the page. Waits first for whatever an earlier test left
    /// presented to go, since UIKit refuses to present over a dismissal.
    @MainActor
    private func sheetOverTheWindow() async throws -> UIViewController {
        let root = try XCTUnwrap(IOSPageSharing.rootViewController, "the test host has no window")
        let clear = await eventually { root.presentedViewController == nil }
        XCTAssertTrue(clear, "an earlier presentation never went away")
        let sheet = UIViewController()
        root.present(sheet, animated: false)
        addTeardownBlock { @MainActor in root.dismiss(animated: false) }
        return sheet
    }

    /// What a dialog answered, or nil if it had not answered within the time
    /// allowed — so a dialog that never returns fails the test instead of
    /// hanging the suite.
    @MainActor
    private func answer<T>(within seconds: TimeInterval = 2, _ ask: @escaping @MainActor () async -> T) async -> T? {
        let answered = XCTestExpectation(description: "the dialog answered")
        var result: T?
        Task { @MainActor in
            result = await ask()
            answered.fulfill()
        }
        _ = await XCTWaiter().fulfillment(of: [answered], timeout: seconds)
        return result
    }
}
