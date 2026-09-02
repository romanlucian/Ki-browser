import LimeghostCore
import SwiftUI

/// The toolbar's own drawings.
///
/// Every chrome icon was an SF Symbol until September 2, 2026. They are fine
/// glyphs and every Mac app has them, which was the problem: the bookmarks bar
/// underneath was already drawing in Limeghost's own hand — a 16-unit box, a
/// 1.5 stroke, round caps and joins — and the toolbar above it was speaking a
/// different language. These are the same eleven ideas in that hand, so the two
/// rows finally match.
///
/// Deliberately NOT in `LimeghostIconCatalog`: that catalogue is what the
/// folder picker offers, and a back arrow has no business being a bookmark
/// folder's icon. Same markup grammar, same parser, same stroke — a separate
/// list, because they answer to different surfaces.
///
/// Two of these are lifted verbatim from the shipped set rather than redrawn:
/// `star` is `LimeghostIconCatalog`'s own star and `bolt` its own bolt. Where
/// the set already had the drawing, using a second one would be the drift this
/// file exists to close.
enum ChromeIcon: String, CaseIterable {
    case back, forward, home, reload
    case star, starFilled, voice, library, download
    case assistant, reader
    case close, chevronDown, arrowRight, ellipsis
    case shield, shieldSlash, lock, lockSlash, lockWarning, globe
    case gear, plus, magnifier

    /// A 16-unit box of stroke-only geometry, in the grammar
    /// `VectorPathParser` already reads for the folder set.
    ///
    /// Paths, circles and ellipses only — the parser does not read `<rect>`,
    /// and an element it cannot read parses to nothing and draws nothing with
    /// no error. Four of these were rects on the first pass and would have
    /// shipped as blank buttons; `testEveryChromeIconParsesIntoSomethingDrawable`
    /// is what caught it.
    var markup: String {
        switch self {
        case .back:        return #"<path d="M9.5 3.5 L5 8 L9.5 12.5"/>"#
        case .forward:     return #"<path d="M6.5 3.5 L11 8 L6.5 12.5"/>"#
        case .home:        return #"<path d="M2.75 8 L8 3.25 L13.25 8"/><path d="M4.5 6.75 V12.75 H11.5 V6.75"/>"#
        case .reload:      return #"<path d="M12.75 8.25 A4.75 4.75 0 1 1 11.3 4.75"/><path d="M11.75 2.75 V5.25 H9.25"/>"#
        // The shipped set's own star, verbatim.
        case .star:        return #"<path d="M8 2.5 L9.45 6.55 L13.5 8 L9.45 9.45 L8 13.5 L6.55 9.45 L2.5 8 L6.55 6.55 Z"/>"#
        case .starFilled:  return #"<path d="M8 2.5 L9.45 6.55 L13.5 8 L9.45 9.45 L8 13.5 L6.55 9.45 L2.5 8 L6.55 6.55 Z" fill="currentColor"/>"#
        case .voice:       return #"<path d="M6 4.75 A2 2 0 0 1 10 4.75 V7.25 A2 2 0 0 1 6 7.25 Z"/><path d="M4 8.25 A4 4 0 0 0 12 8.25"/><path d="M8 12.25 V13.75"/>"#
        case .library:     return #"<path d="M2.75 12.75 V3.75 H5.25 V12.75 Z"/><path d="M5.25 12.75 V5.5 H7.75 V12.75 Z"/><path d="M8.5 4.5 L10.75 3.75 L13.25 12.25 L11 13 Z"/>"#
        case .download:    return #"<path d="M8 2.75 V9.5"/><path d="M5.25 7 L8 9.75 L10.75 7"/><path d="M2.75 11.25 V12.75 H13.25 V11.25"/>"#
        // Two speech shapes overlapping: a conversation, not a robot.
        case .assistant:   return #"<path d="M2.75 4.25 H8.75 V8.25 H5.25 L3.25 10 V8.25 H2.75 Z"/><path d="M10.25 6.75 H13.25 V10.75 H12.75 V12.5 L10.75 10.75 H7.75 V9.75"/>"#
        case .reader:      return #"<path d="M4.25 2.75 H9.25 L11.75 5.25 V13.25 H4.25 Z"/><path d="M9.25 2.75 V5.25 H11.75"/><path d="M6.25 8.25 H9.75 M6.25 10.25 H9.75 M6.25 12.25 H8.25"/>"#
        case .close:       return #"<path d="M4.75 4.75 L11.25 11.25 M11.25 4.75 L4.75 11.25"/>"#
        case .chevronDown: return #"<path d="M4.75 6.25 L8 9.5 L11.25 6.25"/>"#
        case .arrowRight:  return #"<path d="M3.5 8 H12.5 M9 4.5 L12.5 8 L9 11.5"/>"#
        case .ellipsis:    return #"<circle cx="4" cy="8" r="1" fill="currentColor" stroke="none"/><circle cx="8" cy="8" r="1" fill="currentColor" stroke="none"/><circle cx="12" cy="8" r="1" fill="currentColor" stroke="none"/>"#
        case .shield:      return #"<path d="M8 2.75 L13.25 4.75 V8 C13.25 11 10.75 12.75 8 13.5 C5.25 12.75 2.75 11 2.75 8 V4.75 Z"/>"#
        case .shieldSlash: return #"<path d="M8 2.75 L13.25 4.75 V8 C13.25 11 10.75 12.75 8 13.5 C5.25 12.75 2.75 11 2.75 8 V4.75 Z"/><path d="M3.5 3.5 L12.5 12.5"/>"#
        case .lock:        return #"<path d="M4.75 7 H11.25 A1.5 1.5 0 0 1 12.75 8.5 V11.75 A1.5 1.5 0 0 1 11.25 13.25 H4.75 A1.5 1.5 0 0 1 3.25 11.75 V8.5 A1.5 1.5 0 0 1 4.75 7 Z"/><path d="M5.5 7 V5 A2.5 2.5 0 0 1 10.5 5 V7"/>"#
        case .lockSlash:   return #"<path d="M4.75 7 H11.25 A1.5 1.5 0 0 1 12.75 8.5 V11.75 A1.5 1.5 0 0 1 11.25 13.25 H4.75 A1.5 1.5 0 0 1 3.25 11.75 V8.5 A1.5 1.5 0 0 1 4.75 7 Z"/><path d="M5.5 7 V5 A2.5 2.5 0 0 1 10.5 5 V7"/><path d="M3 2.75 L13 13.25"/>"#
        case .lockWarning: return #"<path d="M4.75 7 H11.25 A1.5 1.5 0 0 1 12.75 8.5 V11.75 A1.5 1.5 0 0 1 11.25 13.25 H4.75 A1.5 1.5 0 0 1 3.25 11.75 V8.5 A1.5 1.5 0 0 1 4.75 7 Z"/><path d="M5.5 7 V5 A2.5 2.5 0 0 1 10.5 5 V7"/><path d="M8 9 V10.75"/><circle cx="8" cy="12" r="0.6" fill="currentColor" stroke="none"/>"#
        case .globe:       return #"<circle cx="8" cy="8" r="5.25"/><path d="M2.75 8 H13.25"/><path d="M8 2.75 A7 7 0 0 1 8 13.25 A7 7 0 0 1 8 2.75 Z"/>"#
        case .gear:        return #"<circle cx="8" cy="8" r="2.25"/><path d="M8 2.5 V4 M8 12 V13.5 M2.5 8 H4 M12 8 H13.5 M4.1 4.1 L5.2 5.2 M10.8 10.8 L11.9 11.9 M11.9 4.1 L10.8 5.2 M5.2 10.8 L4.1 11.9"/>"#
        case .plus:        return #"<path d="M8 3.5 V12.5 M3.5 8 H12.5"/>"#
        case .magnifier:   return #"<circle cx="7.25" cy="7.25" r="4"/><path d="M10.25 10.25 L13.25 13.25"/>"#
        }
    }
}

/// Draws a chrome icon at the size the toolbar asks for.
///
/// The stroke scales with the box the way `LimeghostIconView` does, so a glyph
/// at 17 and a folder mark at 18 carry the same visual weight — which is the
/// whole point of moving the toolbar into this hand.
struct ChromeIconView: View {
    let icon: ChromeIcon
    var size: CGFloat = 17

    /// The Limeghost set's stroke, in its own 16-unit box. Read from the
    /// catalogue's style rather than typed here, so the two cannot drift.
    private static let strokeWidth = LimeghostIconStyle.limeghost.strokeWidth

    /// Parsed once per glyph per launch. The list is fixed at build time.
    private static var cache: [ChromeIcon: [VectorShape]] = [:]

    private var shapes: [VectorShape] {
        if let cached = Self.cache[icon] { return cached }
        let parsed = VectorPathParser.parse(icon.markup) ?? []
        Self.cache[icon] = parsed
        return parsed
    }

    var body: some View {
        let scale = size / 16
        ZStack {
            ForEach(Array(shapes.enumerated()), id: \.offset) { _, shape in
                let path = VectorCommandShape(commands: shape.commands, box: .sixteen)
                if shape.paint == .filled {
                    path.fill(style: FillStyle(eoFill: shape.usesEvenOddFill))
                } else {
                    path.stroke(
                        style: StrokeStyle(
                            lineWidth: Self.strokeWidth * scale,
                            lineCap: (shape.lineCap ?? .round).cgLineCap,
                            lineJoin: (shape.lineJoin ?? .round).cgLineJoin,
                            miterLimit: 10
                        )
                    )
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
