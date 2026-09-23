import LimeghostCore
@testable import LimeghostShared
import Foundation
import WebKit
import XCTest

/// SwiftUI keeps a closed window's scene and can bring it back from the Dock.
/// `teardownForWindowClose` promises that what comes back is a clean window —
/// "exactly the state a genuinely new window starts in" — and the assistant is
/// part of that window.
@MainActor
final class CompanionWindowCloseTests: XCTestCase {
    /// A window closed mid-comparison came back still comparing, with a second
    /// column whose conversation had been torn down with the window.
    func testAWindowClosedWhileComparingComesBackWithoutAComparison() throws {
        let workspace = try IsolatedWorkspace.make(for: self).workspace
        let companion = workspace.aiCompanion
        companion.show()
        companion.startComparing()
        XCTAssertTrue(companion.isComparing)

        workspace.teardownForWindowClose()
        workspace.windowIsVisibleAgain()

        XCTAssertFalse(companion.isComparing, "the revived window is still comparing")
        XCTAssertFalse(companion.isExpanded, "the revived window's assistant still fills it")
    }

    /// An assistant that stepped aside because the window was too narrow comes
    /// back by itself when the window widens. After the window closed, it came
    /// back by itself into the revived one — a panel nobody opened.
    func testAnAssistantThatLeftForLackOfRoomStaysGoneInARevivedWindow() throws {
        let workspace = try IsolatedWorkspace.make(for: self).workspace
        let companion = workspace.aiCompanion
        companion.show()
        companion.setCanShareWindow(false)
        workspace.addTab()
        XCTAssertFalse(companion.isVisible)

        workspace.teardownForWindowClose()
        workspace.windowIsVisibleAgain()
        companion.setCanShareWindow(true)

        XCTAssertFalse(companion.isVisible, "the assistant opened itself in a window that should have come back clean")
    }
}
