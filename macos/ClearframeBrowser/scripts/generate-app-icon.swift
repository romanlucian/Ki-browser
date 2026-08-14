import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: generate-app-icon.swift OUTPUT.iconset OUTPUT.icns\n", stderr)
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let icnsURL = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func renderIcon(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "ClearframeIcon", code: 1)
    }

    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }

    let size = CGFloat(pixels)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let outerInset = size * 0.055
    let outerRect = NSRect(
        x: outerInset,
        y: outerInset,
        width: size - outerInset * 2,
        height: size - outerInset * 2
    )
    let outer = NSBezierPath(roundedRect: outerRect, xRadius: size * 0.22, yRadius: size * 0.22)
    NSColor(calibratedRed: 0.035, green: 0.19, blue: 0.14, alpha: 1).setFill()
    outer.fill()

    let frameInset = size * 0.17
    let frameRect = NSRect(
        x: frameInset,
        y: frameInset,
        width: size - frameInset * 2,
        height: size - frameInset * 2
    )
    let frame = NSBezierPath(roundedRect: frameRect, xRadius: size * 0.15, yRadius: size * 0.15)
    NSColor(calibratedRed: 0.075, green: 0.34, blue: 0.25, alpha: 1).setFill()
    frame.fill()

    let font = NSFont(name: "Georgia-Bold", size: size * 0.48)
        ?? NSFont.systemFont(ofSize: size * 0.48, weight: .bold)
    let text = "C" as NSString
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(calibratedRed: 0.83, green: 0.96, blue: 0.46, alpha: 1)
    ]
    let textSize = text.size(withAttributes: attributes)
    text.draw(
        at: NSPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2 + size * 0.015),
        withAttributes: attributes
    )

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "ClearframeIcon", code: 2)
    }
    return png
}

var renderedByPixelSize: [Int: Data] = [:]
for variant in variants {
    let png = try renderIcon(pixels: variant.pixels)
    renderedByPixelSize[variant.pixels] = png
    try png.write(
        to: outputDirectory.appendingPathComponent(variant.name),
        options: .atomic
    )
}

// ICNS is a sequence of typed, length-prefixed image records. Writing the
// modern PNG-backed records directly avoids depending on iconutil, which is
// not reliable across all macOS runner versions.
func appendBigEndian(_ value: UInt32, to data: inout Data) {
    var encoded = value.bigEndian
    Swift.withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
}

let iconRecords: [(type: String, pixels: Int)] = [
    ("icp4", 16),
    ("icp5", 32),
    ("icp6", 64),
    ("ic07", 128),
    ("ic08", 256),
    ("ic09", 512),
    ("ic10", 1024)
]

var body = Data()
for record in iconRecords {
    guard let png = renderedByPixelSize[record.pixels] else {
        throw NSError(domain: "ClearframeIcon", code: 3)
    }
    body.append(contentsOf: record.type.utf8)
    appendBigEndian(UInt32(png.count + 8), to: &body)
    body.append(png)
}

var icns = Data("icns".utf8)
appendBigEndian(UInt32(body.count + 8), to: &icns)
icns.append(body)
try icns.write(to: icnsURL, options: .atomic)
