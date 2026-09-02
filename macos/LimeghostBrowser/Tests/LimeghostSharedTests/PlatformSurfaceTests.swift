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
