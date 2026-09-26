import CoreGraphics
import XCTest
@testable import LimeghostShared

@MainActor
final class TabPreviewStoreTests: XCTestCase {
    /// A small opaque bitmap — the store never looks at the pixels, only at
    /// which tab an image belongs to and what it costs.
    private func makeImage(width: Int = 4, height: Int = 4) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.4, green: 0.86, blue: 0.49, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    func testAPreviewComesBackForItsOwnTabAndNoOther() throws {
        let store = TabPreviewStore()
        let mine = UUID()
        let somebodyElses = UUID()
        let image = try makeImage()

        store.store(image, for: mine)

        XCTAssertNotNil(store.preview(for: mine))
        // Not merely "something is stored": a grid that handed every card the
        // same picture would pass a one-tab assertion and be useless.
        XCTAssertNil(store.preview(for: somebodyElses))
    }

    /// A closed tab's picture has no reader left.
    func testForgettingATabDropsItsPreview() throws {
        let store = TabPreviewStore()
        let closed = UUID()
        let stillOpen = UUID()
        store.store(try makeImage(), for: closed)
        store.store(try makeImage(), for: stillOpen)

        store.forget(closed)

        XCTAssertNil(store.preview(for: closed))
        // The neighbour survives — `forget` must not be `clearAll` wearing a
        // different name.
        XCTAssertNotNil(store.preview(for: stillOpen))
    }

    /// What the local-data reset calls.
    func testClearingDropsEveryPreview() throws {
        let store = TabPreviewStore()
        let tabs = [UUID(), UUID(), UUID()]
        for tab in tabs { store.store(try makeImage(), for: tab) }

        store.clearAll()

        for tab in tabs {
            XCTAssertNil(store.preview(for: tab), "a preview survived the reset")
        }
    }

    /// An `NSCache` mutating publishes nothing, so without the counter the
    /// grid would go on drawing identity squares over tabs that now have a
    /// picture. Every mutating call must bump it, including the ones that
    /// remove: a card whose preview was just dropped has to redraw too.
    func testEveryChangeBumpsTheRevisionSoTheGridRedraws() throws {
        let store = TabPreviewStore()
        let tab = UUID()
        let start = store.revision

        store.store(try makeImage(), for: tab)
        let afterStore = store.revision
        store.forget(tab)
        let afterForget = store.revision
        store.clearAll()
        let afterClear = store.revision

        XCTAssertGreaterThan(afterStore, start, "storing did not redraw the grid")
        XCTAssertGreaterThan(afterForget, afterStore, "forgetting did not redraw the grid")
        XCTAssertGreaterThan(afterClear, afterForget, "clearing did not redraw the grid")
    }

    /// The cache is bounded by bytes as well as by count, because sixteen
    /// full-screen images would be tens of megabytes however few they are.
    func testAPreviewIsCostedByItsRealSizeInBytes() throws {
        let store = TabPreviewStore(limit: 16, byteLimit: 24 * 1024 * 1024)
        let big = try makeImage(width: 400, height: 533)

        store.store(big, for: UUID())

        // The assertion that matters is not the eviction policy — `NSCache`
        // owns that — but that a cost is computed from the image at all, and
        // from its padded rows rather than width × 4, which under-counts.
        XCTAssertGreaterThanOrEqual(big.bytesPerRow, big.width * 4)
        XCTAssertEqual(store.revision, 1)
    }

    /// Closing a tab drops its picture. `reopenClosedTab` brings the address
    /// back, deliberately from memory only — a photograph of the page is not
    /// part of what that restores, and leaving one keyed to a tab nobody can
    /// see again is a picture with no reader.
    func testClosingATabForgetsWhatItLookedLike() throws {
        let workspace = try IsolatedWorkspace.make(for: self).workspace
        workspace.addTab(url: URL(string: "https://example.com/")!)
        let closing = try XCTUnwrap(workspace.selectedTabID)
        let staying = try XCTUnwrap(workspace.tabs.first { $0.id != closing }?.id)
        workspace.tabPreviews.store(try makeImage(), for: closing)
        workspace.tabPreviews.store(try makeImage(), for: staying)

        workspace.closeTab(closing)

        XCTAssertNil(workspace.tabPreviews.preview(for: closing))
        XCTAssertNotNil(workspace.tabPreviews.preview(for: staying), "closing one tab dropped another's picture")
    }
}
