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
}
