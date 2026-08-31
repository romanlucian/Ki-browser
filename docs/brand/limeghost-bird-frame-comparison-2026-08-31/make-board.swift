import AppKit
import Foundation

struct Concept {
    let number: Int
    let name: String
    let filename: String
}

let concepts = [
    Concept(number: 1, name: "Peregrine Profile", filename: "01-peregrine-profile-transparent.png"),
    Concept(number: 2, name: "Falcon Rising", filename: "02-falcon-rising.png"),
    Concept(number: 3, name: "Barn Owl", filename: "03-barn-owl-transparent.png"),
    Concept(number: 4, name: "Heron", filename: "04-heron-transparent-v2.png"),
    Concept(number: 5, name: "Golden Eagle", filename: "05-golden-eagle-transparent.png")
]

let boardWidth = 2_000
let boardHeight = 760
let directory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let outputURL = directory.appendingPathComponent("clearframe-bird-frame-board.png")

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func aspectFit(_ imageSize: NSSize, in bounds: NSRect) -> NSRect {
    let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
    let size = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
    return NSRect(
        x: bounds.midX - size.width / 2,
        y: bounds.midY - size.height / 2,
        width: size.width,
        height: size.height
    )
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
    .font: NSFont.systemFont(ofSize: 42, weight: .semibold),
    .foregroundColor: primaryText,
    .kern: -0.5
]
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 19, weight: .regular),
    .foregroundColor: secondaryText
]
let wordmarkAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 41, weight: .semibold),
    .foregroundColor: primaryText,
    .kern: -0.6
]
let conceptAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 17, weight: .medium),
    .foregroundColor: mint,
    .kern: 0.1
]

NSAttributedString(string: "Clearframe — bird + frame comparison", attributes: titleAttributes)
    .draw(at: NSPoint(x: 50, y: 688))
NSAttributedString(string: "Two falcons · barn owl · heron · golden eagle", attributes: subtitleAttributes)
    .draw(at: NSPoint(x: 52, y: 650))

let cardWidth: CGFloat = 360
let cardHeight: CGFloat = 540
let cardGap: CGFloat = 30
let cardStartX: CGFloat = 40
let cardY: CGFloat = 50

for (index, concept) in concepts.enumerated() {
    let cardRect = NSRect(
        x: cardStartX + CGFloat(index) * (cardWidth + cardGap),
        y: cardY,
        width: cardWidth,
        height: cardHeight
    )
    let card = NSBezierPath(roundedRect: cardRect, xRadius: 24, yRadius: 24)
    cardBackground.setFill()
    card.fill()
    cardBorder.setStroke()
    card.lineWidth = 2
    card.stroke()

    let imageURL = directory.appendingPathComponent(concept.filename)
    guard let image = NSImage(contentsOf: imageURL) else {
        fatalError("Could not load \(concept.filename)")
    }
    let iconBounds = NSRect(x: cardRect.minX + 42, y: cardRect.minY + 220, width: 276, height: 276)
    image.draw(
        in: aspectFit(image.size, in: iconBounds),
        from: NSRect(origin: .zero, size: image.size),
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )

    let wordmark = NSAttributedString(string: "Clearframe", attributes: wordmarkAttributes)
    let wordmarkSize = wordmark.size()
    wordmark.draw(at: NSPoint(x: cardRect.midX - wordmarkSize.width / 2, y: cardRect.minY + 128))

    let conceptLabel = NSAttributedString(
        string: String(format: "%02d  %@", concept.number, concept.name),
        attributes: conceptAttributes
    )
    let conceptSize = conceptLabel.size()
    conceptLabel.draw(at: NSPoint(x: cardRect.midX - conceptSize.width / 2, y: cardRect.minY + 86))
}

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode board PNG")
}
try png.write(to: outputURL, options: .atomic)
print(outputURL.path)
