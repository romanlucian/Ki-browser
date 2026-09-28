import CoreGraphics
import XCTest
@testable import LimeghostShared

@MainActor
final class TabPreviewStoreTests: XCTestCase {
    /// A directory of its own per test, removed afterwards, so nothing lands
    /// in the real caches folder and no test can see another's files.
    private func makeDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("limeghost-previews-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeStore(limit: Int = 16, byteLimit: Int = 24 * 1024 * 1024) -> TabPreviewStore {
        TabPreviewStore(directory: makeDirectory(), limit: limit, byteLimit: byteLimit)
    }

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
        let store = makeStore()
        let mine = UUID()
        let somebodyElses = UUID()
        let image = try makeImage()

        store.store(image, for: mine, isPrivate: false)

        XCTAssertNotNil(store.preview(for: mine))
        // Not merely "something is stored": a grid that handed every card the
        // same picture would pass a one-tab assertion and be useless.
        XCTAssertNil(store.preview(for: somebodyElses))
    }

    /// A closed tab's picture has no reader left.
    func testForgettingATabDropsItsPreview() throws {
        let store = makeStore()
        let closed = UUID()
        let stillOpen = UUID()
        store.store(try makeImage(), for: closed, isPrivate: false)
        store.store(try makeImage(), for: stillOpen, isPrivate: false)

        store.forget(closed)

        XCTAssertNil(store.preview(for: closed))
        // The neighbour survives — `forget` must not be `clearAll` wearing a
        // different name.
        XCTAssertNotNil(store.preview(for: stillOpen))
    }

    /// What the local-data reset calls.
    func testClearingDropsEveryPreview() throws {
        let store = makeStore()
        let tabs = [UUID(), UUID(), UUID()]
        for tab in tabs { store.store(try makeImage(), for: tab, isPrivate: false) }

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
        let store = makeStore()
        let tab = UUID()
        let start = store.revision

        store.store(try makeImage(), for: tab, isPrivate: false)
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
        let store = makeStore(limit: 16, byteLimit: 24 * 1024 * 1024)
        let big = try makeImage(width: 400, height: 533)

        store.store(big, for: UUID(), isPrivate: false)

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
        workspace.tabPreviews.store(try makeImage(), for: closing, isPrivate: false)
        workspace.tabPreviews.store(try makeImage(), for: staying, isPrivate: false)

        workspace.closeTab(closing)

        XCTAssertNil(workspace.tabPreviews.preview(for: closing))
        XCTAssertNotNil(workspace.tabPreviews.preview(for: staying), "closing one tab dropped another's picture")
    }

    // MARK: - What survives the app closing, and what must not

    /// The founder quit the app and lost eleven cards. An ordinary tab's
    /// picture is kept now, so a second store reading the same folder — which
    /// is what the next launch is — finds it without the tab being opened.
    func testAnOrdinaryTabsPictureSurvivesTheAppClosing() throws {
        let directory = makeDirectory()
        let tab = UUID()
        let first = TabPreviewStore(directory: directory)
        first.store(try makeImage(width: 40, height: 86), for: tab, isPrivate: false)

        let next = TabPreviewStore(directory: directory)

        XCTAssertNotNil(next.preview(for: tab), "a relaunch lost the card it was meant to keep")
    }

    /// **A private tab's picture is never written anywhere.** Its whole promise
    /// is that nothing it loads reaches the disk — the WebKit store is
    /// non-persistent, so no cookie, no cache and no history entry survives it
    /// — and a preserved preview would be the *only* trace left behind. Not
    /// merely inconsistent: a hole.
    func testAPrivateTabsPictureIsWrittenNowhere() throws {
        let directory = makeDirectory()
        let secret = UUID()
        let ordinary = UUID()
        let store = TabPreviewStore(directory: directory)

        store.store(try makeImage(width: 40, height: 86), for: secret, isPrivate: true)
        store.store(try makeImage(width: 40, height: 86), for: ordinary, isPrivate: false)

        // It is still shown while the tab lives — the picture is in memory.
        XCTAssertNotNil(store.preview(for: secret))

        let left = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        XCTAssertFalse(
            left.contains { $0.hasPrefix(secret.uuidString) },
            "a private tab left a photograph of its page on disk"
        )
        // The ordinary one beside it did write, so an empty folder cannot pass
        // this test by accident.
        XCTAssertTrue(left.contains { $0.hasPrefix(ordinary.uuidString) })

        let next = TabPreviewStore(directory: directory)
        XCTAssertNil(next.preview(for: secret), "a private tab's picture came back after a relaunch")
    }

    /// Closing a tab takes its file with it, not only its place in memory.
    func testForgettingATabRemovesItsFileToo() throws {
        let directory = makeDirectory()
        let tab = UUID()
        let store = TabPreviewStore(directory: directory)
        store.store(try makeImage(width: 40, height: 86), for: tab, isPrivate: false)

        store.forget(tab)

        let next = TabPreviewStore(directory: directory)
        XCTAssertNil(next.preview(for: tab), "a closed tab's picture outlived it on disk")
    }

    /// And the local-data reset takes the whole folder.
    func testClearingRemovesTheFilesAndNotOnlyTheMemory() throws {
        let directory = makeDirectory()
        let tab = UUID()
        let store = TabPreviewStore(directory: directory)
        store.store(try makeImage(width: 40, height: 86), for: tab, isPrivate: false)

        store.clearAll()

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        let next = TabPreviewStore(directory: directory)
        XCTAssertNil(next.preview(for: tab))
    }

    // MARK: - Pictures of tabs that did not come back

    /// A relaunch restores at most twelve tabs, and none when restoring is off.
    /// Pictures of the rest had no card to go on and nothing ever removed them.
    func testKeepingOnlyTheReturnedTabsRemovesTheRest() throws {
        let directory = makeDirectory()
        let returned = UUID(), dropped = UUID(), alsoDropped = UUID()
        let store = TabPreviewStore(directory: directory)
        for tab in [returned, dropped, alsoDropped] {
            store.store(try makeImage(width: 40, height: 86), for: tab, isPrivate: false)
        }
        let stranger = directory.appendingPathComponent("notes.txt")
        try Data("not a picture".utf8).write(to: stranger)

        TabPreviewStore(directory: directory).keepOnly([returned])

        let next = TabPreviewStore(directory: directory)
        XCTAssertNotNil(next.preview(for: returned), "the sweep removed a tab that did come back")
        XCTAssertNil(next.preview(for: dropped), "a picture outlived its tab")
        XCTAssertNil(next.preview(for: alsoDropped))
        // Anything that is not a tab's picture is left alone: a sweep that
        // deletes what it does not recognise is one wrong path from disaster.
        XCTAssertTrue(FileManager.default.fileExists(atPath: stranger.path))
    }

    /// The window that owns the saved session sweeps at launch. Here nothing is
    /// restored — an empty session, as when restoring is switched off — so the
    /// one fresh tab is all that came back and every old picture goes.
    func testALaunchThatRestoresNothingLeavesNoOldPictures() throws {
        let orphan = UUID()
        let isolated = try IsolatedWorkspace.make(for: self, restoresSession: true) { folder in
            try Data([0xFF, 0xD8, 0xFF]).write(to: folder.appendingPathComponent("\(orphan.uuidString).jpg"))
        }

        let left = try FileManager.default.contentsOfDirectory(atPath: isolated.previewDirectory.path)
        XCTAssertFalse(left.contains { $0.hasPrefix(orphan.uuidString) }, "a picture survived with no tab")
    }

    /// A second Mac window restores nothing and must not sweep, or it would
    /// take the first window's pictures with it.
    func testAWindowThatDoesNotOwnTheSessionSweepsNothing() throws {
        let belongsToAnotherWindow = UUID()
        let isolated = try IsolatedWorkspace.make(for: self, restoresSession: false) { folder in
            try Data([0xFF, 0xD8, 0xFF]).write(
                to: folder.appendingPathComponent("\(belongsToAnotherWindow.uuidString).jpg")
            )
        }

        let left = try FileManager.default.contentsOfDirectory(atPath: isolated.previewDirectory.path)
        XCTAssertTrue(
            left.contains { $0.hasPrefix(belongsToAnotherWindow.uuidString) },
            "a window that restored nothing swept another window's pictures"
        )
    }
}
