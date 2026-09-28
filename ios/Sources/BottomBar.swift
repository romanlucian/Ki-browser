import LimeghostShared
import SwiftUI

/// What the bar shows, separate from how it draws, so a test can assert it
/// without standing up SwiftUI.
struct BottomBarModel {
    let urlString: String
    let tabCount: Int
    let canGoBack: Bool
    /// Lit while the assistant is open, as the Mac's toolbar button is.
    var isAssistantOpen: Bool = false

    /// What the button does next, for VoiceOver, as the menu's labels say.
    var assistantLabel: String { isAssistantOpen ? "Hide Assistant" : "Show Assistant" }

    /// The host, or an invitation.
    var addressLabel: String {
        guard let host = URL(string: urlString)?.host else {
            return urlString.isEmpty ? "Search or enter a website" : urlString
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// How much of the address pill's outline an arriving page covers: a sliver
/// the moment a load starts, the page's own progress after that, and nothing
/// once it is done. The phone showed nothing at all while a page loaded — a
/// tap on Go, then silence. The Mac draws its progress the same way, on the
/// pill's own outline (`BrowserView`), so the two agree.
enum AddressProgress {
    static func fraction(isLoading: Bool, estimated: Double) -> Double? {
        guard isLoading else { return nil }
        return min(1, max(0.02, estimated))
    }
}

/// The outline itself. Its own view so it can observe the session, whose
/// progress the workspace never hears about.
struct AddressProgressOutline: View {
    @ObservedObject var session: BrowserSession

    var body: some View {
        let fraction = AddressProgress.fraction(isLoading: session.isLoading, estimated: session.estimatedProgress)
        Capsule()
            .trim(from: 0, to: fraction ?? 1)
            .stroke(LimeghostTheme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .opacity(fraction == nil ? 0 : 1)
            .animation(.easeOut(duration: 0.22), value: session.estimatedProgress)
            .animation(.easeOut(duration: 0.35), value: session.isLoading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The assistant's mark: the word, in a speech bubble.
///
/// It was `bubble.left.and.bubble.right` — **two** bubbles, which is the
/// universal glyph for a conversation *between two people*: comments,
/// replies, Messages. Not vague, wrong. This button opens one person's own
/// ChatGPT, Claude, Gemini, Le Chat or Grok: one party, one machine. The
/// founder, who built it, could not read it, which is the whole of the
/// evidence needed.
///
/// The bubble stays because a conversation is what is behind the button, and
/// the word goes inside it because no drawing ever said *which kind* — the
/// same reason Copy for AI has no toolbar icon and lives in the menu with a
/// label, "where words can say what a glyph could not."
///
/// Two readable alternatives were rejected on purpose. A sparkle would be
/// read instantly and would say *this app is clever*: Limeghost holds no API
/// key and runs no model. Limeghost's own owl would be read instantly too
/// and would say Limeghost **is** the assistant; it is a door to somebody
/// else's, on the person's own account. A provider's own mark changes with
/// whoever was chosen and borrows their chrome besides.
struct AssistantMark: View {
    var body: some View {
        Text("AI")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            // The body of the bubble, then the same box again with room
            // underneath for the tail, so the letters sit centred in the
            // body rather than in the whole mark.
            .frame(width: 26, height: 18)
            .frame(width: 26, height: 23, alignment: .top)
            .overlay(SpeechBubble().stroke(style: StrokeStyle(lineWidth: 1.6, lineJoin: .round)))
    }
}

/// A rounded box with a tail hanging from its lower left.
///
/// One continuous path rather than a rounded rectangle plus a triangle:
/// stroking two overlapping shapes draws a line across the tail's mouth.
/// Quadratic curves rather than arcs at the corners because `addArc`'s
/// `clockwise` is measured in a coordinate space whose y runs the other way,
/// and at this size the curve is indistinguishable from the arc anyway.
private struct SpeechBubble: Shape {
    func path(in rect: CGRect) -> Path {
        let drop: CGFloat = 5
        let radius: CGFloat = 5
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - drop)
        let tailRight = body.minX + radius + 7
        let tailLeft = body.minX + radius + 1

        var path = Path()
        path.move(to: CGPoint(x: body.minX + radius, y: body.minY))
        path.addLine(to: CGPoint(x: body.maxX - radius, y: body.minY))
        path.addQuadCurve(
            to: CGPoint(x: body.maxX, y: body.minY + radius),
            control: CGPoint(x: body.maxX, y: body.minY)
        )
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: body.maxX - radius, y: body.maxY),
            control: CGPoint(x: body.maxX, y: body.maxY)
        )
        path.addLine(to: CGPoint(x: tailRight, y: body.maxY))
        path.addLine(to: CGPoint(x: tailLeft, y: rect.maxY))
        path.addLine(to: CGPoint(x: tailLeft, y: body.maxY))
        path.addLine(to: CGPoint(x: body.minX + radius, y: body.maxY))
        path.addQuadCurve(
            to: CGPoint(x: body.minX, y: body.maxY - radius),
            control: CGPoint(x: body.minX, y: body.maxY)
        )
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: body.minX + radius, y: body.minY),
            control: CGPoint(x: body.minX, y: body.minY)
        )
        path.closeSubpath()
        return path
    }
}

/// Back, the address, your assistant, the tabs and the page menu — within a
/// thumb's reach, along the bottom so the page's own top is left alone.
struct BottomBar: View {
    let model: BottomBarModel
    let goBack: () -> Void
    let openAddress: () -> Void
    let toggleAssistant: () -> Void
    let openTabs: () -> Void
    let openMenu: () -> Void
    /// The tab in front, whose loading the pill's outline follows.
    var session: BrowserSession? = nil

    var body: some View {
        // Neutral, not the system tint: iOS blue painted every control as
        // though it were the one to press, and Limeghost's surfaces were never
        // built for it. Chrome's bar is neutral for the same reason. The accent
        // is kept for the one control that is *on* — the assistant while it is
        // open — and the tint that does the neutralising is set once, on the
        // whole bar, below.
        //
        // Every tap area is 44 by 44 points, Apple's floor. The back button's
        // was its chevron alone, about 12 by 20, and the tab count's was the
        // 24-point box it draws: the most-used control in any browser had the
        // smallest target in the bar. The spacing came down as the areas grew,
        // so the address capsule kept its width.
        HStack(spacing: 4) {
            Button(action: goBack) {
                Image(systemName: "chevron.backward")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
                .disabled(!model.canGoBack)
                .accessibilityLabel("Back")

            Button(action: openAddress) {
                Text(model.addressLabel)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(LimeghostTheme.bg3))
                    .overlay {
                        if let session {
                            AddressProgressOutline(session: session)
                        }
                    }
                    .foregroundStyle(LimeghostTheme.textPrimary)
            }
            .accessibilityLabel("Address")

            // Your own assistant, lit while it is open, as the Mac's toolbar
            // button is.
            Button(action: toggleAssistant) {
                AssistantMark()
                    .foregroundStyle(
                        model.isAssistantOpen ? AnyShapeStyle(LimeghostTheme.onAccent) : AnyShapeStyle(LimeghostTheme.textPrimary)
                    )
                    .frame(width: 38, height: 38)
                    .background(
                        model.isAssistantOpen ? LimeghostTheme.accent : Color.clear,
                        in: RoundedRectangle(cornerRadius: LimeghostTheme.radius8)
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(model.assistantLabel)

            Button(action: openTabs) {
                Text("\(model.tabCount)")
                    .font(.footnote.weight(.semibold))
                    .frame(minWidth: 24, minHeight: 24)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(lineWidth: 1.5))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Tabs, \(model.tabCount) open")

            // The page menu. Its touch area is 44 points wide and as tall as
            // the address pill: the glyph alone is a target a finger misses.
            Button(action: openMenu) {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Menu")
        }
        // `.tint`, not a `.foregroundStyle` per control. The bar's blue came
        // from the system accent, and the hierarchical styles — `.primary` on
        // a glyph, `.quaternary` on the address capsule — resolve against
        // whatever the current foreground is, which inside a `Button` is that
        // tint. Setting the levels individually left the capsule and the
        // assistant blue while their neighbours turned neutral; retinting the
        // whole bar is what actually reaches them.
        .tint(LimeghostTheme.textPrimary)
        .padding(.horizontal, 16)
        // Five, down from eight, because the tap areas grew to 44: the bar is
        // the same height it was.
        .padding(.vertical, 5)
        // Limeghost's own surfaces, not the system's, and therefore the same
        // in a lit room as a dark one. The chrome is dark because that is the
        // product — the Mac says so in as many words — and a bar that went
        // white whenever the phone did was the one part that had not been told.
        // `bg1` is the plane the Mac's toolbar and bookmarks bar share; the
        // address capsule above takes `bg3`, the raised control, which is the
        // same climb the Mac's surfaces make and a test there enforces.
        .background(LimeghostTheme.bg1)
        // The chrome is dark whatever the phone is, so anything the system
        // draws inside it — a menu, a text field's caret — has to be told, or
        // it arrives dressed for the other appearance. The page is deliberately
        // NOT in here: a web view told the phone prefers dark would say so to
        // every site, which is the trap the Mac guards against in its own
        // session code.
        .environment(\.colorScheme, .dark)
    }
}
