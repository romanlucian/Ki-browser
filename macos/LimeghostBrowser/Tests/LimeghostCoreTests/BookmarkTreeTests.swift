import XCTest
@testable import LimeghostCore

/// The folder tree that replaced the bookmarks home's drill-down.
///
/// Pure derivation, so every awkward case is reachable without a view: a
/// collapsed branch, a selection buried four levels down, and an imported file
/// that is not actually a tree.
final class BookmarkTreeTests: XCTestCase {
    private var folders: [BookmarkFolderRecord] = []
    private var bookmarks: [BookmarkRecord] = []

    private let projects = UUID()
    private let ideas = UUID()
    private let catLei = UUID()
    private let etsy = UUID()

    override func setUp() {
        super.setUp()
        // Projects › New projects ideeas › Cat Lei Real, plus a sibling root.
        // Shaped after the founder's own collection, which is four deep.
        folders = [
            folder(projects, "Projects", parent: nil),
            folder(ideas, "New projects ideeas", parent: projects),
            folder(catLei, "Cat Lei Real", parent: ideas),
            folder(etsy, "Etsy", parent: nil),
        ]
        bookmarks = [
            bookmark("A page", in: catLei),
            bookmark("Another", in: catLei),
            bookmark("Shop", in: etsy),
        ]
    }

    private func folder(_ id: UUID, _ title: String, parent: UUID?) -> BookmarkFolderRecord {
        BookmarkFolderRecord(id: id, title: title, emoji: "", parentID: parent)
    }

    private func bookmark(_ title: String, in folderID: UUID?) -> BookmarkRecord {
        BookmarkRecord(
            id: UUID(),
            title: title,
            url: "https://example.com/\(title.replacingOccurrences(of: " ", with: "-"))",
            createdAt: Date(),
            folderID: folderID
        )
    }

    func testACollapsedTreeShowsOnlyItsRoots() {
        let rows = BookmarkTree.rows(folders: folders, bookmarks: bookmarks, expanded: [])
        XCTAssertEqual(rows.map(\.folder.title), ["Etsy", "Projects"], "roots sort by title")
        XCTAssertTrue(rows.allSatisfy { $0.depth == 0 })
        XCTAssertEqual(rows.first { $0.folder.title == "Projects" }?.hasChildren, true)
        XCTAssertEqual(rows.first { $0.folder.title == "Etsy" }?.hasChildren, false)
    }

    func testExpandingAFolderRevealsOnlyItsDirectChildren() {
        let rows = BookmarkTree.rows(folders: folders, bookmarks: bookmarks, expanded: [projects])
        XCTAssertEqual(rows.map(\.folder.title), ["Etsy", "Projects", "New projects ideeas"])
        XCTAssertEqual(rows.last?.depth, 1)
        // The grandchild stays hidden: its own parent is still closed.
        XCTAssertFalse(rows.contains { $0.folder.id == catLei })
    }

    /// The case that separates a tree from a filtered list.
    ///
    /// Marking a deep folder expanded must not drag it into view when the
    /// branch above it is shut. Without this, expanding then collapsing a
    /// parent leaves orphaned grandchildren floating at the root.
    func testAnExpandedFolderStaysHiddenWhileItsParentIsCollapsed() {
        let rows = BookmarkTree.rows(
            folders: folders,
            bookmarks: bookmarks,
            expanded: [ideas, catLei]   // deep folders open, "Projects" shut
        )
        XCTAssertEqual(rows.map(\.folder.title), ["Etsy", "Projects"])
        XCTAssertFalse(rows.contains { $0.folder.id == ideas })
        XCTAssertFalse(rows.contains { $0.folder.id == catLei })
    }

    func testOpeningEveryAncestorRevealsTheDeepestFolder() {
        let expanded = BookmarkTree.ancestors(of: catLei, in: folders)
        XCTAssertEqual(expanded, [projects, ideas], "the folder itself is not one of its own ancestors")

        let rows = BookmarkTree.rows(folders: folders, bookmarks: bookmarks, expanded: expanded)
        XCTAssertEqual(rows.first { $0.folder.id == catLei }?.depth, 2)
    }

    func testCountsAreDirectChildrenAndNeverTheWholeBranch() {
        let rows = BookmarkTree.rows(
            folders: folders,
            bookmarks: bookmarks,
            expanded: BookmarkTree.ancestors(of: catLei, in: folders)
        )
        let projectsRow = rows.first { $0.folder.id == projects }
        // The branch below Projects holds two saved pages. Projects itself
        // holds none, and that is the number a tree shows — the two are one
        // triangle away. The old page showed both numbers under one label.
        XCTAssertEqual(projectsRow?.directBookmarkCount, 0)
        XCTAssertEqual(projectsRow?.directSubfolderCount, 1)

        let catLeiRow = rows.first { $0.folder.id == catLei }
        XCTAssertEqual(catLeiRow?.directBookmarkCount, 2)
        XCTAssertEqual(catLeiRow?.directSubfolderCount, 0)
    }

    func testThePathToAFolderReadsFromTheRootDown() {
        let path = BookmarkTree.path(to: catLei, in: folders)
        XCTAssertEqual(path.map(\.title), ["Projects", "New projects ideeas", "Cat Lei Real"])
    }

    /// Bookmarks arrive from other browsers' export files, which are not
    /// promised to be trees. A parent chain that loops would recurse until the
    /// stack gave out — a hang on launch, from somebody else's data.
    func testAFolderLoopFromAMalformedImportDoesNotHang() {
        let a = UUID(), b = UUID()
        let looped = [
            folder(a, "A", parent: b),
            folder(b, "B", parent: a),
            folder(etsy, "Etsy", parent: nil),
        ]
        let rows = BookmarkTree.rows(folders: looped, bookmarks: [], expanded: [a, b])
        // The loop is unreachable from the root, so it simply does not appear —
        // and, crucially, this call returns at all.
        XCTAssertEqual(rows.map(\.folder.title), ["Etsy"])

        XCTAssertEqual(BookmarkTree.path(to: a, in: looped).count, 2, "a loop must terminate, not repeat")
        XCTAssertFalse(BookmarkTree.ancestors(of: a, in: looped).contains(a))
    }
}
