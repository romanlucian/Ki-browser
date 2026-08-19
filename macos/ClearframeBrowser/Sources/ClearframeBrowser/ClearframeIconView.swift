import ClearframeCore
import SwiftUI

/// Draws one icon from the bundled Clearframe set.
///
/// The artwork is authored in a 16x16 box at a 1.5 stroke, so the stroke is
/// scaled with the icon rather than fixed: a 13pt bar icon and a 24pt picker
/// icon then read as the same drawing at two sizes, which is the whole point
/// of a set built on one stroke weight. Colour is inherited, never baked in.
struct ClearframeIconView: View {
    let iconID: String
    var size: CGFloat = 13

    private var shapes: [VectorShape] { ClearframeIconGeometry.shapes(for: iconID) }

    var body: some View {
        ZStack {
            ForEach(Array(shapes.enumerated()), id: \.offset) { _, shape in
                VectorCommandShape(commands: shape.commands)
                    .stroked(shape.paint == .stroked, lineWidth: 1.5 * size / 16)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private extension VectorCommandShape {
    /// One call site for both paints keeps the `ForEach` branch-free, which
    /// SwiftUI's builder handles better than a `switch` returning two types.
    @ViewBuilder
    func stroked(_ isStroked: Bool, lineWidth: CGFloat) -> some View {
        if isStroked {
            stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        } else {
            fill()
        }
    }
}

/// Scales the parsed 16x16 geometry into whatever rectangle it is given.
struct VectorCommandShape: Shape, @unchecked Sendable {
    let commands: [VectorPathCommand]

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 16
        let dx = rect.minX + (rect.width - 16 * scale) / 2
        let dy = rect.minY + (rect.height - 16 * scale) / 2
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
enum ClearframeIconGeometry {
    private static var cache: [String: [VectorShape]] = [:]

    static func shapes(for iconID: String) -> [VectorShape] {
        if let cached = cache[iconID] { return cached }
        let resolved = ClearframeIconCatalog.icon(id: iconID)
            ?? ClearframeIconCatalog.icon(id: ClearframeIconCatalog.defaultIconID)
        let shapes = resolved.flatMap { VectorPathParser.parse($0.markup) } ?? []
        cache[iconID] = shapes
        return shapes
    }

    /// The icon a folder should draw: its chosen icon, else the one its old
    /// emoji maps to, else the plain folder.
    static func iconID(for folder: BookmarkFolderRecord) -> String {
        ClearframeIconCatalog.resolvedIconID(iconID: folder.iconID, legacyEmoji: folder.emoji)
    }
}

/// A folder's icon at a given size, resolving the legacy-emoji fallback.
struct BookmarkFolderIcon: View {
    let folder: BookmarkFolderRecord
    var size: CGFloat = 13

    var body: some View {
        ClearframeIconView(iconID: ClearframeIconGeometry.iconID(for: folder), size: size)
    }
}
