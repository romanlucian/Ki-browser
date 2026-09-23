import AppKit
@testable import LimeghostShared
import XCTest
@preconcurrency import WebKit
@testable import LimeghostBrowser

/// A navigation carrying the facts a click on a link carries: which keys were
/// held, which button was pressed, and what kind of navigation it is.
@MainActor
private final class ClickedLink: WKNavigationAction {
    private let flags: NSEvent.ModifierFlags
    private let button: Int
    private let kind: WKNavigationType

    init(flags: NSEvent.ModifierFlags = [], button: Int = 0, kind: WKNavigationType = .linkActivated) {
        self.flags = flags
        self.button = button
        self.kind = kind
        super.init()
    }

    override var modifierFlags: NSEvent.ModifierFlags { flags }
    override var buttonNumber: Int { button }
    override var navigationType: WKNavigationType { kind }
}

/// What a click on a link asks for, read the way every Mac browser reads it.
/// Limeghost read none of it: ⌘-click and a middle click both replaced the
/// page being read.
@MainActor
final class LinkClickTests: XCTestCase {
    /// A `WKNavigationAction` is freed through WebKit's main run loop, which
    /// exists only once WebKit has started in this process. Run on its own,
    /// with no web view made yet, freeing one crashed the test process; run
    /// after other tests, it passed. Starting WebKit first makes the result
    /// independent of the order tests happen to run in.
    private static let webKitStarted = WKWebView(frame: .zero)

    override func setUp() async throws {
        _ = Self.webKitStarted
    }

    func testACommandClickOpensTheLinkBehindThePage() {
        XCTAssertEqual(MacSessionPlatform().newTabPlacement(for: ClickedLink(flags: .command)), .background)
    }

    func testAMiddleClickOpensTheLinkBehindThePage() {
        XCTAssertEqual(MacSessionPlatform().newTabPlacement(for: ClickedLink(button: 2)), .background)
    }

    func testACommandShiftClickOpensTheLinkInFront() {
        XCTAssertEqual(
            MacSessionPlatform().newTabPlacement(for: ClickedLink(flags: [.command, .shift])),
            .foreground
        )
    }

    func testAPlainClickStaysInTheTab() {
        XCTAssertNil(MacSessionPlatform().newTabPlacement(for: ClickedLink()))
        XCTAssertNil(MacSessionPlatform().newTabPlacement(for: ClickedLink(flags: .shift)))
    }

    /// Only a link somebody clicked. A script navigating while ⌘ happens to be
    /// held, or a form submitted with it, stays where it is — a form's data
    /// would not survive being moved to a new tab anyway.
    func testOnlyAClickedLinkIsSentToATab() {
        XCTAssertNil(MacSessionPlatform().newTabPlacement(for: ClickedLink(flags: .command, kind: .other)))
        XCTAssertNil(MacSessionPlatform().newTabPlacement(for: ClickedLink(flags: .command, kind: .formSubmitted)))
        XCTAssertNil(MacSessionPlatform().newTabPlacement(for: ClickedLink(button: 2, kind: .reload)))
    }
}
