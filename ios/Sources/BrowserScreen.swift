import SwiftUI
import LimeghostShared

/// The whole browser, one screen.
struct BrowserScreen: View {
    @ObservedObject var host: WorkspaceHost
    @State private var isPresentingAddressSheet = false
    @State private var isPresentingTabSwitcher = false
    @State private var menu = PageMenuPresentation()
    /// The page menu's measured height; see `PageMenu.height`. It starts near
    /// the real value, so the first opening hardly moves.
    @State private var menuHeight: CGFloat = 540

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let tab = host.workspace.selectedTab {
                    TabSurface(tab: tab, workspace: host.workspace)
                        .overlay(alignment: .bottom) { NoticeLayer(session: tab.session) }
                } else {
                    Color.clear
                }
            }

            if let tab = host.workspace.selectedTab {
                BottomChrome(find: tab.find, bar: bottomBar)
            } else {
                bottomBar
            }
        }
        .sheet(isPresented: $isPresentingAddressSheet) {
            AddressSheet(workspace: host.workspace) {
                isPresentingAddressSheet = false
            }
        }
        .sheet(isPresented: $isPresentingTabSwitcher) {
            TabSwitcher(workspace: host.workspace) {
                isPresentingTabSwitcher = false
            }
        }
        .sheet(isPresented: $menu.isPresented, onDismiss: runChosenMenuItem) {
            PageMenu(
                model: PageMenuModel(workspace: host.workspace),
                choose: { menu.choose($0) },
                height: $menuHeight
            )
            .presentationDetents([.height(menuHeight)])
            .presentationDragIndicator(.visible)
            .presentationBackground(LimeghostTheme.bg1)
        }
        .sheet(item: $menu.destination) { destination in
            switch destination {
            case .bookmarks:
                BookmarksSheet(workspace: host.workspace) { menu.destination = nil }
            case .history:
                HistorySheet(workspace: host.workspace) { menu.destination = nil }
            }
        }
        // Handed down once, as the Mac's `BrowserView` does, so every site icon
        // on the phone draws what a visit captured rather than its fallback
        // square: the guide's, and both lists'. The phone had never done this.
        .environment(\.faviconStore, host.workspace.favicons)
    }

    private var bottomBar: BottomBar {
        BottomBar(
            model: BottomBarModel(
                urlString: host.workspace.selectedTab?.session.currentURLString ?? "",
                tabCount: host.workspace.visibleTabs.count,
                canGoBack: host.workspace.canGoBackInSelectedTab
            ),
            goBack: { host.workspace.goBackInSelectedTab() },
            openAddress: { isPresentingAddressSheet = true },
            openTabs: { isPresentingTabSwitcher = true },
            openMenu: { menu.open() }
        )
    }

    /// Runs the row the menu closed for, now that the sheet has gone.
    private func runChosenMenuItem() {
        guard let item = menu.didDismiss() else { return }
        let actions = PageMenuActions(workspace: host.workspace)
        Task { await actions.perform(item) }
    }
}

/// Where a page notice goes. Over the page while the assistant is closed, as
/// always. While it is open, in its own strip above the bar: floating over the
/// assistant, the banner landed exactly on the provider's message box, the one
/// place a person taps to paste. It is never put under the provider's header,
/// where "Copied 812 words." could read as the provider having received them.
enum NoticePlacement: Equatable {
    case overThePage, aboveTheBar

    static func forAssistant(isOpen: Bool) -> NoticePlacement {
        isOpen ? .aboveTheBar : .overThePage
    }
}

/// What sits along the bottom: the find bar while finding, which needs the
/// keyboard; nothing while anything else is typed, as Safari's bar steps
/// aside, so a conversation keeps the room; the bar the rest of the time.
enum BottomChromeContent: Equatable {
    case findBar, bar, nothing

    static func showing(isFinding: Bool, keyboardIsUp: Bool) -> BottomChromeContent {
        if isFinding { return .findBar }
        return keyboardIsUp ? .nothing : .bar
    }
}

/// The bar along the bottom, or the find bar in its place while finding.
///
/// Its own view, so it can observe the tab's find controller. `BrowserScreen`
/// observes the workspace, and a tab's `find` changes without the workspace
/// hearing of it — the same reason `TabSurface` observes its tab and session.
struct BottomChrome: View {
    @ObservedObject var find: PageFindController
    let bar: BottomBar

    var body: some View {
        if find.isPresented {
            FindBar(find: find)
        } else {
            bar
        }
    }
}

/// Whether the guide belongs on screen, rather than the web view: only while
/// the tab is genuinely on its start page — not a page already loading or
/// loaded — and only when that start page is the AI home.
///
/// A free function, not an inline `if` in `TabSurface.body`, so a test can
/// call it directly and check both directions without standing up SwiftUI.
/// The inline form it replaces was invisible to every test: made unreachable
/// on purpose, the suite stayed green, so the whole branch could have been
/// deleted without anything noticing.
///
/// Both conditions are load-bearing on their own. `startSurface` is never reset
/// once a real page loads — iOS has no Home button, and its Bookmarks and
/// History are sheets rather than start surfaces, so nothing resets it — so
/// `loadState` has to be the deciding vote for `.content`/`.loading`: without
/// it, a tab opened straight to a URL (`AddressSheet`, a reopened tab, a tapped
/// guide card) would show the guide instead of the page just asked for, because
/// `startSurface` is still `.aiHome`. And `startSurface` still matters for
/// `.startPage`: the shared layer also loads its own HTML start page into every
/// fresh tab's web view, which is `.startPage` too, so this function is what
/// keeps that page from ever showing instead of, or underneath, the native
/// guide.
func showsGuide(loadState: BrowserLoadState, startSurface: StartSurface) -> Bool {
    loadState == .startPage && startSurface == .aiHome
}

/// The selected tab's own surface: the AI guide (Task 8) while `showsGuide`
/// says so, or the web view otherwise. This branch *replaces* `WebViewHost`
/// outright rather than layering the native guide over it — showing both at
/// once is exactly the bug `showsGuide` exists to prevent.
///
/// `@ObservedObject` on `tab` *and* `session`, not only on `host` above:
/// `startSurface` is published by the tab and `loadState` by the session,
/// and a tab does not forward every session change into its own
/// `objectWillChange` (only `BrowserWorkspace` does that, and only for the
/// tab's own published properties). Reading `host.workspace.selectedTab`
/// again here without observing the session directly would leave a card tap
/// showing the guide for one extra redraw, or none at all, after
/// `open(_:)` starts the load — the same reason the Mac's own
/// `BrowserTabContent` observes both rather than relying on the workspace
/// alone.
///
/// Internal rather than private so a test can build one around a real tab and
/// read `showsTheGuide`. `showsGuide` on its own only proves the rule; this
/// property is where the rule meets the two objects it judges, and reading
/// the wrong one of them — the tab's `loadState` does not exist, the
/// session's `startSurface` does not either — is a mistake no test of the
/// pure function could ever see.
struct TabSurface: View {
    @ObservedObject var tab: BrowserTab
    @ObservedObject var session: BrowserSession
    let workspace: BrowserWorkspace

    init(tab: BrowserTab, workspace: BrowserWorkspace) {
        self.tab = tab
        self.session = tab.session
        self.workspace = workspace
    }

    var showsTheGuide: Bool {
        showsGuide(loadState: session.loadState, startSurface: tab.startSurface)
    }

    /// Reader covers the page while an article is open. Never over the guide,
    /// which is not a page.
    var showsTheReader: Bool {
        !showsTheGuide && tab.readerArticle != nil
    }

    var body: some View {
        if showsTheGuide {
            StartSurfaceScreen(workspace: workspace)
        } else {
            WebViewHost(session: session)
                .id(session.instanceID)
                .ignoresSafeArea(edges: .bottom)
                // Over the page rather than instead of it: the web view stays
                // mounted, so closing Reader shows the page exactly as it was.
                .overlay {
                    if showsTheReader, let article = tab.readerArticle {
                        ReaderView(
                            article: article,
                            copy: { tab.copyArticleForAI(article) },
                            close: { tab.readerArticle = nil },
                            headerStyle: .touch
                        )
                        .transition(.opacity)
                    }
                }
        }
    }
}
