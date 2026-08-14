import ClearframeCore
import SwiftUI

/// What the shield control shows, derived purely from the provider's compile
/// status and whether the current site has a per-site exception. Kept free of
/// SwiftUI/WebKit types so the mapping is unit-testable on its own.
enum ShieldState: Equatable {
    case activeForSite
    case disabledForSite
    case disabledGlobally
    case unavailable

    static func make(status: ContentBlockingStatus, hostDisabled: Bool) -> ShieldState {
        switch status {
        case .compiling, .active:
            // Blocking is configured on whenever status reaches this branch;
            // a brief compile in flight does not change what the shield says.
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
        case .disabledForSite: return "Off for this site"
        case .disabledGlobally: return "Off in Settings"
        case .unavailable: return "Filter unavailable"
        }
    }

    var symbolName: String {
        self == .activeForSite ? "shield" : "shield.slash"
    }
}

/// The address-pill tracker-blocking control. WebKit applies the compiled
/// rules inside the page process, so this button and its popover can only
/// ever state the current configuration — never a count of what was blocked.
struct ContentBlockingShieldButton: View {
    @ObservedObject var provider: ContentRuleListProvider
    @ObservedObject var session: BrowserSession
    @State private var showsPopover = false

    private var host: String? {
        ContentBlockingSettingsStore.normalizedHost(from: session.currentURLString)
    }

    private var shieldState: ShieldState {
        let hostDisabled = host.map { provider.settings.isDisabled(forHost: $0) } ?? false
        return ShieldState.make(status: provider.status, hostDisabled: hostDisabled)
    }

    var body: some View {
        Button {
            showsPopover = true
        } label: {
            Image(systemName: shieldState.symbolName)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(shieldState == .activeForSite ? Color.green : Color.secondary)
        .help("Tracker blocking: \(shieldState.statusLine)")
        .accessibilityLabel("Tracker blocking: \(shieldState.statusLine)")
        .accessibilityHint("Shows tracker blocking status and this site's controls.")
        .popover(isPresented: $showsPopover, arrowEdge: .top) {
            ContentBlockingPopover(provider: provider, session: session, host: host, shieldState: shieldState)
        }
    }
}

private struct ContentBlockingPopover: View {
    @ObservedObject var provider: ContentRuleListProvider
    @ObservedObject var session: BrowserSession
    let host: String?
    let shieldState: ShieldState

    private var hostDisabled: Bool {
        guard let host else { return false }
        return provider.settings.isDisabled(forHost: host)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tracker blocking", systemImage: shieldState.symbolName)
                .font(.headline)

            Text(shieldState.statusLine)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(shieldState == .activeForSite ? Color.green : Color.secondary)

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
        .padding(16)
        .frame(width: 320)
    }

    @ViewBuilder
    private var bodyText: some View {
        switch provider.status {
        case .compiling, .active:
            Text(activeBodyCopy)
        case .disabled:
            EmptyView()
        case .unavailable(let reason):
            Text("The blocking filter could not be loaded on this Mac, so no requests are being blocked. (\(reason))")
        }
    }

    /// Pre-approved copy — keep this exact. It is the one place the app
    /// explains why no block count is ever shown.
    private var activeBodyCopy: String {
        let release = provider.blockList.release
        let date = release.lastChecked.formatted(.dateTime.month(.abbreviated).day().year())
        return "Clearframe blocks third-party requests to the \(provider.ruleCount) advertising and tracking domains on its bundled list (v\(release.version), checked \(date)). This is a curated starter list, not a complete ad blocker. WebKit applies the rules inside the page process, so Clearframe cannot see or count what was blocked — no per-page numbers exist. Blocking reduces some tracking requests; it is not a privacy guarantee or a judgment about this site."
    }
}
