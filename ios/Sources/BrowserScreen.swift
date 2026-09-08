import SwiftUI
import LimeghostShared

/// The whole browser, one screen.
struct BrowserScreen: View {
    @ObservedObject var host: WorkspaceHost
    @State private var isPresentingAddressSheet = false
    @State private var isPresentingTabSwitcher = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let tab = host.workspace.selectedTab {
                    TabSurface(tab: tab, workspace: host.workspace)
                } else {
                    Color.clear
                }
            }

            BottomBar(
                model: BottomBarModel(
                    urlString: host.workspace.selectedTab?.session.currentURLString ?? "",
                    tabCount: host.workspace.visibleTabs.count,
                    canGoBack: host.workspace.canGoBackInSelectedTab
                ),
                goBack: { host.workspace.goBackInSelectedTab() },
                openAddress: { isPresentingAddressSheet = true },
                openTabs: { isPresentingTabSwitcher = true }
            )
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
/// Both conditions are load-bearing on their own. `startSurface` is never
/// reset once a real page loads — iOS has no Home button and no bookmarks or
/// history home yet to reset it — so `loadState` has to be the deciding vote
/// for `.content`/`.loading`: without it, a tab opened straight to a URL
/// (`AddressSheet`, a reopened tab, a tapped guide card) would show the
/// guide instead of the page just asked for, because `startSurface` is still
/// `.aiHome`. And `startSurface` still matters for `.startPage`: the shared
/// layer also loads its own HTML start page into every fresh tab's web view,
/// which is `.startPage` too, so this function is what keeps that page from
/// ever showing instead of, or underneath, the native guide.
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

    var body: some View {
        if showsTheGuide {
            StartSurfaceScreen(workspace: workspace)
        } else {
            WebViewHost(session: session)
                .id(session.instanceID)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}
