import XCTest
@testable import Limeghost

final class BottomBarTests: XCTestCase {
    /// The pill shows the host. A phone has no room for a query string, and the
    /// host is the part that answers "where am I".
    func testTheAddressPillShowsTheHost() {
        let model = BottomBarModel(urlString: "https://www.example.com/a/long/path?q=1", tabCount: 1, canGoBack: false)
        XCTAssertEqual(model.addressLabel, "example.com")
    }

    /// An empty tab has nothing to show, and this is what invites the first tap.
    func testAnEmptyAddressInvitesTyping() {
        let model = BottomBarModel(urlString: "", tabCount: 1, canGoBack: false)
        XCTAssertEqual(model.addressLabel, "Search or enter a website")
    }

    /// The tab button carries the count, because on a phone the tabs are not
    /// otherwise visible.
    func testTheTabButtonCountsTheTabs() {
        let model = BottomBarModel(urlString: "https://example.com/", tabCount: 4, canGoBack: true)
        XCTAssertEqual(model.tabCount, 4)
        XCTAssertTrue(model.canGoBack)
    }
}
