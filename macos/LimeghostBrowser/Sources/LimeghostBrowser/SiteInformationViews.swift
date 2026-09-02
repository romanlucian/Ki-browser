import LimeghostCore
import SwiftUI

/// How the connection to the page in front of the reader actually stands.
///
/// The scheme alone is not the answer: an `https://` page that pulled part of
/// itself over `http://` is not fully encrypted, and a lock over it would be a
/// claim Limeghost cannot back. WebKit answers that second half with
/// `hasOnlySecureContent`, so both facts are used and the chip and the popover
/// read from the same value. Kept as a plain derivation, like `ShieldState`, so
/// it can be tested without a web view.
enum ConnectionSecurity: Equatable {
    /// A Limeghost surface, not a website.
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

    /// The short form for the site information popover's disclosure row, where
    /// `statusLine` would wrap to three lines. The two must never disagree:
    /// this is the same fact with fewer words.
    var badge: String {
        switch self {
        case .noPage: return "No page"
        case .checking: return "Checking…"
        case .secure: return "Secure"
        case .mixedContent: return "Mixed content"
        case .notSecure: return "Not secure"
        }
    }

    var detail: String {
        switch self {
        case .noPage:
            return "This tab is showing a Limeghost page, not a website."
        case .checking:
            return "This page is arriving over HTTPS. Limeghost can say whether every part of it came encrypted once it finishes loading."
        case .secure:
            return "This page reached you over an encrypted connection (HTTPS), and so did everything it loaded. That protects the connection, not the site: Limeghost does not judge who runs it or what it does with what you send."
        case .mixedContent:
            return "The page itself came over HTTPS, but some of what it loaded did not. Anything that arrives unencrypted can be read or changed on the way, so treat this page as you would a plain HTTP one."
        case .notSecure:
            return "This page was loaded over plain HTTP. What you type here — passwords included — can be read or changed by anyone on the network between you and the site."
        }
    }

    /// The words the address bar spells out beside the glyph, or nil where the
    /// glyph alone is enough.
    ///
    /// Only the two states that describe missing encryption get words. A green
    /// lock needs none — the normal case should be quiet — and `checking` gets
    /// none because it lasts a fraction of a second and would flicker a warning
    /// onto pages that turn out to be fine.
    ///
    /// This exists because an orange slashed padlock is not readable by the
    /// people Limeghost is for. Chrome added the same words for the same
    /// reason. They state a fact about the transport and nothing about the
    /// site, which is the only thing Limeghost knows.
    var inlineWarning: String? {
        switch self {
        case .notSecure: return "Not secure"
        // Chrome flattens this into "Not secure" too. Limeghost keeps the
        // distinction it already documents: the page itself did arrive
        // encrypted, and saying otherwise would overstate what went wrong.
        case .mixedContent: return "Not fully secure"
        case .secure, .checking, .noPage: return nil
        }
    }

    /// The chrome set's own drawing for this state.
    ///
    /// The set carries locks so the address bar can speak in one hand; the SF
    /// Symbol it replaced was the last glyph in the toolbar that did not.
    var chromeIcon: ChromeIcon {
        switch self {
        case .noPage: return .globe
        case .checking: return .lock
        case .secure: return .lock
        case .mixedContent: return .lockWarning
        case .notSecure: return .lockSlash
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
            chipContent
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

    /// The mark on a page with nothing to report; the warning glyph and its
    /// words on one without full encryption.
    ///
    /// The owl is never damaged to signal a problem — it is replaced by one.
    /// A slashed or reddened brand mark would make Limeghost's own face the
    /// symbol of a bad page, and the mark has to survive being seen on the
    /// worst site somebody visits. Swapping it out costs the brand nothing and
    /// says far more than a broken owl could.
    ///
    /// Greyed while the page is still arriving, because until it commits
    /// WebKit is still describing the *previous* document, and a confident
    /// green mark over an answer that is not in yet is a claim Limeghost
    /// cannot make. Colour returns when the page does.
    private var chipContent: some View {
        let security = session.connectionSecurity
        let warning = security.inlineWarning
        return HStack(spacing: 4) {
            if warning == nil {
                BrandMark(size: 15)
                    .grayscale(security == .checking ? 1 : 0)
                    .opacity(security == .checking ? 0.55 : 1)
            } else {
                symbol
                Text(warning ?? "")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(security.tint)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, warning == nil ? 0 : 6)
        .frame(minWidth: 20, minHeight: 22)
    }

    /// What the connection is, in the toolbar's own hand.
    ///
    /// Only drawn where there is something to say — a secure page shows the
    /// mark instead, and the words beside this carry the meaning either way.
    private var symbol: some View {
        ChromeIconView(icon: session.connectionSecurity.chromeIcon, size: 14)
            .foregroundStyle(session.connectionSecurity.tint)
    }
}

/// Site information for the page in the address bar: who it is, how it got
/// here, what Limeghost is blocking on it, and what it has stored on this Mac.
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
    @State private var risk: RiskAssessment?
    @State private var isCheckingRisk = false
    @State private var isConfirmingRemoval = false
    @State private var isRemoving = false

    private var blockingHost: String? {
        ContentBlockingSettingsStore.normalizedHost(from: session.currentURLString)
    }

    private var shieldState: ShieldState {
        let hostDisabled = blockingHost.map { contentBlocking.settings.isDisabled(forHost: $0) } ?? false
        return ShieldState.make(status: contentBlocking.status, hostDisabled: hostDisabled)
    }

    /// Which section is showing its detail, if any. One at a time on purpose:
    /// an accordion is what guarantees the popover cannot grow back into the
    /// scrolling wall of text it replaced.
    @State private var openSection: SiteSection?

    @Environment(\.openSettings) private var openSettings

    private enum SiteSection: Hashable {
        case connection, blocking, risk, storage
    }

    private func toggle(_ section: SiteSection) {
        withAnimation(.easeOut(duration: 0.16)) {
            openSection = openSection == section ? nil : section
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                Text(host)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)

                connectionRow
                blockingRow
                riskRow
                storageRow

                Divider().padding(.vertical, 7)

                settingsRow
            }
            .padding(12)
            .frame(width: 340, alignment: .leading)
        }
        .frame(width: 340)
        .frame(maxHeight: 560)
        .background(LimeghostTheme.bg2)
        .task { await loadStoredKinds() }
    }

    private var connectionRow: some View {
        SiteSectionRow(
            symbol: session.connectionSecurity.symbolName,
            title: "Connection",
            badge: session.connectionSecurity.badge,
            badgeTint: session.connectionSecurity.tint,
            isOpen: openSection == .connection,
            toggle: { toggle(.connection) }
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.connectionSecurity.statusLine)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(session.connectionSecurity.tint)
                    .fixedSize(horizontal: false, vertical: true)
                Text(session.connectionSecurity.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// `ContentBlockingSiteControl` supplies the body; the row above is its
    /// header. This is the only place tracker blocking is reachable now that
    /// the address pill's separate shield button is gone.
    private var blockingRow: some View {
        SiteSectionRow(
            symbol: shieldState.symbolName,
            title: "Tracker blocking",
            badge: shieldState.badge,
            badgeTint: shieldState == .activeForSite ? .green : .secondary,
            isOpen: openSection == .blocking,
            toggle: { toggle(.blocking) }
        ) {
            ContentBlockingSiteControl(
                provider: contentBlocking,
                session: session,
                host: blockingHost,
                shieldState: shieldState
            )
        }
    }

    /// Risk signals live here rather than in a panel of their own: this popover
    /// is already where somebody looks when they are wondering about a page,
    /// beside the connection and what the site has stored.
    ///
    /// Behind a button, not automatic. Reading the page's text is something the
    /// person asks for; opening a popover is not asking, and neither is opening
    /// this row.
    private var riskRow: some View {
        SiteSectionRow(
            symbol: risk == nil ? "exclamationmark.shield" : "exclamationmark.shield.fill",
            title: "Risk signals",
            badge: riskBadge,
            badgeTint: riskTint,
            isOpen: openSection == .risk,
            toggle: { toggle(.risk) }
        ) {
            VStack(alignment: .leading, spacing: 9) {
                if let risk {
                    RiskCard(assessment: risk)
                } else if isCheckingRisk {
                    Text("Reading the visible page…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Limeghost can look for obvious signals in this page's visible text — an unencrypted password form, an encoded address, urgent payment or wallet-secret language. It explains what it found and never issues a verdict.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Check this page") {
                        Task { await checkRisk() }
                    }
                }
            }
        }
    }

    private var riskBadge: String {
        if let risk { return risk.level.rawValue }
        return isCheckingRisk ? "Checking…" : "Not checked"
    }

    private var riskTint: Color {
        guard let risk else { return .secondary }
        switch risk.level {
        case .low: return .green
        case .caution: return .orange
        case .high: return .red
        }
    }

    private func checkRisk() async {
        isCheckingRisk = true
        defer { isCheckingRisk = false }
        guard WebURLPolicy.validatedURL(session.currentURLString) != nil,
              let page = try? await session.extractPage() else { return }
        risk = RiskAnalyzer.assess(page: page)
    }

    private var storageRow: some View {
        SiteSectionRow(
            symbol: "internaldrive",
            title: "Cookies and site data",
            badge: storageBadge,
            badgeTint: .secondary,
            isOpen: openSection == .storage,
            toggle: { toggle(.storage) }
        ) {
            VStack(alignment: .leading, spacing: 9) {
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
    }

    /// A count of kinds, never of cookies or bytes: `WKWebsiteDataRecord`
    /// carries neither, so any number here beyond this one would be invented.
    private var storageBadge: String {
        if isRemoving { return "Removing…" }
        guard let storedKinds else { return "Checking…" }
        if storedKinds.isEmpty { return "None" }
        return "\(storedKinds.count) kind\(storedKinds.count == 1 ? "" : "s")"
    }

    /// Limeghost has no per-site settings page, so this says Settings and not
    /// "Site settings" — the window it opens is the app's, and applies to every
    /// site. The row is here because the per-site switches above are only half
    /// the story when blocking is off globally.
    private var settingsRow: some View {
        SiteActionRow(symbol: "gearshape", title: "Open Settings…") {
            dismiss()
            openSettings()
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
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: LimeghostTheme.radius8))
    }

    /// The one place the popover explains the limit of what it can report. Kept
    /// verbatim: it is the same boundary the tracker shield states.
    private static let limitCopy = "Limeghost can see which kinds of data a site stored, not how much. WebKit reports no size and no number of cookies, so Limeghost never shows one. Data from private tabs is never listed here — it is discarded when the tab closes."

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

struct RiskCard: View {
    let assessment: RiskAssessment

    private var tint: Color {
        switch assessment.level {
        case .low: return .green
        case .caution: return .orange
        case .high: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text("\(assessment.level.rawValue) risk signals").font(.callout.bold())
                Spacer()
                Text("\(assessment.score) / 100").font(.caption2).foregroundStyle(.secondary)
            }
            Text(
                assessment.signals.isEmpty
                    ? "No obvious high-risk signals were found in the visible page. That does not prove it is safe."
                    : "\(assessment.signals.count) visible signal\(assessment.signals.count == 1 ? "" : "s") worth checking. This is not a verdict."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            ForEach(assessment.signals) { signal in
                DisclosureGroup(signal.title) {
                    Text(signal.detail).font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                }
                .font(.caption.bold())
            }
        }
        .padding(14)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(tint.opacity(0.24)))
    }
}

/// One line of the site information popover: what the section is, the one word
/// for the state it is in, and a chevron that reveals the rest.
///
/// The popover said all of it at once until September 1, 2026 — four headings,
/// four paragraphs and four controls stacked 560 points tall, scrolling on any
/// window. Every word of that is still here. Only one section's worth of it is
/// on screen at a time, which is the whole change: the reader chooses what to
/// read instead of scrolling past what they did not ask for.
private struct SiteSectionRow<Content: View>: View {
    let symbol: String
    let title: String
    let badge: String
    let badgeTint: Color
    let isOpen: Bool
    let toggle: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 9) {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(badgeTint)
                        .frame(width: 16)
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Spacer(minLength: 8)
                    Text(badge)
                        .font(.caption)
                        .foregroundStyle(badgeTint)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: LimeghostTheme.radius8)
                    .fill(rowFill)
            )
            .onHover { isHovering = $0 }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title), \(badge)")
            .accessibilityHint(isOpen ? "Hides the details for this section." : "Shows the details for this section.")

            if isOpen {
                content()
                    .padding(.horizontal, 10)
                    .padding(.top, 9)
                    .padding(.bottom, 6)
            }
        }
    }

    private var rowFill: Color {
        if isOpen { return LimeghostTheme.itemHover }
        return isHovering ? LimeghostTheme.itemHover.opacity(0.6) : .clear
    }
}

/// A row that leaves rather than expands. Same metrics as `SiteSectionRow` so
/// the popover's last line sits on the same rhythm as the four above it.
private struct SiteActionRow: View {
    let symbol: String
    let title: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: LimeghostTheme.radius8)
                .fill(isHovering ? LimeghostTheme.itemHover : .clear)
        )
        .onHover { isHovering = $0 }
    }
}

/// The Limeghost mark, drawn from the artwork rather than redrawn in code so
/// the address bar and the app icon can never show two different owls.
///
/// The *small* mark on purpose: it is the face alone, drawn for 16–32 px, and
/// it is the only one of the three that survives this size. The full mark's
/// ring closes to a smear below 32 px and takes the face with it, which
/// `docs/brand/limeghost-mark-2026-08-31/README.md` records as measured rather
/// than assumed.
///
/// Falls back to nothing rather than to a placeholder: an address bar missing
/// its mark is a build mistake worth noticing, and a stand-in glyph sitting
/// where a security indicator belongs is worse than an empty space.
struct BrandMark: View {
    var size: CGFloat = 15

    private static let image: NSImage? = {
        guard let url = Bundle.module.url(forResource: "limeghost-mark-small", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()

    /// Whether the artwork is actually in the bundle. A missing resource draws
    /// nothing and raises no error, so the address bar would simply ship empty
    /// — this is what lets a test catch that before somebody sees it.
    static var isAvailable: Bool { image != nil }

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}
