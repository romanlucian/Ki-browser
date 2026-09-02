import LimeghostCore
import SwiftUI

/// Draws one icon from a shipped set.
///
/// Two kinds of artwork come through here. Limeghost's own set is drawn in a
/// 16x16 box at a 1.5 stroke and names no colour, so the stroke scales with the
/// icon and the caller's colour reaches it — a 16pt bar icon and a 28pt picker
/// icon read as the same drawing at two sizes, which is the point of a set built
/// on one stroke weight. A licensed set brings its own box and its own colours;
/// those are drawn as authored, and a folder tint has nothing to act on.
struct LimeghostIconView: View {
    let iconID: String
    var size: CGFloat = LimeghostTheme.siteIconSize

    private var geometry: LimeghostIconGeometry.Resolved {
        LimeghostIconGeometry.resolved(for: iconID)
    }

    var body: some View {
        let geometry = geometry
        // The artwork's own units are square-scaled, so one factor converts a
        // stroke authored in box units into points at the drawn size.
        let scale = size / max(geometry.box.width, geometry.box.height)
        Group {
            if geometry.style.isTintable {
                inherited(geometry, scale: scale)
            } else {
                painted(geometry, scale: scale)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Artwork that names no colour, drawn as a shape per element so the
    /// caller's `foregroundStyle` reaches it. Only the Limeghost set takes
    /// this path, and it is a handful of elements per icon.
    private func inherited(_ geometry: LimeghostIconGeometry.Resolved, scale: CGFloat) -> some View {
        ZStack {
            ForEach(Array(geometry.shapes.enumerated()), id: \.offset) { _, shape in
                VectorCommandShape(commands: shape.commands, box: geometry.box)
                    .painted(shape, style: geometry.strokeStyle(for: shape, scale: scale))
                    .opacity(shape.opacity)
            }
        }
    }

    /// Artwork that carries its own colours, drawn imperatively in one canvas.
    ///
    /// A view per element does not scale here. Illustrative sets are drawn in
    /// hundreds or thousands of paths — one flag in the emoji set is over five
    /// thousand — and at that size a shape view each costs a third of a second
    /// per frame, which the bookmarks bar would pay on every redraw. The same
    /// geometry through a single canvas is several times faster, and leaves
    /// only two icons in the whole set above one frame's budget.
    private func painted(_ geometry: LimeghostIconGeometry.Resolved, scale: CGFloat) -> some View {
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            for shape in geometry.shapes {
                let path = VectorCommandShape(commands: shape.commands, box: geometry.box).path(in: rect)
                // A colourful set almost always names its colour; the rare
                // element that does not falls back to the caller's, which
                // stays visible on any surface.
                let color = (shape.colorHex.flatMap(Color.init(iconHex:)) ?? .primary)
                    .opacity(shape.opacity)
                switch shape.paint {
                case .filled:
                    context.fill(path, with: .color(color), style: FillStyle(eoFill: shape.usesEvenOddFill))
                case .stroked:
                    context.stroke(path, with: .color(color), style: geometry.strokeStyle(for: shape, scale: scale))
                }
            }
        }
    }
}

private extension VectorCommandShape {
    /// One call site for every paint keeps the `ForEach` branch-free, which
    /// SwiftUI's builder handles better than a `switch` returning many types.
    /// A shape that named no colour is left unfilled so the caller's
    /// `foregroundStyle` shows through.
    @ViewBuilder
    func painted(_ shape: VectorShape, style: StrokeStyle) -> some View {
        switch (shape.paint, shape.colorHex.flatMap(Color.init(iconHex:))) {
        case (.stroked, .some(let color)):
            stroke(color, style: style)
        case (.stroked, .none):
            stroke(style: style)
        case (.filled, .some(let color)):
            fill(color, style: FillStyle(eoFill: shape.usesEvenOddFill))
        case (.filled, .none):
            fill(style: FillStyle(eoFill: shape.usesEvenOddFill))
        }
    }
}

/// Scales parsed geometry from the artwork's own box into whatever rectangle it
/// is given, preserving aspect and centring what is left over.
struct VectorCommandShape: Shape, @unchecked Sendable {
    let commands: [VectorPathCommand]
    var box: VectorBox = .sixteen

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / box.width, rect.height / box.height)
        let dx = rect.minX + (rect.width - box.width * scale) / 2 - box.x * scale
        let dy = rect.minY + (rect.height - box.height * scale) / 2 - box.y * scale
        func point(_ p: CGPoint) -> CGPoint {
            CGPoint(x: dx + p.x * scale, y: dy + p.y * scale)
        }

        var path = Path()
        for command in commands {
            switch command {
            case .move(let p):
                path.move(to: point(p))
            case .line(let p):
                path.addLine(to: point(p))
            case .quad(let to, let control):
                path.addQuadCurve(to: point(to), control: point(control))
            case .cubic(let to, let c1, let c2):
                path.addCurve(to: point(to), control1: point(c1), control2: point(c2))
            case .close:
                path.closeSubpath()
            case .ellipse(let center, let radii):
                let c = point(center)
                path.addEllipse(
                    in: CGRect(
                        x: c.x - radii.width * scale,
                        y: c.y - radii.height * scale,
                        width: radii.width * 2 * scale,
                        height: radii.height * 2 * scale
                    )
                )
            }
        }
        return path
    }
}

/// Parses each icon once per launch. The catalog is fixed at build time, so a
/// plain dictionary is enough; nothing here ever invalidates.
@MainActor
enum LimeghostIconGeometry {
    /// Everything drawing one icon needs, with the fallback already applied.
    struct Resolved {
        let shapes: [VectorShape]
        let box: VectorBox
        let strokeWidth: Double
        let style: LimeghostIconStyle

        /// How one shape's stroke is drawn: the artwork's own cap and join
        /// where it named them, the style's defaults where it did not.
        func strokeStyle(for shape: VectorShape, scale: CGFloat) -> StrokeStyle {
            StrokeStyle(
                lineWidth: strokeWidth * scale,
                lineCap: (shape.lineCap ?? style.defaultLineCap).cgLineCap,
                lineJoin: (shape.lineJoin ?? style.defaultLineJoin).cgLineJoin,
                // The artwork asks for a miter limit of 10, which is also
                // SwiftUI's default — sharp points survive rather than
                // silently bevelling.
                miterLimit: 10
            )
        }
    }

    private static var cache: [String: Resolved] = [:]

    static func resolved(for iconID: String) -> Resolved {
        if let cached = cache[iconID] { return cached }
        let icon = LimeghostIconCatalog.icon(id: iconID)
            ?? LimeghostIconCatalog.icon(id: LimeghostIconCatalog.defaultIconID)
        let style = icon?.style ?? .limeghost
        let resolved = Resolved(
            shapes: icon.flatMap { VectorPathParser.parse($0.markup) } ?? [],
            box: icon?.box ?? .sixteen,
            strokeWidth: style.strokeWidth,
            style: style
        )
        cache[iconID] = resolved
        return resolved
    }

    static func shapes(for iconID: String) -> [VectorShape] {
        resolved(for: iconID).shapes
    }

    /// The icon a folder should draw: its chosen icon, else the one its old
    /// emoji maps to, else the plain folder.
    static func iconID(for folder: BookmarkFolderRecord) -> String {
        LimeghostIconCatalog.resolvedIconID(iconID: folder.iconID, legacyEmoji: folder.emoji)
    }

    /// Whether a folder's tint reaches its icon. A multicolour set carries its
    /// own colours, so the swatch row has nothing to change and says so rather
    /// than offering a control that does nothing.
    static func isTintable(iconID: String) -> Bool {
        LimeghostIconCatalog.icon(id: iconID)?.style.isTintable ?? true
    }
}

/// A folder's icon at a given size, in the folder's own tint, resolving the
/// legacy-emoji fallback. Pass `tinted: false` where the surrounding view
/// already owns the colour — a selected row, say — so the icon can go quiet
/// with its neighbours instead of shouting through them.
///
/// A multicolour icon ignores both: its colours are in the artwork.
struct BookmarkFolderIcon: View {
    let folder: BookmarkFolderRecord
    var size: CGFloat = LimeghostTheme.siteIconSize
    var tinted: Bool = true

    var body: some View {
        let iconID = LimeghostIconGeometry.iconID(for: folder)
        let icon = LimeghostIconView(iconID: iconID, size: size)
        if tinted, LimeghostIconGeometry.isTintable(iconID: iconID) {
            icon.foregroundStyle(Color(folder.resolvedColor))
        } else {
            icon
        }
    }
}

// Internal rather than private to this file: `ChromeIconView` draws in the
// same hand and must honour a cap the markup names the same way. One
// conversion, both callers.
extension VectorShape.LineCap {
    var cgLineCap: CGLineCap {
        switch self {
        case .butt: return .butt
        case .round: return .round
        case .square: return .square
        }
    }
}

extension VectorShape.LineJoin {
    var cgLineJoin: CGLineJoin {
        switch self {
        case .miter: return .miter
        case .round: return .round
        case .bevel: return .bevel
        }
    }
}

extension Color {
    /// The set's four tints, built from the palette the artwork was drawn
    /// against rather than re-picked here.
    init(_ iconColor: LimeghostIconColor) {
        let rgb = iconColor.components
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    /// A colour an icon named for itself, as six hex digits without the `#`.
    /// Fails rather than guesses, so a shape with unreadable paint falls back
    /// to the caller's colour instead of drawing in black.
    init?(iconHex: String) {
        guard iconHex.count == 6, let value = UInt32(iconHex, radix: 16) else { return nil }
        self.init(hex: value)
    }
}
