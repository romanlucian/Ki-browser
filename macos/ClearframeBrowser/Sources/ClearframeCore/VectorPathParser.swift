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

    public init(paint: Paint, commands: [VectorPathCommand]) {
        self.paint = paint
        self.commands = commands
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
    public static func parse(_ markup: String) -> [VectorShape]? {
        var scanner = MarkupScanner(markup)
        guard let elements = scanner.scanElements() else { return nil }
        guard !elements.isEmpty else { return nil }

        var shapes: [VectorShape] = []
        for element in elements {
            switch element.name {
            case "path":
                guard let data = element.attributes["d"],
                      let commands = parsePathData(data),
                      !commands.isEmpty else { return nil }
                shapes.append(VectorShape(paint: element.paint, commands: commands))
            case "circle":
                guard let cx = element.number("cx"),
                      let cy = element.number("cy"),
                      let r = element.number("r"),
                      r > 0 else { return nil }
                shapes.append(
                    VectorShape(
                        paint: element.paint,
                        commands: [.ellipse(center: CGPoint(x: cx, y: cy), radii: CGSize(width: r, height: r))]
                    )
                )
            case "ellipse":
                guard let cx = element.number("cx"),
                      let cy = element.number("cy"),
                      let rx = element.number("rx"),
                      let ry = element.number("ry"),
                      rx > 0, ry > 0 else { return nil }
                shapes.append(
                    VectorShape(
                        paint: element.paint,
                        commands: [.ellipse(center: CGPoint(x: cx, y: cy), radii: CGSize(width: rx, height: ry))]
                    )
                )
            default:
                return nil
            }
        }
        return shapes
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

/// One `<tag …/>` from an icon's markup.
private struct MarkupElement {
    let name: String
    let attributes: [String: String]

    /// The set draws in strokes; only an explicit `fill` turns an element into
    /// a solid form.
    var paint: VectorShape.Paint {
        guard let fill = attributes["fill"], fill != "none" else { return .stroked }
        return .filled
    }

    func number(_ name: String) -> Double? {
        attributes[name].flatMap(Double.init)
    }
}

/// A deliberately tiny reader for the one markup shape this catalog uses:
/// self-closing elements with quoted attributes and no text between them.
/// Anything richer — nesting, entities, comments, text nodes — is rejected
/// rather than half-understood.
private struct MarkupScanner {
    private let characters: [Character]
    private var index = 0

    init(_ markup: String) {
        characters = Array(markup)
    }

    mutating func scanElements() -> [MarkupElement]? {
        var elements: [MarkupElement] = []
        while true {
            skipWhitespace()
            if index >= characters.count { return elements }
            guard characters[index] == "<" else { return nil }
            index += 1
            guard let element = scanElement() else { return nil }
            elements.append(element)
        }
    }

    private mutating func scanElement() -> MarkupElement? {
        guard let name = scanName(), !name.isEmpty else { return nil }
        var attributes: [String: String] = [:]
        while true {
            skipWhitespace()
            guard index < characters.count else { return nil }
            if characters[index] == "/" {
                index += 1
                guard index < characters.count, characters[index] == ">" else { return nil }
                index += 1
                return MarkupElement(name: name, attributes: attributes)
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
        while index < characters.count, characters[index].isLetter || characters[index] == "-" {
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
