import Combine
import UIKit
import WebKit
import XCTest
@testable import Limeghost
@testable import LimeghostShared

@MainActor
final class AssistantOnThePhoneTests: XCTestCase {
    /// A suite of its own, emptied afterwards: these tests run inside the app.
    private func makeHost() throws -> WorkspaceHost {
        let suiteName = "clearframe.iosAssistant.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return WorkspaceHost.forTesting(defaults: defaults)
    }

    // MARK: - The assistant and the page

    /// A phone never has room for the page and the assistant at once, so
    /// asking for a page makes the assistant leave rather than shrink, and
    /// the conversation stays loaded.
    func testAskingForAPageMakesTheAssistantLeave() throws {
        let host = try makeHost()
        let companion = host.workspace.aiCompanion
        companion.toggle()
        XCTAssertTrue(companion.isVisible)

        host.workspace.open("https://example.com/")

        XCTAssertFalse(companion.isVisible, "the page opened behind the assistant")
        XCTAssertNotNil(companion.session, "leaving threw the conversation away")
    }

    /// The host hears the assistant open; otherwise the bar's button never lights.
    func testTheHostHearsTheAssistantOpen() throws {
        let host = try makeHost()
        var heard = false
        let subscription = host.objectWillChange.sink { _ in heard = true }
        defer { subscription.cancel() }

        host.workspace.aiCompanion.toggle()

        XCTAssertTrue(heard)
    }

    /// Reader shows the page the assistant covers, so opening it uncovers the page.
    func testReaderFromTheMenuUncoversThePage() async throws {
        let host = try makeHost()
        let companion = host.workspace.aiCompanion
        companion.toggle()

        await PageMenuActions(workspace: host.workspace).perform(.reader)

        XCTAssertFalse(companion.isVisible)
    }

    /// Find in Page likewise: a match highlighted under the assistant helps nobody.
    func testFindInPageFromTheMenuUncoversThePage() async throws {
        let host = try makeHost()
        let companion = host.workspace.aiCompanion
        companion.toggle()

        await PageMenuActions(workspace: host.workspace).perform(.find)

        XCTAssertFalse(companion.isVisible)
    }

    /// On the phone a sign-in window opens over the assistant, not as a tab
    /// hidden behind it.
    func testThePhoneShowsSignInWindowsOverTheAssistant() throws {
        let host = try makeHost()
        let companion = host.workspace.aiCompanion
        companion.toggle()
        let tabsBefore = host.workspace.visibleTabs.count

        _ = try XCTUnwrap(companion.session).onRequestPopupWebView?(WKWebViewConfiguration())

        XCTAssertNotNil(companion.popup)
        XCTAssertEqual(host.workspace.visibleTabs.count, tabsBefore)
    }

    // MARK: - Layout rules

    /// A small drag leaves the assistant where it is; a long or a flung one
    /// closes it; dragging up never does.
    func testSwipingDownFarOrFastClosesTheAssistant() {
        XCTAssertFalse(AssistantDismissal.closes(translation: 40, predictedEnd: 90))
        XCTAssertTrue(AssistantDismissal.closes(translation: 130, predictedEnd: 140))
        XCTAssertTrue(AssistantDismissal.closes(translation: 60, predictedEnd: 320))
        XCTAssertFalse(AssistantDismissal.closes(translation: -50, predictedEnd: -200))
    }

    /// While the assistant is open, a notice gets its own strip above the bar.
    /// Floating over the assistant, it landed on the provider's message box.
    func testANoticeNeverCoversTheAssistant() {
        XCTAssertEqual(NoticePlacement.forAssistant(isOpen: false), .overThePage)
        XCTAssertEqual(NoticePlacement.forAssistant(isOpen: true), .aboveTheBar)
    }

    /// The find bar stays while finding, because it needs the keyboard. The
    /// bar steps aside while anything else is typed, as Safari's does.
    func testTheBarStepsAsideWhileTyping() {
        XCTAssertEqual(BottomChromeContent.showing(isFinding: false, keyboardIsUp: false), .bar)
        XCTAssertEqual(BottomChromeContent.showing(isFinding: false, keyboardIsUp: true), .nothing)
        XCTAssertEqual(BottomChromeContent.showing(isFinding: true, keyboardIsUp: true), .findBar)
    }

    /// The observer follows the system's own keyboard notifications.
    func testTheKeyboardObserverFollowsTheSystem() {
        let center = NotificationCenter()
        let keyboard = KeyboardObserver(center: center)
        XCTAssertFalse(keyboard.isUp)

        center.post(name: UIResponder.keyboardWillShowNotification, object: nil)
        XCTAssertTrue(keyboard.isUp)

        center.post(name: UIResponder.keyboardWillHideNotification, object: nil)
        XCTAssertFalse(keyboard.isUp)
    }
}
