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

    /// An address with no host to pull out is shown exactly as it stands.
    ///
    /// This is the third answer `addressLabel` can give and the only one the
    /// two tests above cannot reach: one has a host, the other is empty and
    /// gets the invitation instead. What stood here before asserted
    /// `tabCount == 4` and `canGoBack` straight back out of the memberwise
    /// initialiser that had just been handed them, so it could only have
    /// failed if Swift itself had; the count and the flag are carried to the
    /// view untouched and there is nothing derived about them to check.
    func testAnAddressWithNoHostIsShownAsItStands() {
        let model = BottomBarModel(urlString: "about:blank", tabCount: 1, canGoBack: false)
        XCTAssertEqual(model.addressLabel, "about:blank")
    }
}
