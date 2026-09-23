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

    @MainActor
    private func eventually(timeout: TimeInterval = 3, _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
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
