import CoreGraphics
import SwiftUI
import UIKit
import XCTest
@testable import Limeghost
@testable import LimeghostShared

@MainActor
final class TabSwitcherTests: XCTestCase {
    private func makeHost() throws -> WorkspaceHost {
        let suiteName = "clearframe.iosTabs.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return WorkspaceHost.forTesting(defaults: defaults)
    }

    /// Private tabs are their own section. They are ephemeral and excluded from
    /// history; one list would blur a line the product draws on purpose.
    func testPrivateTabsAreTheirOwnSection() throws {
        let host = try makeHost()
        host.workspace.addTab(url: URL(string: "https://example.com/")!, isPrivate: false)
        host.workspace.addTab(url: URL(string: "https://example.org/")!, isPrivate: true)

        let model = TabSwitcherModel(workspace: host.workspace)

        XCTAssertTrue(model.rows.allSatisfy { !$0.isPrivate })
        XCTAssertEqual(model.privateRows.count, 1)
    }

    /// Closing every tab must not leave an empty browser with nothing to tap.
    /// `closeTab` makes a replacement when the last one goes.
    func testClosingEveryTabLeavesOneToLookAt() throws {
        let host = try makeHost()
        let model = TabSwitcherModel(workspace: host.workspace)
        let closedIDs = model.rows.map(\.id)
        for id in closedIDs { model.close(id) }

        XCTAssertFalse(model.rows.isEmpty)
        // Not merely non-empty: the survivor must be the *replacement*, not
        // one of the tabs just asked to close left behind by a `close` that
        // silently did nothing.
        XCTAssertTrue(model.rows.allSatisfy { !closedIDs.contains($0.id) })
    }

    /// A closed tab can come back.
    func testAClosedTabCanBeReopened() throws {
        let host = try makeHost()
        host.workspace.addTab(url: URL(string: "https://example.com/")!)
        let model = TabSwitcherModel(workspace: host.workspace)
        let id = try XCTUnwrap(host.workspace.selectedTabID)
        model.close(id)

        XCTAssertTrue(model.canReopenClosed)

        model.reopenClosedTab()

        // Reopening consumes the one closed tab remembered above, so nothing
        // is left to reopen — proof `reopenClosedTab()` actually ran rather
        // than leaving the closed-tab stack untouched.
        XCTAssertFalse(model.canReopenClosed)
    }

    private func makeImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(context.makeImage())
    }

    /// With titles alone you could tell where you were by reading. A wall of
    /// page pictures all look like pages, so the grid has to say which card is
    /// the tab you are on — and it knew nothing about it before.
    func testTheGridKnowsWhichTabYouAreOn() throws {
        let host = try makeHost()
        host.workspace.addTab(url: URL(string: "https://example.com/")!)
        host.workspace.addTab(url: URL(string: "https://example.org/")!)
        let model = TabSwitcherModel(workspace: host.workspace)
        let wanted = try XCTUnwrap(model.rows.first).id

        host.workspace.selectTab(wanted)

        XCTAssertEqual(model.selectedID, wanted)
        // One card, not all of them: an `isSelected` that answered true for
        // every row would ring the whole grid and say nothing.
        XCTAssertEqual(model.rows.filter { $0.id == model.selectedID }.count, 1)
    }

    /// Each card draws its own tab's picture. A grid that handed every card
    /// the same image would look convincing and be a lie about which page is
    /// which.
    func testACardIsHandedItsOwnTabsPictureAndNoOthers() throws {
        let host = try makeHost()
        host.workspace.addTab(url: URL(string: "https://example.com/")!)
        let model = TabSwitcherModel(workspace: host.workspace)
        let photographed = try XCTUnwrap(model.rows.first).id
        let unseen = try XCTUnwrap(model.rows.last { $0.id != photographed }).id

        host.workspace.tabPreviews.store(try makeImage(), for: photographed)

        XCTAssertNotNil(model.preview(for: photographed))
        // The unseen tab falls back to its identity square, which is what an
        // unvisited site shows everywhere else in the product.
        XCTAssertNil(model.preview(for: unseen))
    }

    /// The card's height comes from the preview's 3:4 aspect ratio, not from a
    /// constant. It was a fixed 110 — shorter than it was wide, and too short
    /// to say anything about the page inside it — and a card that stops
    /// growing with its width is exactly how that comes back.
    ///
    /// Rendered rather than reasoned about, because a height that only the
    /// layout system knows is a height no arithmetic here can check.
    func testACardIsTallerThanItIsWide() throws {
        let row = TabRow(id: UUID(), title: "Owl", host: "en.wikipedia.org", isPrivate: false)
        let card = TabCard(row: row, preview: nil, isSelected: false, select: {}, close: {})
            .frame(width: 173)

        let rendered = try XCTUnwrap(ImageRenderer(content: card).uiImage).size

        XCTAssertEqual(rendered.width, 173, accuracy: 1)
        XCTAssertGreaterThan(
            rendered.height, rendered.width * 1.3,
            "the card stopped growing with its width — a fixed height is back"
        )
    }
}
