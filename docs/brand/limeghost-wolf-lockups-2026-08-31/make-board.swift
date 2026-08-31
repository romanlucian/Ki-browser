import AppKit
import Foundation

struct Concept {
    let number: Int
    let name: String
    let filename: String
}

let concepts = [
    Concept(number: 1, name: "Threshold Wolf", filename: "01-threshold-wolf.png"),
    Concept(number: 2, name: "Corner Guardian", filename: "02-corner-guardian.png"),
    Concept(number: 3, name: "Negative Window", filename: "03-negative-window.png"),
    Concept(number: 4, name: "Twin Profiles", filename: "04-twin-profiles.png"),
    Concept(number: 5, name: "Tail Frame", filename: "05-tail-frame.png"),
    Concept(number: 6, name: "One Ribbon Sentinel", filename: "06-one-ribbon-sentinel.png"),
    Concept(number: 7, name: "Rising View", filename: "07-rising-view.png"),
    Concept(number: 8, name: "Clear Gaze", filename: "08-clear-gaze.png"),
    Concept(number: 9, name: "Passing Wolf", filename: "09-passing-wolf.png"),
    Concept(number: 10, name: "Resting Frame", filename: "10-resting-frame.png")
]

let boardWidth = 1_920
let boardHeight = 1_440
let headerHeight: CGFloat = 160
let slotWidth: CGFloat = 960
let slotHeight: CGFloat = 256
let cardInset: CGFloat = 12
let cardSize = NSSize(width: 936, height: 232)

let directory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let outputURL = directory.appendingPathComponent("clearframe-wolf-lockup-board.png")

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: boardWidth,
    pixelsHigh: boardHeight,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Could not create board bitmap")
}

guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not create board graphics context")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

let background = color(7, 7, 10)
let cardBackground = color(16, 16, 19)
let cardBorder = color(42, 42, 49)
let primaryText = color(244, 244, 242)
let secondaryText = color(161, 161, 170)
let mint = color(102, 219, 125)

background.setFill()
NSRect(x: 0, y: 0, width: boardWidth, height: boardHeight).fill()

let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 44, weight: .semibold),
    .foregroundColor: primaryText,
    .kern: -0.5
]
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 20, weight: .regular),
    .foregroundColor: secondaryText
]
let wordmarkAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 52, weight: .semibold),
    .foregroundColor: primaryText,
    .kern: -0.7
]
let conceptAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 18, weight: .medium),
    .foregroundColor: mint,
    .kern: 0.2
]

NSAttributedString(string: "Clearframe — wolf + frame exploration", attributes: titleAttributes)
    .draw(at: NSPoint(x: 60, y: 1_348))
NSAttributedString(string: "Ten equal lockups · one shared wordmark · concept board", attributes: subtitleAttributes)
    .draw(at: NSPoint(x: 62, y: 1_308))

for (index, concept) in concepts.enumerated() {
    let column = index % 2
    let rowFromTop = index / 2
    let slotX = CGFloat(column) * slotWidth
    let slotY = CGFloat(4 - rowFromTop) * slotHeight
    let cardRect = NSRect(
        x: slotX + cardInset,
        y: slotY + cardInset,
        width: cardSize.width,
        height: cardSize.height
    )

    let card = NSBezierPath(roundedRect: cardRect, xRadius: 22, yRadius: 22)
    cardBackground.setFill()
    card.fill()
    cardBorder.setStroke()
    card.lineWidth = 2
    card.stroke()

    let imageURL = directory.appendingPathComponent(concept.filename)
    guard let image = NSImage(contentsOf: imageURL) else {
        fatalError("Could not load \(concept.filename)")
    }

    let iconRect = NSRect(
        x: cardRect.minX + 26,
        y: cardRect.minY + 26,
        width: 180,
        height: 180
    )
    image.draw(
        in: iconRect,
        from: NSRect(origin: .zero, size: image.size),
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )

    NSAttributedString(string: "Clearframe", attributes: wordmarkAttributes)
        .draw(at: NSPoint(x: cardRect.minX + 238, y: cardRect.minY + 112))

    let conceptLabel = String(format: "%02d  %@", concept.number, concept.name)
    NSAttributedString(string: conceptLabel, attributes: conceptAttributes)
        .draw(at: NSPoint(x: cardRect.minX + 240, y: cardRect.minY + 72))
}

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode board PNG")
}
try png.write(to: outputURL, options: .atomic)
print(outputURL.path)
