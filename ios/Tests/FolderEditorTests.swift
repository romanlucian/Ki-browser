import XCTest
import LimeghostCore
@testable import Limeghost
@testable import LimeghostShared

@MainActor
final class FolderEditorTests: XCTestCase {
    /// A suite of its own, emptied afterwards: these tests run inside the app.
    private func makeHost() throws -> WorkspaceHost {
        let suiteName = "clearframe.iosFolderEditor.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return WorkspaceHost.forTesting(defaults: defaults)
    }

    private func firstIconID(in style: LimeghostIconStyle, except excluded: String? = nil) throws -> String {
        let ids = LimeghostIconCategory.allCases
            .flatMap { LimeghostIconCatalog.icons(in: $0, style: style) }
            .map(\.id)
        return try XCTUnwrap(ids.first { $0 != excluded }, "the \(style) set has no icons")
    }

    /// The editor opens on what the folder has now — its name, the icon it
    /// draws, its colour — and on the set that icon belongs to, so editing a
    /// folder never silently moves it to another set's grid. A multicolour
    /// icon offers no colour, because it cannot take one.
    func testTheEditorOpensOnWhatTheFolderHasNow() throws {
        let store = try makeHost().workspace.dataStore
        let sticky = try firstIconID(in: .stickies)
        let travel = try XCTUnwrap(store.createBookmarkFolder(title: "Travel", iconID: sticky, colorID: "amber", parentID: nil))

        let edit = FolderEdit(folder: travel)

        XCTAssertEqual(edit.title, "Travel")
        XCTAssertEqual(edit.iconID, sticky)
        XCTAssertEqual(edit.color, .amber)
        XCTAssertEqual(edit.style, .stickies, "the editor opened on another set's grid")
        XCTAssertFalse(edit.selectedIsTintable, "a multicolour icon was offered a colour it cannot take")
    }

    /// Save writes the name, the icon and the colour in one update, and
    /// nothing reaches the store before it: Cancel has to leave the folder
    /// as it was.
    func testSaveWritesNameIconAndColourAndNothingBefore() throws {
        let store = try makeHost().workspace.dataStore
        let palette = try firstIconID(in: .limeghost)
        let other = try firstIconID(in: .limeghost, except: palette)
        let folder = try XCTUnwrap(store.createBookmarkFolder(title: "Travel", iconID: palette, colorID: "amber", parentID: nil))
        var edit = FolderEdit(folder: folder)

        edit.title = "Holidays"
        edit.iconID = other
        edit.color = .blue
        XCTAssertEqual(store.bookmarkFolder(id: folder.id)?.title, "Travel", "the folder changed before Save")

        edit.save(to: store)

        let saved = try XCTUnwrap(store.bookmarkFolder(id: folder.id))
        XCTAssertEqual(saved.title, "Holidays")
        XCTAssertEqual(saved.iconID, other)
        XCTAssertEqual(saved.colorID, "blue")
    }

    /// Changing only the name keeps the icon and the colour — what Rename…
    /// promised before this screen replaced it for folders.
    func testChangingOnlyTheNameKeepsIconAndColour() throws {
        let store = try makeHost().workspace.dataStore
        let palette = try firstIconID(in: .limeghost)
        let travel = try XCTUnwrap(store.createBookmarkFolder(title: "Travel", iconID: palette, colorID: "amber", parentID: nil))
        var edit = FolderEdit(folder: travel)

        edit.title = "Holidays"
        edit.save(to: store)

        let saved = try XCTUnwrap(store.bookmarkFolder(id: travel.id))
        XCTAssertEqual(saved.title, "Holidays")
        XCTAssertEqual(saved.iconID, palette)
        XCTAssertEqual(saved.colorID, "amber")
    }

    // MARK: - A new folder

    /// New Folder opens this screen too, so everybody who makes a folder sees
    /// that it can have an icon: with no name yet, the plain folder, and mint —
    /// what the Mac's New Folder opens with — and Create off until it has a
    /// name.
    func testANewFolderStartsBlankPlainAndMint() throws {
        let edit = FolderEdit(newIn: nil)

        XCTAssertTrue(edit.isNew)
        XCTAssertEqual(edit.title, "")
        XCTAssertEqual(edit.iconID, LimeghostIconCatalog.defaultIconID)
        XCTAssertEqual(edit.color, .mint)
        XCTAssertEqual(edit.style, .limeghost)
        XCTAssertFalse(edit.canSave, "Create was on with no name")
    }

    /// Create files the folder inside the one on screen, with the name, icon
    /// and colour chosen, and nowhere else.
    func testCreateFilesTheFolderWhereItWasAskedForAsChosen() throws {
        let store = try makeHost().workspace.dataStore
        let recipes = try XCTUnwrap(store.createBookmarkFolder(title: "Recipes", iconID: try firstIconID(in: .limeghost), parentID: nil))
        let other = try firstIconID(in: .limeghost, except: LimeghostIconCatalog.defaultIconID)
        var edit = FolderEdit(newIn: recipes.id)

        edit.title = "  Soups "
        edit.iconID = other
        edit.color = .blue
        edit.save(to: store)

        let soups = try XCTUnwrap(store.bookmarkFolders(in: recipes.id).first)
        XCTAssertEqual(store.bookmarkFolders(in: recipes.id).count, 1)
        XCTAssertEqual(soups.title, "Soups")
        XCTAssertEqual(soups.iconID, other)
        XCTAssertEqual(soups.colorID, "blue")
        XCTAssertEqual(store.bookmarkFolders(in: nil).map(\.title), ["Recipes"], "the folder landed at the top level too")
    }

    /// A new folder needs a name, as on the Mac: without one, nothing is made.
    func testANewFolderNeedsAName() throws {
        let store = try makeHost().workspace.dataStore
        var edit = FolderEdit(newIn: nil)

        edit.title = "   "
        edit.save(to: store)

        XCTAssertTrue(store.bookmarkFolders.isEmpty, "a folder was made with no name")
    }

    // MARK: - Either way

    /// An empty name cannot be saved, as on the Mac: Save is off, and saving
    /// anyway changes nothing.
    func testAnEmptyNameCannotBeSaved() throws {
        let store = try makeHost().workspace.dataStore
        let travel = try XCTUnwrap(store.createBookmarkFolder(title: "Travel", iconID: try firstIconID(in: .limeghost), parentID: nil))
        var edit = FolderEdit(folder: travel)

        edit.title = "   "

        XCTAssertFalse(edit.canSave)
        edit.save(to: store)
        XCTAssertEqual(store.bookmarkFolder(id: travel.id)?.title, "Travel")
    }
}
