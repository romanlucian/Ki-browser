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

    /// Setting WebKit's application name *replaces* its platform default. On
    /// an iPhone that default is the `Mobile/…` token, and sites that choose
    /// their mobile layout by looking for "Mobi" — MDN's own recommendation —
    /// sent the phone their desktop pages. The platform's token is kept.
    func testThePlatformsOwnTokenStaysInTheApplicationName() {
        XCTAssertEqual(
            BrowserUserAgent.applicationName(platformDefault: "Mobile/15E148", safariVersion: "18.7"),
            "Version/18.7 Mobile/15E148 Safari/605.1.15"
        )
    }

    /// With no platform token — the Mac — the name is what it always was.
    func testWithNoPlatformTokenTheApplicationNameIsUnchanged() {
        XCTAssertEqual(
            BrowserUserAgent.applicationName(platformDefault: nil, safariVersion: "26.5"),
            "Version/26.5 Safari/605.1.15"
        )
        XCTAssertEqual(
            BrowserUserAgent.applicationName(platformDefault: "  ", safariVersion: "26.5"),
            "Version/26.5 Safari/605.1.15"
        )
    }
}
