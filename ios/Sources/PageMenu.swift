import LimeghostShared
import SwiftUI

/// Everything the page menu offers, in the order it shows them: the two large
/// buttons, then the two cards.
enum PageMenuItem: CaseIterable, Hashable {
    case reader, copyForAI
    case reload, forward, newTab, newPrivateTab
    case bookmark, find, share, desktopSite
}

/// What the menu shows, apart from how it draws, so a test can read it without
/// standing up SwiftUI — as `BottomBarTests` read `BottomBarModel`.
struct PageMenuModel: Equatable {
    /// A web page is open in the tab in front: not the AI guide, not an empty tab.
    var hasPage: Bool
    var canGoForward: Bool
    var isBookmarked: Bool
    var prefersDesktopSite: Bool
    var isReaderOpen: Bool

    func isEnabled(_ item: PageMenuItem) -> Bool {
        switch item {
        case .newTab, .newPrivateTab:
            return true
        case .forward:
            return canGoForward
        case .find:
            // Find searches the page, and Reader covers it: a match would be
            // highlighted where nobody can see it.
            return hasPage && !isReaderOpen
        case .reader, .copyForAI, .reload, .bookmark, .share, .desktopSite:
            return hasPage
        }
    }

    /// Title case, as Apple's guidelines give menu items, and the Mac's own
    /// menu names where it has one. The three that change say what a tap will
    /// do next.
    func title(_ item: PageMenuItem) -> String {
        switch item {
        case .reader: return isReaderOpen ? "Close Reader" : "Reader"
        case .copyForAI: return "Copy for AI"
        case .reload: return "Reload"
        case .forward: return "Forward"
        case .newTab: return "New Tab"
        case .newPrivateTab: return "New Private Tab"
        case .bookmark: return isBookmarked ? "Remove Bookmark" : "Add Bookmark"
        case .find: return "Find in Page"
        case .share: return "Share"
        case .desktopSite: return prefersDesktopSite ? "Request Mobile Site" : "Request Desktop Site"
        }
    }

    /// System symbols. Reader's is the one the Mac's Reader header uses, and
    /// New Private Tab's is the tab switcher's Private section's.
    func symbol(_ item: PageMenuItem) -> String {
        switch item {
        case .reader: return "doc.plaintext"
        case .copyForAI: return "doc.on.doc"
        case .reload: return "arrow.clockwise"
        case .forward: return "chevron.forward"
        case .newTab: return "plus.square.on.square"
        case .newPrivateTab: return "eye.slash"
        case .bookmark: return isBookmarked ? "star.fill" : "star"
        case .find: return "magnifyingglass"
        case .share: return "square.and.arrow.up"
        case .desktopSite: return prefersDesktopSite ? "iphone" : "desktopcomputer"
        }
    }
}

extension PageMenuModel {
    /// The menu as the tab in front stands now. SwiftUI rebuilds it whenever
    /// the workspace changes, and every row closes the sheet, so it never has
    /// to follow a change of its own.
    @MainActor
    init(workspace: BrowserWorkspace) {
        let tab = workspace.selectedTab
        self.init(
            hasPage: workspace.canShareSelectedPage,
            canGoForward: workspace.canGoForwardInSelectedTab,
            isBookmarked: tab.map { workspace.dataStore.isBookmarked($0.session.currentURLString) } ?? false,
            prefersDesktopSite: tab?.session.prefersDesktopSite ?? false,
            isReaderOpen: tab?.readerArticle != nil
        )
    }
}

/// What each row does, as named methods rather than closures in the view, so
/// a test can call them. An inline closure is invisible to tests, which is the
/// lesson `StartSurfaceScreen.openTool` recorded.
@MainActor
struct PageMenuActions {
    let workspace: BrowserWorkspace

    func perform(_ item: PageMenuItem) async {
        switch item {
        case .reader: await workspace.toggleReaderInSelectedTab()
        case .copyForAI: await copyForAI()
        case .reload: workspace.reloadSelectedTab()
        case .forward: workspace.goForwardInSelectedTab()
        case .newTab: workspace.addTab()
        case .newPrivateTab: workspace.addTab(isPrivate: true)
        case .bookmark: toggleBookmark()
        case .find: workspace.findInSelectedTab()
        case .share: workspace.shareSelectedPage()
        case .desktopSite: workspace.toggleDesktopSiteInSelectedTab()
        }
    }

    /// The menu closes as it copies, so the phone says what went onto the
    /// clipboard. A copy that did not happen has already said why, through
    /// `readCurrentPage`, and gets no confirmation on top.
    func copyForAI() async {
        guard let article = await workspace.copySelectedPageForAI() else { return }
        workspace.selectedTab?.session.showPageNotice(article.copyConfirmation)
    }

    /// The shared toggle says nothing, and the phone has no star to show the
    /// change, so the phone says it in words. It says only what actually
    /// changed, read from the store before and after: an address the store
    /// refuses changes nothing and is claimed as nothing.
    func toggleBookmark() {
        guard let tab = workspace.selectedTab else { return }
        let address = tab.session.currentURLString
        let wasSaved = workspace.dataStore.isBookmarked(address)
        workspace.toggleBookmarkForSelectedTab()
        let isSaved = workspace.dataStore.isBookmarked(address)
        guard isSaved != wasSaved else { return }
        tab.session.showPageNotice(isSaved ? "Bookmark added." : "Bookmark removed.")
    }
}
