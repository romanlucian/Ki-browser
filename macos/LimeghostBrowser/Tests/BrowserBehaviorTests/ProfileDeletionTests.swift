import AppKit
import LimeghostCore
@testable import LimeghostShared
import XCTest
@preconcurrency import WebKit
@testable import LimeghostBrowser

/// Deleting a profile promises "there is no undo": its bookmarks, history,
/// site icons, picture and signed-in sessions are gone from this Mac. Two
/// parts of that did not happen.
@MainActor
final class ProfileDeletionTests: XCTestCase {
    private func ledger() throws -> UserDefaults {
        let name = "clearframe.profileErasure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    /// The picture lives beside the profile's site icons, and only the icons
    /// were removed: the photograph stayed on disk after the profile was gone.
    func testDeletingAProfileRemovesItsPicture() throws {
        let store = ProfileStore(defaults: try ledger())
        let work = store.addProfile(name: "Work")
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("limeghost-erase-\(UUID().uuidString).png")
        let square = NSImage(size: CGSize(width: 64, height: 64))
        square.lockFocus()
        NSColor.systemPink.drawSwatch(in: CGRect(x: 0, y: 0, width: 64, height: 64))
        square.unlockFocus()
        try XCTUnwrap(ProfileStore.squareAvatarPNG(from: square, side: 64)).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        XCTAssertTrue(store.setPicture(from: source, for: work.id))
        let folder = try XCTUnwrap(ProfileStorage.profileDirectory(for: work.id))
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))

        store.deleteProfile(work.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), "the profile's picture is still on disk")
    }

    /// WebKit refuses to remove a store anything still uses, and the profile
    /// being deleted is still in use: its windows are closing. The refusal was
    /// ignored, so the deleted profile's cookies and logins stayed on disk.
    /// Now it is recorded, retried, and finished at the next launch.
    func testAStoreStillInUseIsFinishedOffAfterward() async throws {
        let ledger = try ledger()
        let id = UUID()
        var store: WKWebsiteDataStore? = WKWebsiteDataStore(forIdentifier: id)
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .name: "signed-in", .value: "1", .domain: "work.example", .path: "/",
            .expires: Date().addingTimeInterval(3_600)
        ]))
        await store?.httpCookieStore.setCookie(cookie)
        let before = await Self.storeIdentifiers()
        XCTAssertTrue(before.contains(id), "the store was never created")

        ProfileStorage.erase(profileID: id, ledger: ledger)

        XCTAssertTrue(
            ProfileStorage.profilesAwaitingErasure(in: ledger).contains(id),
            "a store WebKit would not remove yet was forgotten"
        )

        // The person's windows close; the next launch finishes the job.
        store = nil
        ProfileStorage.finishErasures(ledger: ledger)
        var removed = false
        for _ in 0..<100 where !removed {
            try await Task.sleep(nanoseconds: 200_000_000)
            let remaining = await Self.storeIdentifiers()
            removed = !remaining.contains(id) && !ProfileStorage.profilesAwaitingErasure(in: ledger).contains(id)
        }
        XCTAssertTrue(removed, "the deleted profile's logins are still on disk")
    }

    private static func storeIdentifiers() async -> [UUID] {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.fetchAllDataStoreIdentifiers { continuation.resume(returning: $0) }
        }
    }
}
