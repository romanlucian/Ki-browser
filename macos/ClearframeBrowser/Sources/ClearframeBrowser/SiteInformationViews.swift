import ClearframeCore
import SwiftUI

/// How the connection to the page in front of the reader actually stands.
///
/// The scheme alone is not the answer: an `https://` page that pulled part of
/// itself over `http://` is not fully encrypted, and a lock over it would be a
/// claim Clearframe cannot back. WebKit answers that second half with
/// `hasOnlySecureContent`, so both facts are used and the chip and the popover
/// read from the same value. Kept as a plain derivation, like `ShieldState`, so
/// it can be tested without a web view.
enum ConnectionSecurity: Equatable {
    /// A Clearframe surface, not a website.
    case noPage
    /// An HTTPS page that has not committed yet. Until it does,
    /// `hasOnlySecureContent` still describes the document being replaced, so
    /// there is nothing truthful to say about this one's subresources.
    case checking
    case secure
    case mixedContent
    case notSecure

    static func make(
        urlString: String,
        hasOnlySecureContent: Bool,
        hasCommittedNavigation: Bool
    ) -> ConnectionSecurity {
        guard let url = WebURLPolicy.validatedURL(urlString) else { return .noPage }
        guard url.scheme?.lowercased() == "https" else { return .notSecure }
        guard hasCommittedNavigation else { return .checking }
        return hasOnlySecureContent ? .secure : .mixedContent
    }

    var statusLine: String {
        switch self {
        case .noPage: return "No page loaded"
        case .checking: return "Connection is encrypted, still loading"
        case .secure: return "Connection is secure"
        case .mixedContent: return "Parts of this page were loaded over an unencrypted connection"
        case .notSecure: return "Connection is not secure"
        }
    }

    var detail: String {
        switch self {
        case .noPage:
            return "This tab is showing a Clearframe page, not a website."
        case .checking:
            return "This page is arriving over HTTPS. Clearframe can say whether every part of it came encrypted once it finishes loading."
        case .secure:
            return "This page reached you over an encrypted connection (HTTPS), and so did everything it loaded. That protects the connection, not the site: Clearframe does not judge who runs it or what it does with what you send."
        case .mixedContent:
            return "The page itself came over HTTPS, but some of what it loaded did not. Anything that arrives unencrypted can be read or changed on the way, so treat this page as you would a plain HTTP one."
        case .notSecure:
            return "This page was loaded over plain HTTP. What you type here — passwords included — can be read or changed by anyone on the network between you and the site."
        }
    }

    var symbolName: String {
        switch self {
        case .noPage: return "globe"
        case .checking: return "lock"
        case .secure: return "lock.fill"
        case .mixedContent: return "lock.trianglebadge.exclamationmark.fill"
        case .notSecure: return "lock.slash.fill"
        }
    }

    /// Semantic, not brand: green states encryption, orange states its absence.
    var tint: Color {
        switch self {
        case .secure: return .green
        case .mixedContent, .notSecure: return .orange
        case .noPage, .checking: return .secondary
        }
    }
}

/// The chip on the left of the address pill. It does two jobs: it drags this
/// page's link out to the bookmarks bar, and it opens site information for the
/// site the reader is on.
///
/// The drag is the older of the two and stays untouched — `.draggable` keeps
/// owning the press-and-move — while the click arrives through a
/// `simultaneousGesture`, which recognizes a tap without claiming the events a
/// drag needs.
struct SiteInformationChip: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var contentBlocking: ContentRuleListProvider
    @State private var showsPopover = false

    private var pageHost: String? {
        WebURLPolicy.validatedURL(session.currentURLString)?.host
    }

    @ViewBuilder
    var body: some View {
        if let url = BookmarkURLPolicy.validatedURL(session.currentURLString), let host = pageHost {
            symbol
                .frame(width: 20, height: 22)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 5))
                .contentShape(RoundedRectangle(cornerRadius: 5))
                .draggable(url) {
                    Label(session.pageTitle.isEmpty ? host : session.pageTitle, systemImage: "link")
                        .lineLimit(1)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                .simultaneousGesture(TapGesture().onEnded { showsPopover = true })
                .popover(isPresented: $showsPopover, arrowEdge: .top) {
                    SiteInformationPopover(
                        session: session,
                        contentBlocking: contentBlocking,
                        host: host,
                        dismiss: { showsPopover = false }
                    )
                }
                .help("Site information for \(host) — \(session.connectionSecurity.statusLine). Click to open it, or drag this chip to the bookmarks bar to save the page.")
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Site information for \(host)")
                .accessibilityValue(session.connectionSecurity.statusLine)
                .accessibilityHint("Opens connection, tracker-blocking, and stored-data controls for this site. Drag it to the bookmarks bar to save this page.")
                .accessibilityAction { showsPopover = true }
        } else {
            symbol
                .frame(width: 20, height: 22)
                .accessibilityHidden(true)
        }
    }

    private var symbol: some View {
        Image(systemName: session.connectionSecurity.symbolName)
            .foregroundStyle(session.connectionSecurity.tint)
            .font(.system(size: 11, weight: .semibold))
    }
}

/// Site information for the page in the address bar: who it is, how it got
/// here, what Clearframe is blocking on it, and what it has stored on this Mac.
///
/// Everything it says about storage is a list of kinds. WebKit's
/// `WKWebsiteDataRecord` carries a display name and a set of data types and
/// nothing else — no bytes, no cookie count — so a size or a tally here would
/// be invented, the same reason the tracker shield never shows a number.
private struct SiteInformationPopover: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var contentBlocking: ContentRuleListProvider
    let host: String
    let dismiss: () -> Void

    @StateObject private var siteData = SiteDataInventory()
    @State private var storedKinds: [SiteDataKind]?
    @State private var isConfirmingRemoval = false
    @State private var isRemoving = false

    private var blockingHost: String? {
        ContentBlockingSettingsStore.normalizedHost(from: session.currentURLString)
    }

    private var shieldState: ShieldState {
        let hostDisabled = blockingHost.map { contentBlocking.settings.isDisabled(forHost: $0) } ?? false
        return ShieldState.make(status: contentBlocking.status, hostDisabled: hostDisabled)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(host)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                    .truncationMode(.middle)

                connectionSection

                Divider()

                ContentBlockingSiteControl(
                    provider: contentBlocking,
                    session: session,
                    host: blockingHost,
                    shieldState: shieldState
                )

                Divider()

                siteDataSection
            }
            .padding(16)
            .frame(width: 340, alignment: .leading)
        }
        .frame(width: 340)
        .frame(maxHeight: 560)
        .task { await loadStoredKinds() }
    }

    private var connectionSection: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: session.connectionSecurity.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(session.connectionSecurity.tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.connectionSecurity.statusLine)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(session.connectionSecurity.tint)
                    .fixedSize(horizontal: false, vertical: true)
                Text(session.connectionSecurity.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var siteDataSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Cookies and site data", systemImage: "internaldrive")
                .font(.headline)

            if isRemoving {
                Text("Removing data stored by \(host)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let storedKinds {
                if storedKinds.isEmpty {
                    Text("This site has stored nothing on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(SiteDataKind.summary(of: storedKinds))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Checking what this site has stored…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isConfirmingRemoval {
                confirmation
            } else {
                Button("Remove this site’s data…", role: .destructive) {
                    isConfirmingRemoval = true
                }
                .disabled(isRemoving || storedKinds?.isEmpty != false)
            }

            Text(Self.limitCopy)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Confirmed inside the popover rather than in a separate dialog: naming the
    /// site next to the button that acts on it keeps the destructive step and
    /// its subject in one place, and nothing has to fight the popover for focus.
    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Remove the cookies and site data stored by \(host)?")
                .font(.caption.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("You will probably be signed out of this site, and it will reload. Your bookmarks, history, and downloaded files are not touched. This cannot be undone.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Remove site data", role: .destructive) {
                    Task { await removeSiteData() }
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel") { isConfirmingRemoval = false }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: ClearframeTheme.radius8))
    }

    /// The one place the popover explains the limit of what it can report. Kept
    /// verbatim: it is the same boundary the tracker shield states.
    private static let limitCopy = "Clearframe can see which kinds of data a site stored, not how much. WebKit reports no size and no number of cookies, so Clearframe never shows one. Data from private tabs is never listed here — it is discarded when the tab closes."

    private func loadStoredKinds() async {
        storedKinds = await siteData.kinds(forHost: host)
    }

    private func removeSiteData() async {
        isConfirmingRemoval = false
        isRemoving = true
        _ = await siteData.remove(forHost: host)
        isRemoving = false
        storedKinds = []
        session.reload()
        dismiss()
    }
}
