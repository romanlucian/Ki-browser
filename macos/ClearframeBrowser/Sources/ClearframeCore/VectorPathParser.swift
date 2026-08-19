import CoreGraphics
import Foundation

/// One drawing instruction, with every shorthand already resolved: horizontal
/// and vertical runs are lines, smooth curves carry their reflected control
/// point, relative coordinates are absolute, and arcs are cubic béziers. A
/// renderer walks this list and never has to know SVG.
public enum VectorPathCommand: Equatable, Sendable {
    case move(CGPoint)
    case line(CGPoint)
    case quad(to: CGPoint, control: CGPoint)
    case cubic(to: CGPoint, c1: CGPoint, c2: CGPoint)
    case close
    /// A whole `<circle>` or `<ellipse>` element. Kept as an ellipse rather
    /// than four béziers so a round form stays exactly round at any size.
    case ellipse(center: CGPoint, radii: CGSize)
}

/// One element of an icon: its geometry, and whether the artwork strokes it or
/// fills it.
///
/// The set is stroke-based, with one deliberate exception — a handful of icons
/// use a solid dot (`fill="currentColor" stroke="none"`). Stroking such a dot
/// would draw a ring, so the paint has to survive parsing.
public struct VectorShape: Equatable, Sendable {
    public enum Paint: Sendable {
        case stroked
        case filled
    }

    public let paint: Paint
    public let commands: [VectorPathCommand]
    /// The colour this element names, as six hex digits without the `#`.
    ///
    /// `nil` means the element named none, so it draws in whatever colour the
    /// caller is using. That is the Clearframe set's whole convention, and the
    /// only reason a folder tint can apply at all — a multicolour set carries
    /// its own colours here and ignores the tint by construction.
    public let colorHex: String?
    /// Even-odd winding rather than non-zero. Only meaningful while filling,
    /// and only the multicolour sets ask for it.
    public let usesEvenOddFill: Bool
    /// How this element's stroke ends and turns corners, when the artwork says.
    /// `nil` leaves the choice to the style: the Clearframe set is drawn to be
    /// rounded throughout, while a set that follows SVG's own defaults wants
    /// butt ends and mitred corners — forcing round joins on it visibly blunts
    /// sharp points such as a star's.
    public let lineCap: LineCap?
    public let lineJoin: LineJoin?

    public enum LineCap: String, Sendable {
        case butt, round, square
    }

    public enum LineJoin: String, Sendable {
        case miter, round, bevel
    }

    public init(
        paint: Paint,
        commands: [VectorPathCommand],
        colorHex: String? = nil,
        usesEvenOddFill: Bool = false,
        lineCap: LineCap? = nil,
        lineJoin: LineJoin? = nil
    ) {
        self.paint = paint
        self.commands = commands
        self.colorHex = colorHex
        self.usesEvenOddFill = usesEvenOddFill
        self.lineCap = lineCap
        self.lineJoin = lineJoin
    }
}

/// Turns the icon set's markup into drawable geometry.
///
/// Deliberately strict: anything it was not built for — an unknown element, an
/// unknown path command, a missing or non-numeric attribute, a truncated
/// coordinate list — returns `nil` instead of a guess. A malformed icon then
/// fails loudly in the catalog test rather than shipping as garbage on screen.
///
/// Foundation-only, like the rest of `ClearframeCore`: `CGPoint` and `CGSize`
/// are geometry value types, not a UI dependency.
public enum VectorPathParser {
    /// Every element of one icon's markup, in drawing order.
    ///
    /// Groups are walked rather than drawn: `fill`, `stroke`, and `fill-rule`
    /// inherit down the tree the way SVG says they do, so a `<g>` that names a
    /// colour hands it to every child that does not name its own.
    public static func parse(_ markup: String) -> [VectorShape]? {
        var scanner = MarkupScanner(markup)
        guard let nodes = scanner.scanNodes(closing: nil) else { return nil }
        guard !nodes.isEmpty else { return nil }

        // Definitions are gathered up front: `<use>` may reference a shape
        // declared after it, and document order is not reference order.
        var definitions: [String: MarkupNode] = [:]
        for node in nodes { collectDefinitions(node, into: &definitions) }

        var shapes: [VectorShape] = []
        for node in nodes {
            guard emit(node, context: PaintContext(), definitions: definitions, into: &shapes) else {
                return nil
            }
        }
        return shapes.isEmpty ? nil : shapes
    }

    /// Indexes everything inside `<defs>` by its identifier, so `<use>` can
    /// find it. A definition draws nothing where it sits.
    private static func collectDefinitions(_ node: MarkupNode, into definitions: inout [String: MarkupNode]) {
        if node.name == "defs" {
            for child in node.children where child.attributes["id"] != nil {
                definitions[child.attributes["id"]!] = child
            }
        }
        for child in node.children { collectDefinitions(child, into: &definitions) }
    }

    /// Appends one node's drawing to `shapes`, or reports refusal. Returning a
    /// flag rather than throwing keeps the parser's all-or-nothing contract:
    /// one unknown element and the whole icon is refused.
    private static func emit(
        _ node: MarkupNode,
        context: PaintContext,
        definitions: [String: MarkupNode],
        into shapes: inout [VectorShape]
    ) -> Bool {
        let context = context.inheriting(node.attributes)

        switch node.name {
        case "g":
            for child in node.children {
                guard emit(child, context: context, definitions: definitions, into: &shapes) else { return false }
            }
            return true
        case "defs":
            // Already indexed; a definition is drawn only where it is used.
            return true
        case "clipPath":
            // Every clip in the shipped artwork is the icon's own full frame,
            // which clips nothing. Honouring it would cost a layer per icon
            // and change no pixel. If artwork ever ships a real clip, this is
            // the line that has to grow.
            return true
        case "use":
            guard let href = node.attributes["href"], href.hasPrefix("#") else { return false }
            guard let target = definitions[String(href.dropFirst())] else { return false }
            return emit(target, context: context, definitions: definitions, into: &shapes)
        case "path":
            guard let data = node.attributes["d"],
                  let commands = parsePathData(data),
                  !commands.isEmpty else { return false }
            append(commands, context: context, into: &shapes)
            return true
        case "circle":
            guard let cx = node.number("cx"),
                  let cy = node.number("cy"),
                  let r = node.number("r"),
                  r > 0 else { return false }
            append(
                [.ellipse(center: CGPoint(x: cx, y: cy), radii: CGSize(width: r, height: r))],
                context: context,
                into: &shapes
            )
            return true
        case "ellipse":
            guard let cx = node.number("cx"),
                  let cy = node.number("cy"),
                  let rx = node.number("rx"),
                  let ry = node.number("ry"),
                  rx > 0, ry > 0 else { return false }
            append(
                [.ellipse(center: CGPoint(x: cx, y: cy), radii: CGSize(width: rx, height: ry))],
                context: context,
                into: &shapes
            )
            return true
        default:
            return false
        }
    }

    /// Turns one element's geometry and its resolved paint into drawable
    /// shapes. An element that both fills and strokes becomes two shapes in
    /// that order, which is what SVG draws and what keeps `paint` a single
    /// unambiguous answer per shape.
    private static func append(
        _ commands: [VectorPathCommand],
        context: PaintContext,
        into shapes: inout [VectorShape]
    ) {
        var painted = false
        if let fill = context.fill, fill != "none" {
            shapes.append(
                VectorShape(
                    paint: .filled,
                    commands: commands,
                    colorHex: normalizedHex(fill),
                    usesEvenOddFill: context.fillRule == "evenodd"
                )
            )
            painted = true
        }
        if let stroke = context.stroke, stroke != "none" {
            shapes.append(
                VectorShape(
                    paint: .stroked,
                    commands: commands,
                    colorHex: normalizedHex(stroke),
                    lineCap: context.lineCap.flatMap(VectorShape.LineCap.init(rawValue:)),
                    lineJoin: context.lineJoin.flatMap(VectorShape.LineJoin.init(rawValue:))
                )
            )
            painted = true
        }
        // The Clearframe set names no paint at all: a bare element is a stroke
        // in the caller's own colour. An element that explicitly asked for
        // neither fill nor stroke is honoured as drawing nothing.
        if !painted && context.fill == nil && context.stroke == nil {
            shapes.append(
                VectorShape(
                    paint: .stroked,
                    commands: commands,
                    colorHex: nil,
                    lineCap: context.lineCap.flatMap(VectorShape.LineCap.init(rawValue:)),
                    lineJoin: context.lineJoin.flatMap(VectorShape.LineJoin.init(rawValue:))
                )
            )
        }
    }

    /// Six lowercase hex digits, or `nil` for a colour that means "whatever
    /// the caller is drawing in".
    private static func normalizedHex(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        let digits = trimmed.dropFirst().lowercased()
        if digits.count == 6, digits.allSatisfy(\.isHexDigit) { return String(digits) }
        if digits.count == 3, digits.allSatisfy(\.isHexDigit) {
            return digits.map { "\($0)\($0)" }.joined()
        }
        return nil
    }

    /// The same markup flattened into one command list, for callers that only
    /// need the geometry — measurement, bounds checks, tests.
    public static func commands(_ markup: String) -> [VectorPathCommand]? {
        parse(markup).map { $0.flatMap(\.commands) }
    }

    // MARK: - Path data

    /// Parses one `d` attribute. Absolute and relative forms of every command
    /// are accepted, including the implicit repeats SVG allows: extra
    /// coordinate pairs after a move continue as lines, and extra parameter
    /// sets after any other command repeat that command.
    public static func parsePathData(_ data: String) -> [VectorPathCommand]? {
        var reader = PathDataReader(data)
        var commands: [VectorPathCommand] = []

        /// Where the pen is.
        var current = CGPoint.zero
        /// Where the current subpath started, so `Z` knows what to return to.
        var subpathStart = CGPoint.zero
        /// The last cubic and quadratic control points, for `S`/`s` and `T`/`t`
        /// reflection. Nil whenever the previous command was not of that kind,
        /// which is what the SVG rules require.
        var lastCubicControl: CGPoint?
        var lastQuadControl: CGPoint?
        var lastCommand: Character?

        while true {
            reader.skipSeparators()
            if reader.isAtEnd { break }

            var command: Character
            if let letter = reader.scanCommandLetter() {
                command = letter
            } else if let previous = lastCommand, previous != "Z", previous != "z" {
                // An implicit repeat: another parameter set for the command
                // already running. A move repeats as a line, per SVG.
                command = previous == "M" ? "L" : (previous == "m" ? "l" : previous)
            } else {
                return nil
            }

            let isRelative = command.isLowercase
            let uppercased = command.uppercased()
            guard uppercased.count == 1, let absolute = uppercased.first else { return nil }

            switch absolute {
            case "M":
                guard let point = reader.scanPoint(relativeTo: isRelative ? current : .zero) else { return nil }
                current = point
                subpathStart = point
                commands.append(.move(point))
                lastCubicControl = nil
                lastQuadControl = nil
            case "L":
                guard let point = reader.scanPoint(relativeTo: isRelative ? current : .zero) else { return nil }
                current = point
                commands.append(.line(point))
                lastCubicControl = nil
                lastQuadControl = nil
            case "H":
                guard let x = reader.scanNumber() else { return nil }
                current = CGPoint(x: isRelative ? current.x + x : x, y: current.y)
                commands.append(.line(current))
                lastCubicControl = nil
                lastQuadControl = nil
            case "V":
                guard let y = reader.scanNumber() else { return nil }
                current = CGPoint(x: current.x, y: isRelative ? current.y + y : y)
                commands.append(.line(current))
                lastCubicControl = nil
                lastQuadControl = nil
            case "C":
                let origin = isRelative ? current : .zero
                guard let c1 = reader.scanPoint(relativeTo: origin),
                      let c2 = reader.scanPoint(relativeTo: origin),
                      let end = reader.scanPoint(relativeTo: origin) else { return nil }
                commands.append(.cubic(to: end, c1: c1, c2: c2))
                current = end
                lastCubicControl = c2
                lastQuadControl = nil
            case "S":
                let origin = isRelative ? current : .zero
                guard let c2 = reader.scanPoint(relativeTo: origin),
                      let end = reader.scanPoint(relativeTo: origin) else { return nil }
                let c1 = reflect(lastCubicControl, about: current)
                commands.append(.cubic(to: end, c1: c1, c2: c2))
                current = end
                lastCubicControl = c2
                lastQuadControl = nil
            case "Q":
                let origin = isRelative ? current : .zero
                guard let control = reader.scanPoint(relativeTo: origin),
                      let end = reader.scanPoint(relativeTo: origin) else { return nil }
                commands.append(.quad(to: end, control: control))
                current = end
                lastQuadControl = control
                lastCubicControl = nil
            case "T":
                let origin = isRelative ? current : .zero
                guard let end = reader.scanPoint(relativeTo: origin) else { return nil }
                let control = reflect(lastQuadControl, about: current)
                commands.append(.quad(to: end, control: control))
                current = end
                lastQuadControl = control
                lastCubicControl = nil
            case "A":
                guard let rx = reader.scanNumber(),
                      let ry = reader.scanNumber(),
                      let rotation = reader.scanNumber(),
                      let largeArc = reader.scanFlag(),
                      let sweep = reader.scanFlag(),
                      let end = reader.scanPoint(relativeTo: isRelative ? current : .zero) else { return nil }
                commands.append(
                    contentsOf: arcCommands(
                        from: current,
                        to: end,
                        rx: rx,
                        ry: ry,
                        rotationDegrees: rotation,
                        largeArc: largeArc,
                        sweep: sweep
                    )
                )
                current = end
                lastCubicControl = nil
                lastQuadControl = nil
            case "Z":
                commands.append(.close)
                current = subpathStart
                lastCubicControl = nil
                lastQuadControl = nil
            default:
                return nil
            }
            lastCommand = command
        }

        // Path data that produced nothing is defective artwork, not an
        // empty drawing: refuse it so the catalog test catches it.
        return commands.isEmpty ? nil : commands
    }

    /// The mirror of a control point through the current point — what `S` and
    /// `T` mean by "smooth". With no previous curve of the right kind the
    /// current point is its own reflection, which is what SVG specifies.
    private static func reflect(_ control: CGPoint?, about current: CGPoint) -> CGPoint {
        guard let control else { return current }
        return CGPoint(x: 2 * current.x - control.x, y: 2 * current.y - control.y)
    }

    // MARK: - Arcs

    /// Converts one SVG elliptical arc into cubic béziers, by the endpoint-to-
    /// centre parameterization in the SVG specification (F.6.5), including the
    /// out-of-range radii correction (F.6.6).
    ///
    /// The two degenerate cases the specification calls out are handled the way
    /// it asks: an arc whose endpoints coincide draws nothing, and an arc with a
    /// zero radius is a straight line. The sweep is then cut into segments of at
    /// most 90 degrees, each approximated by a cubic — the standard construction,
    /// well under a thousandth of a unit of error at this size.
    static func arcCommands(
        from start: CGPoint,
        to end: CGPoint,
        rx: Double,
        ry: Double,
        rotationDegrees: Double,
        largeArc: Bool,
        sweep: Bool
    ) -> [VectorPathCommand] {
        if start == end { return [] }
        var rx = abs(rx)
        var ry = abs(ry)
        if rx == 0 || ry == 0 { return [.line(end)] }

        let phi = rotationDegrees * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        // Step 1: the endpoints in the ellipse's own frame.
        let dx2 = (start.x - end.x) / 2
        let dy2 = (start.y - end.y) / 2
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2

        // Step 2 (F.6.6): grow radii that are too small to reach.
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let scale = lambda.squareRoot()
            rx *= scale
            ry *= scale
        }

        // Step 3: the centre, in that same frame.
        let rxSquared = rx * rx
        let rySquared = ry * ry
        let numerator = max(0, rxSquared * rySquared - rxSquared * y1p * y1p - rySquared * x1p * x1p)
        let denominator = rxSquared * y1p * y1p + rySquared * x1p * x1p
        guard denominator > 0 else { return [.line(end)] }
        var coefficient = (numerator / denominator).squareRoot()
        if largeArc == sweep { coefficient = -coefficient }
        let cxp = coefficient * rx * y1p / ry
        let cyp = -coefficient * ry * x1p / rx

        // Step 4: back to the drawing's frame, and the swept angles.
        let cx = cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2

        let startAngle = angle(
            ux: 1, uy: 0,
            vx: (x1p - cxp) / rx, vy: (y1p - cyp) / ry
        )
        var sweepAngle = angle(
            ux: (x1p - cxp) / rx, uy: (y1p - cyp) / ry,
            vx: (-x1p - cxp) / rx, vy: (-y1p - cyp) / ry
        )
        if !sweep && sweepAngle > 0 {
            sweepAngle -= 2 * .pi
        } else if sweep && sweepAngle < 0 {
            sweepAngle += 2 * .pi
        }

        // Step 5: quarter-turn bézier segments.
        let segmentCount = max(1, Int(ceil(abs(sweepAngle) / (.pi / 2 + 1e-9))))
        let segmentAngle = sweepAngle / Double(segmentCount)
        let alpha = 4.0 / 3.0 * tan(segmentAngle / 4)

        var commands: [VectorPathCommand] = []
        var from = start
        var theta = startAngle
        for _ in 0..<segmentCount {
            let next = theta + segmentAngle
            let to = ellipsePoint(cx: cx, cy: cy, rx: rx, ry: ry, cosPhi: cosPhi, sinPhi: sinPhi, angle: next)
            let d1 = ellipseDerivative(rx: rx, ry: ry, cosPhi: cosPhi, sinPhi: sinPhi, angle: theta)
            let d2 = ellipseDerivative(rx: rx, ry: ry, cosPhi: cosPhi, sinPhi: sinPhi, angle: next)
            let c1 = CGPoint(x: from.x + alpha * d1.x, y: from.y + alpha * d1.y)
            let c2 = CGPoint(x: to.x - alpha * d2.x, y: to.y - alpha * d2.y)
            commands.append(.cubic(to: to, c1: c1, c2: c2))
            from = to
            theta = next
        }
        // The last segment must land exactly on the stated endpoint; rounding
        // in the trigonometry above must never move it.
        if case .cubic(_, let c1, let c2) = commands[commands.count - 1] {
            commands[commands.count - 1] = .cubic(to: end, c1: c1, c2: c2)
        }
        return commands
    }

    private static func ellipsePoint(
        cx: Double, cy: Double,
        rx: Double, ry: Double,
        cosPhi: Double, sinPhi: Double,
        angle: Double
    ) -> CGPoint {
        let x = rx * cos(angle)
        let y = ry * sin(angle)
        return CGPoint(x: cosPhi * x - sinPhi * y + cx, y: sinPhi * x + cosPhi * y + cy)
    }

    private static func ellipseDerivative(
        rx: Double, ry: Double,
        cosPhi: Double, sinPhi: Double,
        angle: Double
    ) -> CGPoint {
        let dx = -rx * sin(angle)
        let dy = ry * cos(angle)
        return CGPoint(x: cosPhi * dx - sinPhi * dy, y: sinPhi * dx + cosPhi * dy)
    }

    /// Signed angle between two vectors, the SVG helper used for the arc's
    /// start and sweep.
    private static func angle(ux: Double, uy: Double, vx: Double, vy: Double) -> Double {
        let dot = ux * vx + uy * vy
        let lengths = (ux * ux + uy * uy).squareRoot() * (vx * vx + vy * vy).squareRoot()
        guard lengths > 0 else { return 0 }
        let cosine = min(1, max(-1, dot / lengths))
        let sign: Double = (ux * vy - uy * vx) < 0 ? -1 : 1
        return sign * acos(cosine)
    }
}

// MARK: - Markup scanning

/// The paint an element has inherited from its ancestors, before its own
/// attributes are applied. Held as the raw attribute strings so the rules for
/// "unset" and "none" stay distinguishable — the first falls back to the
/// caller's colour, the second draws nothing.
private struct PaintContext {
    var fill: String?
    var stroke: String?
    var fillRule: String?
    var lineCap: String?
    var lineJoin: String?

    func inheriting(_ attributes: [String: String]) -> PaintContext {
        PaintContext(
            fill: attributes["fill"] ?? fill,
            stroke: attributes["stroke"] ?? stroke,
            fillRule: attributes["fill-rule"] ?? fillRule,
            lineCap: attributes["stroke-linecap"] ?? lineCap,
            lineJoin: attributes["stroke-linejoin"] ?? lineJoin
        )
    }
}

/// One element from an icon's markup, with whatever it contains.
private struct MarkupNode {
    let name: String
    let attributes: [String: String]
    let children: [MarkupNode]

    func number(_ name: String) -> Double? {
        attributes[name].flatMap(Double.init)
    }
}

/// A deliberately tiny reader for the markup these catalogs use: elements with
/// quoted attributes, nested or self-closing, and no text between them.
/// Anything richer — entities, comments, text nodes, an unbalanced tag — is
/// rejected rather than half-understood.
private struct MarkupScanner {
    private let characters: [Character]
    private var index = 0

    init(_ markup: String) {
        characters = Array(markup)
    }

    /// Reads sibling elements until `</closing>`, or until the markup ends when
    /// `closing` is nil. A missing closing tag is a refusal, not a guess.
    mutating func scanNodes(closing: String?) -> [MarkupNode]? {
        var nodes: [MarkupNode] = []
        while true {
            skipWhitespace()
            if index >= characters.count {
                return closing == nil ? nodes : nil
            }
            guard characters[index] == "<" else { return nil }

            if index + 1 < characters.count, characters[index + 1] == "/" {
                guard let closing else { return nil }
                index += 2
                guard let name = scanName(), name == closing else { return nil }
                skipWhitespace()
                guard index < characters.count, characters[index] == ">" else { return nil }
                index += 1
                return nodes
            }

            index += 1
            guard let node = scanElement() else { return nil }
            nodes.append(node)
        }
    }

    private mutating func scanElement() -> MarkupNode? {
        guard let name = scanName(), !name.isEmpty else { return nil }
        var attributes: [String: String] = [:]
        while true {
            skipWhitespace()
            guard index < characters.count else { return nil }
            if characters[index] == "/" {
                index += 1
                guard index < characters.count, characters[index] == ">" else { return nil }
                index += 1
                return MarkupNode(name: name, attributes: attributes, children: [])
            }
            if characters[index] == ">" {
                index += 1
                guard let children = scanNodes(closing: name) else { return nil }
                return MarkupNode(name: name, attributes: attributes, children: children)
            }
            guard let attributeName = scanName(), !attributeName.isEmpty else { return nil }
            skipWhitespace()
            guard index < characters.count, characters[index] == "=" else { return nil }
            index += 1
            skipWhitespace()
            guard index < characters.count, characters[index] == "\"" else { return nil }
            index += 1
            var value = ""
            while index < characters.count, characters[index] != "\"" {
                value.append(characters[index])
                index += 1
            }
            guard index < characters.count else { return nil }
            index += 1
            guard attributes[attributeName] == nil else { return nil }
            attributes[attributeName] = value
        }
    }

    private mutating func scanName() -> String? {
        var name = ""
        while index < characters.count,
              characters[index].isLetter || characters[index].isNumber || characters[index] == "-" {
            name.append(characters[index])
            index += 1
        }
        return name.isEmpty ? nil : name
    }

    private mutating func skipWhitespace() {
        while index < characters.count, characters[index].isWhitespace { index += 1 }
    }
}

// MARK: - Path data scanning

/// Reads the number and command soup inside a `d` attribute. SVG allows a lot
/// of shorthand here — commas or spaces or nothing at all between numbers, a
/// leading sign standing in for a separator, and single-digit arc flags packed
/// against their neighbours — so the reader handles all of it explicitly.
private struct PathDataReader {
    private let characters: [Character]
    private var index = 0

    init(_ data: String) {
        characters = Array(data)
    }

    var isAtEnd: Bool { index >= characters.count }

    mutating func skipSeparators() {
        while index < characters.count, characters[index].isWhitespace || characters[index] == "," {
            index += 1
        }
    }

    mutating func scanCommandLetter() -> Character? {
        guard index < characters.count else { return nil }
        let character = characters[index]
        guard character.isLetter, character != "e", character != "E" else { return nil }
        index += 1
        return character
    }

    mutating func scanNumber() -> Double? {
        skipSeparators()
        let start = index
        if index < characters.count, characters[index] == "+" || characters[index] == "-" { index += 1 }
        var sawDigit = false
        while index < characters.count, characters[index].isNumber { index += 1; sawDigit = true }
        if index < characters.count, characters[index] == "." {
            index += 1
            while index < characters.count, characters[index].isNumber { index += 1; sawDigit = true }
        }
        guard sawDigit else {
            index = start
            return nil
        }
        if index < characters.count, characters[index] == "e" || characters[index] == "E" {
            let exponentStart = index
            index += 1
            if index < characters.count, characters[index] == "+" || characters[index] == "-" { index += 1 }
            var sawExponentDigit = false
            while index < characters.count, characters[index].isNumber { index += 1; sawExponentDigit = true }
            if !sawExponentDigit { index = exponentStart }
        }
        return Double(String(characters[start..<index]))
    }

    /// An arc flag is exactly one character, `0` or `1`, and may sit flush
    /// against the number after it.
    mutating func scanFlag() -> Bool? {
        skipSeparators()
        guard index < characters.count else { return nil }
        switch characters[index] {
        case "0": index += 1; return false
        case "1": index += 1; return true
        default: return nil
        }
    }

    mutating func scanPoint(relativeTo origin: CGPoint) -> CGPoint? {
        guard let x = scanNumber(), let y = scanNumber() else { return nil }
        return CGPoint(x: origin.x + x, y: origin.y + y)
    }
}
