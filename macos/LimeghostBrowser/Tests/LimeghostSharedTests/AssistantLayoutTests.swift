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
