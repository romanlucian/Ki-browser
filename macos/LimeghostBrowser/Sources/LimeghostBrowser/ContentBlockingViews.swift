import LimeghostCore
import SwiftUI

/// What the shield control shows, derived purely from the provider's compile
/// status and whether the current site has a per-site exception. Kept free of
/// SwiftUI/WebKit types so the mapping is unit-testable on its own.
enum ShieldState: Equatable {
    case activeForSite
    /// The rule list is still compiling, so it is not attached to any page yet
    /// and nothing is being blocked. Kept separate from `.activeForSite`
    /// because the shield must never state protection the app is not applying.
    case preparing
    case disabledForSite
    case disabledGlobally
    case unavailable

    static func make(status: ContentBlockingStatus, hostDisabled: Bool) -> ShieldState {
        switch status {
        case .compiling:
            // A site the user switched off stays off either way; otherwise the
            // honest answer during a compile is "not yet", not "on".
            return hostDisabled ? .disabledForSite : .preparing
        case .active:
            return hostDisabled ? .disabledForSite : .activeForSite
        case .disabled:
            return .disabledGlobally
        case .unavailable:
            return .unavailable
        }
    }

    var statusLine: String {
        switch self {
        case .activeForSite: return "On for this site"
        case .preparing: return "Not blocking yet"
        case .disabledForSite: return "Off for this site"
        case .disabledGlobally: return "Off in Settings"
        case .unavailable: return "Filter unavailable"
        }
    }

    /// The short form for the site information popover's disclosure row. Same
    /// fact as `statusLine`, fewer words — never a different one.
    var badge: String {
        switch self {
        case .activeForSite: return "On"
        case .preparing: return "Not yet"
        case .disabledForSite: return "Off"
        case .disabledGlobally: return "Off in Settings"
        case .unavailable: return "Unavailable"
        }
    }

    var symbolName: String {
        self == .activeForSite ? "shield" : "shield.slash"
    }
}

/// The whole per-site tracker-blocking control: what state blocking is in, why,
/// and the switch for this one site.
///
/// It carries no header of its own. The address bar's site information popover
/// is its only home, and the disclosure row it opens under already names the
/// section and states it — a second heading underneath would say it twice.
/// A separate shield button in the address pill showed this same view until
/// September 1, 2026; it was removed because everything it said had become a
/// row in that popover, and because a shield in the address bar promises
/// protection where a lock only reports encryption.
struct ContentBlockingSiteControl: View {
    @ObservedObject var provider: ContentRuleListProvider
    @ObservedObject var session: BrowserSession
    let host: String?
    let shieldState: ShieldState

    private var hostDisabled: Bool {
        guard let host else { return false }
        return provider.settings.isDisabled(forHost: host)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            bodyText
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let host {
                Divider()
                Toggle(
                    "Block trackers on \(host)",
                    isOn: Binding(
                        get: { !hostDisabled },
                        set: { blockingOn in
                            Task { @MainActor in
                                await provider.setSiteDisabled(!blockingOn, forHost: host)
                                session.reload()
                            }
                        }
                    )
                )
                .disabled(shieldState == .disabledGlobally)

                if shieldState == .disabledGlobally {
                    Text("Tracker blocking is off in Settings. Turn it on there to manage this site.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var bodyText: some View {
        switch provider.status {
        case .compiling:
            Text(preparingBodyCopy)
        case .active:
            Text(activeBodyCopy)
        case .disabled:
            EmptyView()
        case .unavailable(let reason):
            Text("The blocking filter could not be loaded on this Mac, so no requests are being blocked. (\(reason))")
        }
    }

    /// The one window where blocking is switched on but not applied. Say so:
    /// a page opened right now is not being filtered.
    private var preparingBodyCopy: String {
        "Limeghost is still preparing its tracker filter, so nothing is being blocked on this page yet. It applies to pages you open once it is ready — reload this page then to filter it too."
    }

    /// Pre-approved copy — keep this exact. It is the one place the app
    /// explains why no block count is ever shown.
    private var activeBodyCopy: String {
        let release = provider.blockList.release
        let date = release.lastChecked.formatted(.dateTime.month(.abbreviated).day().year())
        return "Limeghost blocks third-party requests to the \(provider.ruleCount) advertising and tracking domains on its bundled list (v\(release.version), checked \(date)). This is a curated starter list, not a complete ad blocker. WebKit applies the rules inside the page process, so Limeghost cannot see or count what was blocked — no per-page numbers exist. Blocking reduces some tracking requests; it is not a privacy guarantee or a judgment about this site."
    }
}
