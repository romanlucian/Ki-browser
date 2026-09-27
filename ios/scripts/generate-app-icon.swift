#!/usr/bin/env swift
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// The iPhone app's icon: one 1024-pixel square, which is all a modern asset
// catalog needs for iOS.
//
// Not a mode of the Mac's `generate-app-icon.swift`, because the two are not
// the same drawing. macOS draws an inset rounded tile with transparent corners
// and a hairline, because a Mac icon carries its own shape. **iOS masks the
// corners itself**, so this fills the whole square, has no hairline — the mask
// would cut it unevenly — and carries **no alpha channel at all**, which
// App Store validation requires of an app icon.
//
// What must not drift between them is the palette and the mark, so both are
// stated here with the reason:
//
//   - the near-black gradient is the Mac's, to the same three decimals;
//   - the artwork is `limeghost-mark-full.png`, the form CLAUDE.md reserves
//     for 32 pixels and above, which 1024 comfortably is;
//   - the artwork's visible content fills about 92 percent of its own canvas,
//     so the drawn rect is enlarged to land the *owl* at the intended share of
//     the icon rather than the transparent box around it. Measured on the Mac,
//     inherited here.
//
// Usage: ios/scripts/generate-app-icon.swift OUTPUT.png

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate-app-icon.swift OUTPUT.png\n", stderr)
    exit(2)
}
let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // scripts
    .deletingLastPathComponent()   // ios
    .deletingLastPathComponent()   // repo root
let artworkURL = repoRoot
    .appendingPathComponent("docs/brand/limeghost-mark-2026-08-31")
    .appendingPathComponent("limeghost-mark-full.png")
guard let artwork = NSImage(contentsOf: artworkURL) else {
    fputs("error: brand artwork not found at \(artworkURL.path)\n", stderr)
    exit(1)
}

let pixels = 1024
let size = CGFloat(pixels)

// A CoreGraphics surface with `noneSkipLast`, not an `NSBitmapImageRep`:
// `NSGraphicsContext(bitmapImageRep:)` returns nil for an alpha-free rep, so
// the obvious spelling of "opaque" cannot be drawn into at all. This keeps a
// fourth byte per pixel for alignment and tells CoreGraphics to ignore it, and
// ImageIO then writes a PNG with no alpha channel — which app-icon validation
// requires, even of an image that is opaque everywhere.
guard let surface = CGContext(
    data: nil,
    width: pixels,
    height: pixels,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    fputs("error: could not make the drawing surface\n", stderr)
    exit(1)
}

let context = NSGraphicsContext(cgContext: surface, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

let square = NSRect(x: 0, y: 0, width: size, height: size)
NSGradient(
    starting: NSColor(calibratedRed: 0.086, green: 0.094, blue: 0.110, alpha: 1),
    ending: NSColor(calibratedRed: 0.035, green: 0.039, blue: 0.047, alpha: 1)
)?.draw(in: square, angle: -90)

// 0.70 of the square. The Mac draws the mark at 0.66 of its canvas inside a
// tile inset by 5.5 percent, which is about 0.74 of the visible tile; iOS has
// no inset and a more aggressive corner mask, so this sits between the two.
// Judged by looking at the rendered icon, not derived.
let visibleShare: CGFloat = 0.92
let intended: CGFloat = 0.70
let drawSide = size * intended / visibleShare
let origin = (size - drawSide) / 2
NSGraphicsContext.current?.imageInterpolation = .high
artwork.draw(
    in: NSRect(x: origin, y: origin, width: drawSide, height: drawSide),
    from: .zero,
    operation: .sourceOver,
    fraction: 1
)

NSGraphicsContext.restoreGraphicsState()

guard let image = surface.makeImage() else {
    fputs("error: could not read the surface back\n", stderr)
    exit(1)
}
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true
)
guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL, "public.png" as CFString, 1, nil
) else {
    fputs("error: could not open the output\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("error: could not write the icon\n", stderr)
    exit(1)
}
print("wrote \(outputURL.path) (\(pixels)×\(pixels))")
