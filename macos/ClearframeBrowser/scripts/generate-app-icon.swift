import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: generate-app-icon.swift OUTPUT.iconset OUTPUT.icns\n", stderr)
    exit(2)
}

/// The brand marks live in `docs/brand/`, four levels above this script.
/// Loaded once: `NSImage` decoding is not free and this renders ten variants.
private func loadMark(_ name: String) -> NSImage? {
    let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // scripts
        .deletingLastPathComponent()   // ClearframeBrowser
        .deletingLastPathComponent()   // macos
        .deletingLastPathComponent()   // repo root
    let url = repoRoot
        .appendingPathComponent("docs/brand/clearframe-mark-2026-08-31")
        .appendingPathComponent(name)
    return NSImage(contentsOf: url)
}

let fullMarkImage = loadMark("clearframe-mark-full.png")
let smallMarkImage = loadMark("clearframe-mark-small.png")
if fullMarkImage == nil || smallMarkImage == nil {
    fputs("warning: brand artwork not found; drawing the geometric fallback mark\n", stderr)
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

    // The mark is the product's name drawn in the icon set's own rule: a
    // closed form whose top-right corner is cut at 45 degrees. An empty frame,
    // because that is what the name says. Same geometry as the 104 folder
    // icons — 1.5 units of stroke and 1.75 of cut on a 16 box — so the app
    // icon reads as the family's own member rather than a separate logo.
    let tileInset = size * 0.055
    let tileRect = NSRect(
        x: tileInset,
        y: tileInset,
        width: size - tileInset * 2,
        height: size - tileInset * 2
    )
    let tile = NSBezierPath(roundedRect: tileRect, xRadius: size * 0.2237, yRadius: size * 0.2237)

    // Near-black, lifted very slightly at the top so the tile has depth in the
    // Dock instead of reading as a hole.
    let ground = NSGradient(
        starting: NSColor(calibratedRed: 0.086, green: 0.094, blue: 0.110, alpha: 1),
        ending: NSColor(calibratedRed: 0.035, green: 0.039, blue: 0.047, alpha: 1)
    )
    tile.addClip()
    ground?.draw(in: tileRect, angle: -90)
    NSGraphicsContext.current?.cgContext.resetClip()

    // A hairline so the tile still has an edge on a black wallpaper.
    NSColor(calibratedWhite: 1, alpha: 0.06).setStroke()
    tile.lineWidth = max(1, size * 0.004)
    tile.stroke()

    // The brand mark, drawn from artwork rather than geometry.
    //
    // Two files, chosen by size, because one drawing cannot serve both ends:
    // at 16 and 32 pixels the ring turns to mud and takes the owl's face with
    // it, so those sizes get the face alone. Above that there is room for the
    // whole mark. Measured, not assumed — the full mark was rendered at both
    // and only the face survived the small one.
    let markArtwork = pixels <= 32 ? smallMarkImage : fullMarkImage
    if let artwork = markArtwork {
        // The artwork's own visible content fills about 92 percent of its
        // canvas, so the drawn rect is enlarged to land the *owl* at the
        // intended share of the tile rather than the transparent box round it.
        let visibleShare: CGFloat = 0.92
        let intended: CGFloat = pixels <= 32 ? 0.60 : 0.66
        let drawSide = size * intended / visibleShare
        let origin = (size - drawSide) / 2
        NSGraphicsContext.current?.imageInterpolation = .high
        artwork.draw(
            in: NSRect(x: origin, y: origin, width: drawSide, height: drawSide),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "ClearframeIcon", code: 2)
        }
        return png
    }

    // Fallback: the geometric mark this script drew before the owl existed —
    // a closed form with its top-right corner cut at 45 degrees, sharing the
    // folder icons' geometry. Kept so a missing asset degrades to a correct
    // icon instead of failing the build.
    let isSmall = pixels <= 32
    let markSide = size * (isSmall ? 0.52 : 0.46)
    let strokeWidth = markSide * (isSmall ? 0.135 : 0.094)
    // The cut is the whole point of the shape, and at menu-bar size the
    // authored 1.75 units round away to nothing. Deepen it there so the corner
    // still reads as turned instead of merely rounded.
    let cut = markSide * (isSmall ? 0.26 : 0.109)
    let originX = (size - markSide) / 2
    let originY = (size - markSide) / 2

    let mark = NSBezierPath()
    mark.move(to: NSPoint(x: originX, y: originY))
    mark.line(to: NSPoint(x: originX + markSide, y: originY))
    mark.line(to: NSPoint(x: originX + markSide, y: originY + markSide - cut))
    mark.line(to: NSPoint(x: originX + markSide - cut, y: originY + markSide))
    mark.line(to: NSPoint(x: originX, y: originY + markSide))
    mark.close()
    mark.lineWidth = strokeWidth
    mark.lineCapStyle = .round
    mark.lineJoinStyle = .round
    NSColor(calibratedRed: 0.40, green: 0.86, blue: 0.49, alpha: 1).setStroke()
    mark.stroke()

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
