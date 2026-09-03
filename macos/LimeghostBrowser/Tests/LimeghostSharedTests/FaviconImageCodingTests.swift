import XCTest
import CoreGraphics
@testable import LimeghostShared

final class FaviconImageCodingTests: XCTestCase {
    /// A 2×2 opaque square, encoded and decoded, keeps its size. The point is
    /// not the pixels: it is that encoding and decoding go through ImageIO on
    /// both platforms rather than through AppKit on one of them.
    func testAnIconRoundTripsThroughImageIO() throws {
        let context = CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        let source = try XCTUnwrap(context?.makeImage())

        let data = try XCTUnwrap(FaviconStore.pngData(from: source))
        let decoded = try XCTUnwrap(FaviconStore.image(from: data))

        XCTAssertEqual(decoded.width, 2)
        XCTAssertEqual(decoded.height, 2)
    }

    /// Bytes that are not an image return nil rather than throwing, because a
    /// site can serve anything at /favicon.ico and a browser must not crash on it.
    func testGarbageBytesDecodeToNothing() {
        XCTAssertNil(FaviconStore.image(from: Data([0x00, 0x01, 0x02, 0x03])))
    }
}
