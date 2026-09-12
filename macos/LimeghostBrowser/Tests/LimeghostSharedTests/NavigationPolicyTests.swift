import XCTest
import WebKit
@testable import LimeghostShared

/// The page-load hook, read as a decision, and a tab's request for a site's
/// desktop version.
///
/// The decision used to live only inside the navigation delegate, where no
/// test reached it. It is a pure function of four facts now, so each branch
/// is checked here with plain values, on the Mac and on the Simulator alike.
@MainActor
final class NavigationPolicyTests: XCTestCase {
    private let page = URL(string: "https://example.com/owls")!

    // MARK: - The decision, one branch at a time

    /// A link that asks to be saved is saved, whatever its address. Asked
    /// before anything else, because `<a download href="blob:…">` has an
    /// address no navigation would accept.
    func testALinkThatAsksToBeSavedIsDownloaded() {
        let blob = URL(string: "blob:https://example.com/5f0c")!
        XCTAssertEqual(
            BrowserSession.decide(shouldPerformDownload: true, targetFrameIsMain: true, url: blob),
            .download
        )
    }

    /// A link aimed at a new window opens a tab of its own.
    func testALinkWithNoTargetFrameOpensInANewTab() {
        XCTAssertEqual(
            BrowserSession.decide(shouldPerformDownload: false, targetFrameIsMain: nil, url: page),
            .openInNewTab(page)
        )
    }

    /// Going back onto a tab's first entry, `about:blank`, is a return to its
    /// start surface, not a link Limeghost cannot open.
    func testGoingBackOntoTheStartPageRestoresTheStartSurface() {
        let blank = URL(string: "about:blank")!
        XCTAssertEqual(
            BrowserSession.decide(shouldPerformDownload: false, targetFrameIsMain: true, url: blank),
            .restoreStartSurface
        )
    }

    /// Any other main-frame address that is not a web page goes to
    /// `handleUnsupportedLink`, which hands `mailto:` and `tel:` to their
    /// apps and names the rest in a notice.
    func testAnAddressThatIsNotAWebPageIsUnsupported() {
        let script = URL(string: "javascript:alert(1)")!
        XCTAssertEqual(
            BrowserSession.decide(shouldPerformDownload: false, targetFrameIsMain: true, url: script),
            .unsupported(script)
        )
    }

    /// A web page in the main frame loads, and is recorded as the page asked for.
    func testAWebPageLoadsAndIsRecordedAsThePageAskedFor() {
        XCTAssertEqual(
            BrowserSession.decide(shouldPerformDownload: false, targetFrameIsMain: true, url: page),
            .allow(mainFrameURL: page)
        )
    }

    /// A frame inside the page loads without becoming the page: nothing is
    /// recorded, whatever its address.
    func testAFrameInsideThePageLoadsWithoutBecomingThePage() {
        let frame = URL(string: "https://ads.example/frame")!
        XCTAssertEqual(
            BrowserSession.decide(shouldPerformDownload: false, targetFrameIsMain: false, url: frame),
            .allow(mainFrameURL: nil)
        )
    }

    // MARK: - The question WebKit asks

    /// WebKit asks the variant of the policy question that carries
    /// `WKWebpagePreferences`, and when a delegate answers it, never asks the
    /// older one (`WKNavigationDelegate.h`). The session answers that variant
    /// and only that one. So the desktop switch is read on every navigation,
    /// and no dead copy of the old hook is left to be edited by mistake.
    ///
    /// Asked by selector, because a Swift method that nearly matches an
    /// optional Objective-C requirement compiles with at most a warning and
    /// is then never called.
    func testTheSessionAnswersTheQuestionThatCarriesTheContentMode() {
        let session = makeSession()
        XCTAssertTrue(session.responds(
            to: NSSelectorFromString("webView:decidePolicyForNavigationAction:preferences:decisionHandler:")
        ))
        XCTAssertFalse(session.responds(
            to: NSSelectorFromString("webView:decidePolicyForNavigationAction:decisionHandler:")
        ))
    }

    // MARK: - The desktop switch

    /// With the switch off, WebKit's preferences go back exactly as they came
    /// in. That is all the Mac ever does: it already gets desktop pages.
    func testWithTheSwitchOffTheContentModeIsLeftAlone() {
        let preferences = WKWebpagePreferences()
        BrowserSession.applyContentMode(prefersDesktopSite: false, to: preferences)
        XCTAssertEqual(preferences.preferredContentMode, .recommended)
    }

    /// With it on, the site is asked for its desktop version.
    func testWithTheSwitchOnTheSiteIsAskedForItsDesktopVersion() {
        let preferences = WKWebpagePreferences()
        BrowserSession.applyContentMode(prefersDesktopSite: true, to: preferences)
        XCTAssertEqual(preferences.preferredContentMode, .desktop)
    }

    /// A tab starts with the switch off, and it turns on and off again.
    func testTheSwitchStartsOffAndTurnsOnAndOff() {
        let session = makeSession()
        XCTAssertFalse(session.prefersDesktopSite)

        session.setPrefersDesktopSite(true)
        XCTAssertTrue(session.prefersDesktopSite)

        session.setPrefersDesktopSite(false)
        XCTAssertFalse(session.prefersDesktopSite)
    }

    /// A throwaway session, on a defaults suite of its own that is emptied
    /// afterwards. `RecordingPlatform` and `NoDownloads` are the stand-ins
    /// this target's other tests already use.
    private func makeSession() -> BrowserSession {
        let suiteName = "clearframe.navigationPolicy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return BrowserSession(
            platform: RecordingPlatform(),
            downloadCenter: NoDownloads(),
            searchSettings: SearchSettingsStore(defaults: defaults)
        )
    }
}
