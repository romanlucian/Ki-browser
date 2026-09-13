import Foundation
import XCTest
@testable import LimeghostShared

final class BrowserUserAgentTests: XCTestCase {
    /// Where there is no Safari to read, which is every iPhone, the version
    /// claimed is the operating system's own: on iOS, Safari ships with the
    /// system. It used to be a fixed "26.5" whatever the phone ran. The test
    /// hands in iOS 18.7.8 because this Mac runs macOS 26.5, where the old
    /// constant happened to be right.
    func testWithNoSafariToReadTheVersionIsTheSystemsOwn() {
        let phone = OperatingSystemVersion(majorVersion: 18, minorVersion: 7, patchVersion: 8)
        XCTAssertEqual(BrowserUserAgent.fallbackVersion(for: phone), "18.7")
        XCTAssertEqual(
            BrowserUserAgent.fallbackSafariVersion,
            BrowserUserAgent.fallbackVersion(for: ProcessInfo.processInfo.operatingSystemVersion)
        )
    }
}
