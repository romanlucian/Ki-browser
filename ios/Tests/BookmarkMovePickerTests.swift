import XCTest
import LimeghostCore
@testable import Limeghost

final class BookmarkMovePickerTests: XCTestCase {
    /// The top level first, then every folder with its children beneath it,
    /// alphabetical within a parent, each indented one step past its parent.
    /// The input is deliberately out of order.
    func testDestinationsListTheTopLevelThenTheTreeIndented() {
        let travel = BookmarkFolderRecord(title: "Travel")
        let recipes = BookmarkFolderRecord(title: "Recipes")
        let soups = BookmarkFolderRecord(title: "Soups", parentID: recipes.id)
        let bread = BookmarkFolderRecord(title: "Bread", parentID: recipes.id)

        let rows = BookmarkDestinations.rows(folders: [travel, soups, recipes, bread])

        XCTAssertEqual(rows.map(\.title), ["Bookmarks", "Recipes", "Bread", "Soups", "Travel"])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 2, 2, 1])
        XCTAssertNil(rows.first?.folderID, "the first row is the top level")
        XCTAssertEqual(rows[2].folderID, bread.id)
    }
}
