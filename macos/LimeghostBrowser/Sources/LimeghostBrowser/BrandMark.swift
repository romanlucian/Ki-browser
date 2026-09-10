import ImageIO
import SwiftUI

/// The Limeghost mark, drawn from the artwork rather than redrawn in code so
/// the address bar and the app icon can never show two different owls.
///
/// The *small* mark on purpose: it is the face alone, drawn for 16–32 px, and
/// it is the only one of the three that survives this size. The full mark's
/// ring closes to a smear below 32 px and takes the face with it, which
/// `docs/brand/limeghost-mark-2026-08-31/README.md` records as measured rather
/// than assumed.
///
/// Falls back to nothing rather than to a placeholder: an address bar missing
/// its mark is a build mistake worth noticing, and a stand-in glyph sitting
/// where a security indicator belongs is worse than an empty space.
///
/// Both apps compile this file, because the phone's AI guide draws the mark
/// too. So it decodes the artwork into a `CGImage` with ImageIO, the way
/// `FaviconStore` decodes site icons, rather than through `NSImage`. The one
/// thing that differs between the two apps is where the artwork lives. Each
/// app target answers that in a file of its own: `BrandMarkArtwork.swift` on
/// the Mac, `IOSBrandMarkArtwork.swift` on the phone. This file never asks
/// which platform it is on.
struct BrandMark: View {
    var size: CGFloat = 15

    private static let image: CGImage? = {
        guard let url = artworkURL,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }()

    /// Whether the artwork is actually in the bundle. A missing resource draws
    /// nothing and raises no error, so the address bar would simply ship empty
    /// — this is what lets a test catch that before somebody sees it.
    static var isAvailable: Bool { image != nil }

    var body: some View {
        if let image = Self.image {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}
