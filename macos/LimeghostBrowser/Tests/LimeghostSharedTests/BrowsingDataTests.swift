import CoreGraphics
import LimeghostCore
@testable import LimeghostShared
import Foundation
import WebKit
import XCTest

/// Clearing and listing browsing data acts on the store the pages in front of
/// the person actually use — this profile's, or a private tab's own — and on
/// nothing else. Every profile but the original has a WebKit store of its own
/// (`WKWebsiteDataStore(forIdentifier:)`), and code written before profiles
/// existed reached for `.default()`, which belongs to the original profile.
@MainActor
final class BrowsingDataTests: XCTestCase {
    /// A profile store that does not outlive the test. WebKit refuses to remove
    /// a store while anything still holds it, and lets go of it a moment after
    /// the last reference goes, so removal is retried rather than tried once.
    /// On the main actor: WebKit's store registry traps on any other thread.
    private func throwawayProfileStore() -> WKWebsiteDataStore {
        let identifier = UUID()
        addTeardownBlock { @MainActor in
            for _ in 0..<40 {
                let error: Error? = await withCheckedContinuation { continuation in
                    WKWebsiteDataStore.remove(forIdentifier: identifier) { continuation.resume(returning: $0) }
                }
                if error == nil { return }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        return WKWebsiteDataStore(forIdentifier: identifier)
    }

    private func cookie(named name: String, domain: String) throws -> HTTPCookie {
        try XCTUnwrap(HTTPCookie(properties: [
            .name: name,
            .value: "1",
            .domain: domain,
            .path: "/",
            .expires: Date().addingTimeInterval(3_600)
        ]))
    }

    // MARK: - The reset

    /// "Clear local browsing data" in a window of a second profile cleared the
    /// original profile's cookies and left its own untouched, then said the
    /// data had been cleared.
    func testTheResetClearsThisProfilesCookiesAndLeavesTheOriginalProfilesAlone() async throws {
        let profileStore = throwawayProfileStore()
        let workspace = try IsolatedWorkspace.make(for: self, websiteDataStore: profileStore).workspace
        let mine = try cookie(named: "limeghost-reset-mine", domain: "profile-b.example")
        let theirs = try cookie(named: "limeghost-reset-theirs", domain: "personal-profile.example")
        await profileStore.httpCookieStore.setCookie(mine)
        let original = WKWebsiteDataStore.default()
        await original.httpCookieStore.setCookie(theirs)
        addTeardownBlock { @MainActor in await original.httpCookieStore.deleteCookie(theirs) }

        await workspace.resetLocalBrowsingData()

        let leftInThisProfile = await profileStore.httpCookieStore.allCookies()
        XCTAssertFalse(leftInThisProfile.contains { $0.name == mine.name }, "the reset left this profile's cookies")
        let leftInOriginal = await original.httpCookieStore.allCookies()
        XCTAssertTrue(leftInOriginal.contains { $0.name == theirs.name }, "the reset wiped another profile's cookies")
    }

    /// What each tab looked like is browsing evidence too. These pictures are
    /// never written to disk, but the reset is also what somebody presses to
    /// clear the screen behind them, and a switcher still holding photographs
    /// of the pages they just erased would not be cleared.
    func testTheResetErasesWhatEachTabLookedLike() async throws {
        let workspace = try IsolatedWorkspace.make(for: self).workspace
        let tab = try XCTUnwrap(workspace.selectedTab?.id)
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        workspace.tabPreviews.store(try XCTUnwrap(context.makeImage()), for: tab, isPrivate: false)
        XCTAssertNotNil(workspace.tabPreviews.preview(for: tab), "nothing was stored to erase")

        await workspace.resetLocalBrowsingData()

        XCTAssertNil(workspace.tabPreviews.preview(for: tab), "a page picture survived the reset")
    }

    /// Recently closed tabs are sites visited before the reset. They survived
    /// it, so "Reopen closed tab" could bring back a page the person had just
    /// asked to forget.
    func testTheResetForgetsRecentlyClosedTabs() async throws {
        let workspace = try IsolatedWorkspace.make(for: self).workspace
        workspace.addTab(url: URL(string: "https://example.com/")!)
        let closing = try XCTUnwrap(workspace.selectedTabID)
        workspace.closeTab(closing)
        XCTAssertTrue(workspace.canReopenClosedTab, "a closed tab has to be remembered first")

        await workspace.resetLocalBrowsingData()

        XCTAssertFalse(workspace.canReopenClosedTab, "a tab closed before the reset could still be reopened")
    }

    /// Bookmarks are what somebody chose to keep, not a trace of where they
    /// went, and Safari's and Chrome's equivalents of this reset keep them.
    /// Limeghost's took them, folders and all, until the founder decided on
    /// September 29, 2026 that it should not: somebody coming from either
    /// would press it to forget their browsing and lose what they had saved.
    func testTheResetKeepsBookmarksAndTheirFolders() async throws {
        let workspace = try IsolatedWorkspace.make(for: self).workspace
        let store = workspace.dataStore
        let recipes = try XCTUnwrap(store.createBookmarkFolder(title: "Recipes", iconID: "folder", parentID: nil))
        XCTAssertNotNil(store.addBookmark(title: "Soup", url: "https://example.com/soup", folderID: recipes.id))
        XCTAssertNotNil(store.addBookmark(title: "Bread", url: "https://example.com/bread", folderID: nil))
        store.recordVisit(title: "Soup", url: "https://example.com/soup")

        await workspace.resetLocalBrowsingData()

        XCTAssertEqual(Set(store.bookmarks.map(\.title)), ["Soup", "Bread"], "the reset took bookmarks")
        XCTAssertEqual(store.bookmarkFolders.map(\.title), ["Recipes"], "the reset took a folder")
        XCTAssertEqual(store.bookmarks(in: recipes.id).map(\.title), ["Soup"], "a bookmark left its folder")
        XCTAssertTrue(store.history.isEmpty, "history is still what the reset is for")
    }

    /// A kept bookmark keeps its icon, as a bookmark does through Chrome's
    /// clearing. Erasing it too left every kept bookmark a colour square
    /// until its site was visited again. Every other icon still goes.
    func testTheResetKeepsTheIconsOfBookmarkedSites() async throws {
        let isolated = try IsolatedWorkspace.make(for: self)
        let workspace = isolated.workspace
        XCTAssertNotNil(workspace.dataStore.addBookmark(title: "Soup", url: "https://example.com/soup", folderID: nil))
        let png = try XCTUnwrap(FaviconStore.pngData(from: try Self.onePixel()))
        try FileManager.default.createDirectory(at: isolated.iconDirectory, withIntermediateDirectories: true)
        try png.write(to: isolated.iconDirectory.appendingPathComponent("example.com.png"))
        try png.write(to: isolated.iconDirectory.appendingPathComponent("elsewhere.example.png"))

        await workspace.resetLocalBrowsingData()

        XCTAssertNotNil(workspace.favicons.icon(forHost: "example.com"), "a bookmarked site lost its icon")
        XCTAssertNil(workspace.favicons.icon(forHost: "elsewhere.example"), "the icon of a site only visited survived")
    }

    private static func onePixel() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0.2, green: 0.8, blue: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return try XCTUnwrap(context.makeImage())
    }

    /// The reset signed the person out of their assistant — it shares the
    /// tabs' website data — but left the conversation that was already loaded
    /// on screen until the panel was closed.
    func testTheResetClosesTheAssistantAndForgetsItsConversations() async throws {
        let workspace = try IsolatedWorkspace.make(for: self).workspace
        workspace.aiCompanion.toggle()
        XCTAssertTrue(workspace.aiCompanion.isVisible)
        XCTAssertFalse(workspace.aiCompanion.live.isEmpty, "opening the assistant has to load a conversation first")

        await workspace.resetLocalBrowsingData()

        XCTAssertFalse(workspace.aiCompanion.isVisible, "the assistant stayed open over a reset")
        XCTAssertTrue(workspace.aiCompanion.live.isEmpty, "a conversation stayed loaded after the reset")
        // And it is usable again at once, on the assistant the person chose.
        workspace.aiCompanion.toggle()
        XCTAssertTrue(workspace.aiCompanion.isVisible)
    }

    // MARK: - Listing a site's data

    /// The address bar's site panel lists and removes what a site stored. In a
    /// private tab it read the person's *saved* cookies for that site, and its
    /// Remove button deleted them — from inside a private window.
    func testAPrivateTabsSiteDataIsItsOwnEphemeralStore() throws {
        let workspace = try IsolatedWorkspace.make(for: self, isPrivate: true).workspace
        let session = try XCTUnwrap(workspace.selectedTab?.session)

        let inventory = SiteDataInventory(for: session)

        XCTAssertFalse(inventory.dataStore.isPersistent, "a private tab's site panel reads saved data")
        XCTAssertTrue(inventory.dataStore === session.webView.configuration.websiteDataStore)
    }

    /// In a second profile's window the panel read, and removed from, the
    /// original profile's store.
    func testAProfilesSiteDataIsThatProfilesStore() throws {
        let profileStore = throwawayProfileStore()
        let workspace = try IsolatedWorkspace.make(for: self, websiteDataStore: profileStore).workspace
        let session = try XCTUnwrap(workspace.selectedTab?.session)

        XCTAssertTrue(SiteDataInventory(for: session).dataStore === profileStore)
    }

    // MARK: - Switches that belong to a profile

    /// "Save browsing history" was bound to the app's standard preferences,
    /// while each profile's store reads its own suite — so in every profile but
    /// the original, switching history off changed nothing and visits went on
    /// being recorded. The switch is the store's, like the start-up choice.
    func testTurningHistoryOffInAProfileStopsThatProfileRecording() throws {
        let isolated = try IsolatedWorkspace.make(for: self)
        let store = isolated.workspace.dataStore

        store.savesHistory = false
        store.recordVisit(title: "Not kept", url: "https://not-kept.example/")

        XCTAssertTrue(store.history.isEmpty, "a visit was recorded with history switched off")
        XCTAssertFalse(isolated.defaults.bool(forKey: "clearframe.saveHistory"), "not written where this profile reads it")
        store.savesHistory = true
        XCTAssertTrue(isolated.defaults.bool(forKey: "clearframe.saveHistory"))
    }

    /// The same for loading every restored tab at start.
    func testLoadingEveryRestoredTabIsAProfilesOwnChoice() throws {
        let isolated = try IsolatedWorkspace.make(for: self)
        let store = isolated.workspace.dataStore
        XCTAssertFalse(store.reloadsRestoredTabs)

        store.reloadsRestoredTabs = true

        XCTAssertTrue(isolated.defaults.bool(forKey: "clearframe.reloadRestoredTabs"))
        XCTAssertTrue(BrowserDataStore(defaults: isolated.defaults).reloadsRestoredTabs)
    }

    // MARK: - Placeholder names are not titles

    /// The star and the phone's Add Bookmark go through `toggleBookmark`,
    /// which saved whatever the tab was called at that moment — "Loading…" or
    /// "Opening ChatGPT…" for a page not yet arrived — where `addBookmark`
    /// already refused both.
    func testAPageStarredWhileItLoadsIsNotSavedUnderAPlaceholder() throws {
        let store = try IsolatedWorkspace.make(for: self).workspace.dataStore

        store.toggleBookmark(title: "Loading…", url: "https://starred.example/page")
        store.toggleBookmark(title: "Opening ChatGPT…", url: "https://chatgpt.com/")

        XCTAssertEqual(store.bookmark(for: "https://starred.example/page")?.title, "starred.example")
        XCTAssertEqual(store.bookmark(for: "https://chatgpt.com/")?.title, "chatgpt.com")
    }

    /// Unstarring is a deletion, and leaves nothing behind in the backup either.
    func testAnUnstarredBookmarkIsNotKeptInTheBackup() throws {
        let isolated = try IsolatedWorkspace.make(for: self)
        let store = isolated.workspace.dataStore
        store.toggleBookmark(title: "Kept", url: "https://kept.example/")
        store.toggleBookmark(title: "Gone", url: "https://gone.example/")

        store.toggleBookmark(title: "Gone", url: "https://gone.example/")

        let backup = isolated.defaults.data(forKey: "clearframe.bookmarks.v1.lastKnownGood")
        let kept = try backup.map { try JSONDecoder().decode([BookmarkRecord].self, from: $0) } ?? []
        XCTAssertFalse(kept.contains { $0.url == "https://gone.example/" }, "the unstarred bookmark is still on disk")
    }

    // MARK: - What a deletion leaves on disk

    /// Every save first copies the previous value into a last-known-good
    /// backup. After deleting a visit, that backup still held it, on disk,
    /// until the next unrelated write.
    func testAVisitDeletedFromHistoryIsNotKeptInTheBackup() throws {
        let isolated = try IsolatedWorkspace.make(for: self)
        let store = isolated.workspace.dataStore
        let now = Date()
        store.recordVisit(title: "Kept", url: "https://kept.example/", at: now)
        store.recordVisit(title: "Private matter", url: "https://secret.example/", at: now.addingTimeInterval(60))
        let secret = try XCTUnwrap(store.history.first { $0.url == "https://secret.example/" })

        store.removeHistory(secret)

        let backup = isolated.defaults.data(forKey: "clearframe.history.v1.lastKnownGood")
        let kept = try backup.map { try JSONDecoder().decode([HistoryRecord].self, from: $0) } ?? []
        XCTAssertFalse(kept.contains { $0.url == "https://secret.example/" }, "the deleted visit is still on disk")
        XCTAssertTrue(store.history.contains { $0.url == "https://kept.example/" })
    }

    /// The same for a bookmark somebody removed.
    func testARemovedBookmarkIsNotKeptInTheBackup() throws {
        let isolated = try IsolatedWorkspace.make(for: self)
        let store = isolated.workspace.dataStore
        _ = store.addBookmark(title: "Kept", url: "https://kept.example/", folderID: nil)
        let removed = try XCTUnwrap(store.addBookmark(title: "Gone", url: "https://gone.example/", folderID: nil))

        store.removeBookmark(removed)

        let backup = isolated.defaults.data(forKey: "clearframe.bookmarks.v1.lastKnownGood")
        let kept = try backup.map { try JSONDecoder().decode([BookmarkRecord].self, from: $0) } ?? []
        XCTAssertFalse(kept.contains { $0.url == "https://gone.example/" }, "the removed bookmark is still on disk")
    }
}
