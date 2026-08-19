import CoreGraphics
import Foundation
import XCTest
@testable import ClearframeCore

/// The icon set and the parser that draws it.
///
/// The parser is the risk in this feature: nothing else in the app turns text
/// into geometry, and a silent mistake there does not crash — it draws a wrong
/// shape that a reader would have to notice by eye. So the catalog sweep at the
/// top of this file is the regression net: every shipped icon has to parse, has
/// to produce something drawable, and has to stay inside its own 16-point box.
final class ClearframeIconTests: XCTestCase {

    // MARK: - The catalog

    func testCatalogShipsOneHundredFourIconsAcrossThirteenCategories() {
        XCTAssertEqual(ClearframeIconCatalog.icons(style: .clearframe).count, 104)
        XCTAssertEqual(ClearframeIconCategory.allCases.count, 13)

        let expectedCounts: [ClearframeIconCategory: Int] = [
            .work: 7, .creative: 7, .reading: 7, .shopping: 7, .travel: 7, .code: 7,
            .people: 10, .media: 10, .home: 10, .markers: 10,
            .nature: 8, .objects: 8,
            .interface: 6
        ]
        for category in ClearframeIconCategory.allCases {
            XCTAssertEqual(
                ClearframeIconCatalog.icons(in: category).count,
                expectedCounts[category],
                "\(category.rawValue) has the wrong number of icons"
            )
            XCTAssertFalse(category.title.isEmpty)
        }
        XCTAssertEqual(
            expectedCounts.values.reduce(0, +),
            ClearframeIconCatalog.icons(style: .clearframe).count,
            "the categories account for every icon"
        )
    }

    /// The licensed sets are one hundred drawings twice, and the two are
    /// separate styles rather than one mixed set: a bar that mixed them would
    /// read as a mistake.
    func testStickiesShipsBothStylesOfEveryDrawing() {
        let plain = ClearframeIconCatalog.icons(style: .stickiesPlain)
        let duo = ClearframeIconCatalog.icons(style: .stickiesDuo)
        XCTAssertEqual(plain.count, 100)
        XCTAssertEqual(duo.count, 100)

        let plainNames = Set(plain.map { $0.id.replacingOccurrences(of: "stickies-", with: "") })
        let duoNames = Set(duo.map { $0.id.replacingOccurrences(of: "stickies-duo-", with: "") })
        XCTAssertEqual(plainNames, duoNames, "every drawing ships in both styles")

        XCTAssertEqual(
            ClearframeIconCatalog.all.count,
            104 + 200,
            "one lookup has to answer for every style"
        )
        XCTAssertEqual(ClearframeIconCatalog.availableStyles, ClearframeIconStyle.allCases)
    }

    /// The tint is the reason the Clearframe set names no colour. A licensed
    /// set carries its own, so the swatch row must not pretend otherwise.
    func testOnlyTheClearframeSetIsTintable() {
        XCTAssertTrue(ClearframeIconStyle.clearframe.isTintable)
        XCTAssertFalse(ClearframeIconStyle.stickiesPlain.isTintable)
        XCTAssertFalse(ClearframeIconStyle.stickiesDuo.isTintable)

        XCTAssertNil(ClearframeIconStyle.clearframe.attribution)
        for style in [ClearframeIconStyle.stickiesPlain, .stickiesDuo] {
            XCTAssertEqual(style.attribution, "Stickies by Streamline, CC BY 4.0")
        }
    }

    func testEveryIconHasAUniqueIdentifierAndKeepsItsCategoryOrder() {
        let ids = ClearframeIconCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "identifiers are the stored value; duplicates would collide")
        for icon in ClearframeIconCatalog.all {
            XCTAssertFalse(icon.markup.isEmpty)
            XCTAssertEqual(ClearframeIconCatalog.icon(id: icon.id)?.id, icon.id)
        }

        let categoryOrder = ClearframeIconCatalog.icons(style: .clearframe).map(\.category)
        let expectedOrder = ClearframeIconCategory.allCases.flatMap { category in
            Array(repeating: category, count: ClearframeIconCatalog.icons(in: category).count)
        }
        XCTAssertEqual(categoryOrder, expectedOrder, "the catalog runs category by category, in picker order")

        XCTAssertNil(ClearframeIconCatalog.icon(id: "no-such-icon"))
        XCTAssertNotNil(ClearframeIconCatalog.icon(id: ClearframeIconCatalog.defaultIconID))
    }

    // MARK: - The catalog, parsed

    func testEveryShippedIconParsesIntoSomethingDrawable() {
        for icon in ClearframeIconCatalog.all {
            guard let shapes = VectorPathParser.parse(icon.markup) else {
                XCTFail("\(icon.id) failed to parse: \(icon.markup)")
                continue
            }
            XCTAssertFalse(shapes.isEmpty, "\(icon.id) parsed into no shapes")
            let commands = shapes.flatMap(\.commands)
            XCTAssertGreaterThanOrEqual(commands.count, 1, "\(icon.id) parsed into no commands")
            let drawable = commands.contains { command in
                if case .close = command { return false }
                if case .move = command { return false }
                return true
            }
            XCTAssertTrue(drawable, "\(icon.id) is only moves and closes — it would draw nothing")
        }
    }

    func testEveryShippedIconStaysInsideItsSixteenPointBox() {
        // A broken relative-coordinate accumulator drifts; the artwork itself
        // sits inside 0…16 with the stroke's own half-width to spare, so a
        // small tolerance still catches drift of even one unit.
        let bounds = -0.25...16.25
        for icon in ClearframeIconCatalog.icons(style: .clearframe) {
            let commands = VectorPathParser.commands(icon.markup) ?? []
            XCTAssertFalse(commands.isEmpty, "\(icon.id) produced no commands")
            for point in Self.points(in: commands) {
                XCTAssertTrue(
                    bounds.contains(point.x) && bounds.contains(point.y),
                    "\(icon.id) draws outside its box at \(point)"
                )
            }
        }
    }

    /// A licensed set brings its own box, sometimes with a non-zero origin. The
    /// renderer is told that box rather than assuming one, so the artwork has
    /// to actually sit in the box each icon declares — otherwise it would be
    /// silently cropped or floated off-centre.
    func testEveryStickiesIconStaysInsideTheBoxItDeclares() {
        let stickies = ClearframeIconCatalog.all.filter { $0.style != .clearframe }
        XCTAssertEqual(stickies.count, 200)

        var worst = (id: "", overshoot: 0.0)
        for icon in stickies {
            let commands = VectorPathParser.commands(icon.markup) ?? []
            XCTAssertFalse(commands.isEmpty, "\(icon.id) produced no commands")
            for point in Self.drawnPoints(in: commands) {
                let overshoot = max(
                    icon.box.x - point.x,
                    point.x - (icon.box.x + icon.box.width),
                    icon.box.y - point.y,
                    point.y - (icon.box.y + icon.box.height)
                )
                if overshoot > worst.overshoot { worst = (icon.id, overshoot) }
            }
        }
        // Half a stroke: the artwork is drawn to its own edge and a stroke
        // centred there reaches half a unit past it. Anything beyond that would
        // be geometry the source clips away and this renderer would not.
        XCTAssertLessThanOrEqual(
            worst.overshoot,
            ClearframeIconStyle.stickiesPlain.strokeWidth / 2,
            "\(worst.id) draws \(worst.overshoot) units outside its declared box"
        )
    }

    /// The whole reason the licensed sets were worth the parser work: they name
    /// their own colours, which is exactly what the Clearframe set never does.
    func testStickiesArtworkCarriesItsOwnColours() {
        var seen = Set<String>()
        for icon in ClearframeIconCatalog.all where icon.style != .clearframe {
            guard let shapes = VectorPathParser.parse(icon.markup) else {
                XCTFail("\(icon.id) failed to parse")
                continue
            }
            XCTAssertTrue(
                shapes.contains { $0.colorHex != nil },
                "\(icon.id) named no colour of its own — a tint would be the only thing drawing it"
            )
            for shape in shapes { shape.colorHex.map { seen.insert($0) } }
        }
        // The five the plain set is drawn in plus the three the duo set uses,
        // with white shared. Anything else means a colour was misread.
        XCTAssertEqual(
            seen.sorted(),
            ["00034a", "231f20", "48eeff", "9bff00", "ff52a1", "ffe236", "ffffff"]
        )

        for icon in ClearframeIconCatalog.icons(style: .clearframe) {
            let shapes = VectorPathParser.parse(icon.markup) ?? []
            XCTAssertTrue(
                shapes.allSatisfy { $0.colorHex == nil },
                "\(icon.id) named a colour; the folder tint would stop reaching it"
            )
        }
    }

    func testEveryShippedIconIsStrokedExceptTheDeliberateSolidDots() {
        var filledIcons: [String] = []
        for icon in ClearframeIconCatalog.icons(style: .clearframe) {
            guard let shapes = VectorPathParser.parse(icon.markup) else {
                XCTFail("\(icon.id) failed to parse")
                continue
            }
            if shapes.contains(where: { $0.paint == .filled }) { filledIcons.append(icon.id) }
        }
        XCTAssertEqual(
            filledIcons,
            ["meeting", "camera", "tag", "percent", "cart", "share", "music", "podcast", "pet", "car", "target", "dot"],
            "only these icons carry a solid dot; stroking one would draw a ring instead"
        )
    }

    // MARK: - Path data

    func testKnownLinePathProducesExactlyThePointsItNames() {
        let commands = VectorPathParser.parsePathData("M2.75 12.75 L8 6.5 L13.25 12.75 Z")

        XCTAssertEqual(commands, [
            .move(CGPoint(x: 2.75, y: 12.75)),
            .line(CGPoint(x: 8, y: 6.5)),
            .line(CGPoint(x: 13.25, y: 12.75)),
            .close
        ])
    }

    func testHorizontalAndVerticalRunsWorkAbsoluteAndRelative() {
        XCTAssertEqual(
            VectorPathParser.parsePathData("M2 3 H10 V7"),
            [.move(CGPoint(x: 2, y: 3)), .line(CGPoint(x: 10, y: 3)), .line(CGPoint(x: 10, y: 7))]
        )
        XCTAssertEqual(
            VectorPathParser.parsePathData("M2 3 h8 v4"),
            [.move(CGPoint(x: 2, y: 3)), .line(CGPoint(x: 10, y: 3)), .line(CGPoint(x: 10, y: 7))],
            "a relative run lands where the absolute one does"
        )
        XCTAssertEqual(
            VectorPathParser.parsePathData("M2 3 h-1 v-1"),
            [.move(CGPoint(x: 2, y: 3)), .line(CGPoint(x: 1, y: 3)), .line(CGPoint(x: 1, y: 2))],
            "a negative sign separates numbers without whitespace"
        )
    }

    func testImplicitCoordinatePairsContinueAsLines() {
        XCTAssertEqual(
            VectorPathParser.parsePathData("M1 1 2 2 3 3"),
            [.move(CGPoint(x: 1, y: 1)), .line(CGPoint(x: 2, y: 2)), .line(CGPoint(x: 3, y: 3))],
            "extra pairs after a move are lines, not more moves"
        )
        XCTAssertEqual(
            VectorPathParser.parsePathData("m1 1 1 1 1 1"),
            [.move(CGPoint(x: 1, y: 1)), .line(CGPoint(x: 2, y: 2)), .line(CGPoint(x: 3, y: 3))],
            "and they stay relative when the move was"
        )
        XCTAssertEqual(
            VectorPathParser.parsePathData("M1 1 L2 2 3 3"),
            [.move(CGPoint(x: 1, y: 1)), .line(CGPoint(x: 2, y: 2)), .line(CGPoint(x: 3, y: 3))]
        )
    }

    func testMultipleSubpathsInOneAttributeEachCloseToTheirOwnStart() {
        let commands = VectorPathParser.parsePathData("M1 1 H3 Z M5 5 H7 Z")

        XCTAssertEqual(commands, [
            .move(CGPoint(x: 1, y: 1)),
            .line(CGPoint(x: 3, y: 1)),
            .close,
            .move(CGPoint(x: 5, y: 5)),
            .line(CGPoint(x: 7, y: 5)),
            .close
        ])
    }

    func testSmoothQuadraticReflectsThePreviousControlPoint() {
        // The set's wave: q then t, exactly as the artwork writes it.
        let commands = VectorPathParser.parsePathData("M2.75 6.5 q2.6 -2.6 5.25 0 t5.25 0")

        XCTAssertEqual(commands?.count, 3)
        guard case .quad(let firstEnd, let firstControl)? = commands?[1] else {
            return XCTFail("expected a quadratic")
        }
        XCTAssertEqual(firstControl.x, 5.35, accuracy: 0.0001)
        XCTAssertEqual(firstControl.y, 3.9, accuracy: 0.0001)
        XCTAssertEqual(firstEnd.x, 8, accuracy: 0.0001)
        XCTAssertEqual(firstEnd.y, 6.5, accuracy: 0.0001)

        guard case .quad(let secondEnd, let secondControl)? = commands?[2] else {
            return XCTFail("expected a smooth quadratic")
        }
        // The reflection of (5.35, 3.9) through the current point (8, 6.5).
        XCTAssertEqual(secondControl.x, 10.65, accuracy: 0.0001)
        XCTAssertEqual(secondControl.y, 9.1, accuracy: 0.0001)
        XCTAssertEqual(secondEnd.x, 13.25, accuracy: 0.0001)
        XCTAssertEqual(secondEnd.y, 6.5, accuracy: 0.0001)
    }

    func testSmoothQuadraticWithNoPreviousCurveUsesTheCurrentPoint() {
        let commands = VectorPathParser.parsePathData("M2 2 T6 6")

        guard case .quad(let end, let control)? = commands?[1] else {
            return XCTFail("expected a quadratic")
        }
        XCTAssertEqual(control, CGPoint(x: 2, y: 2), "with nothing to reflect, the current point is the control")
        XCTAssertEqual(end, CGPoint(x: 6, y: 6))
    }

    func testSmoothCubicReflectsThePreviousControlPoint() {
        let commands = VectorPathParser.parsePathData("M0 0 C1 1 2 2 3 3 S5 5 6 6")

        guard case .cubic(let end, let c1, let c2)? = commands?[2] else {
            return XCTFail("expected a smooth cubic")
        }
        XCTAssertEqual(c1, CGPoint(x: 4, y: 4), "the reflection of (2,2) through (3,3)")
        XCTAssertEqual(c2, CGPoint(x: 5, y: 5))
        XCTAssertEqual(end, CGPoint(x: 6, y: 6))
    }

    // MARK: - Arcs

    func testQuarterArcBecomesOneCubicThatEndsWhereTheArcEnds() {
        // A quarter turn of a unit circle centred on the origin.
        let commands = VectorPathParser.parsePathData("M1 0 A1 1 0 0 1 0 1")

        XCTAssertEqual(commands?.count, 2, "a 90-degree sweep needs exactly one cubic")
        guard case .cubic(let end, let c1, let c2)? = commands?[1] else {
            return XCTFail("expected a cubic")
        }
        XCTAssertEqual(end.x, 0, accuracy: 0.01)
        XCTAssertEqual(end.y, 1, accuracy: 0.01)
        // The standard 4/3·tan(θ/4) construction for a quarter circle.
        XCTAssertEqual(c1.x, 1, accuracy: 0.01)
        XCTAssertEqual(c1.y, 0.5523, accuracy: 0.01)
        XCTAssertEqual(c2.x, 0.5523, accuracy: 0.01)
        XCTAssertEqual(c2.y, 1, accuracy: 0.01)

        // The curve's own midpoint sits on the circle, which is the real test
        // of the approximation.
        let midpoint = Self.cubicPoint(from: CGPoint(x: 1, y: 0), c1: c1, c2: c2, to: end, t: 0.5)
        XCTAssertEqual((midpoint.x * midpoint.x + midpoint.y * midpoint.y).squareRoot(), 1, accuracy: 0.001)
    }

    func testLargeArcAndSweepFlagsPickDifferentPathsBetweenTheSameEndpoints() {
        let short = VectorPathParser.parsePathData("M1 0 A1 1 0 0 1 0 1") ?? []
        let long = VectorPathParser.parsePathData("M1 0 A1 1 0 1 1 0 1") ?? []
        let mirrored = VectorPathParser.parsePathData("M1 0 A1 1 0 0 0 0 1") ?? []

        XCTAssertEqual(short.count, 2)
        XCTAssertEqual(long.count, 4, "270 degrees needs three quarter-turn cubics")
        XCTAssertEqual(Self.points(in: short).last, Self.points(in: long).last, "both still end where the arc ends")

        // The short sweep bulges away from the centre; the mirrored one bulges
        // toward it. Their midpoints must therefore differ.
        let shortMid = Self.midpoint(of: short)
        let mirroredMid = Self.midpoint(of: mirrored)
        XCTAssertGreaterThan(
            (shortMid.x * shortMid.x + shortMid.y * shortMid.y).squareRoot(),
            (mirroredMid.x * mirroredMid.x + mirroredMid.y * mirroredMid.y).squareRoot()
        )
    }

    func testRelativeArcLandsWhereItsAbsoluteTwinDoes() {
        // The bag's handle, written relative in the artwork.
        let relative = VectorPathParser.parsePathData("M6.25 5.5 V4.75 a1.75 1.75 0 0 1 3.5 0 V5.5")
        let absolute = VectorPathParser.parsePathData("M6.25 5.5 V4.75 A1.75 1.75 0 0 1 9.75 4.75 V5.5")

        XCTAssertEqual(relative?.count, absolute?.count)
        let relativePoints = Self.points(in: relative ?? [])
        let absolutePoints = Self.points(in: absolute ?? [])
        XCTAssertEqual(relativePoints.count, absolutePoints.count)
        for (left, right) in zip(relativePoints, absolutePoints) {
            XCTAssertEqual(left.x, right.x, accuracy: 0.0001)
            XCTAssertEqual(left.y, right.y, accuracy: 0.0001)
        }
    }

    func testDegenerateArcsAreHandledTheWayTheSpecificationAsksFor() {
        XCTAssertEqual(
            VectorPathParser.parsePathData("M4 4 A2 2 0 0 1 4 4"),
            [.move(CGPoint(x: 4, y: 4))],
            "an arc that ends where it started draws nothing"
        )
        XCTAssertEqual(
            VectorPathParser.parsePathData("M4 4 A0 2 0 0 1 8 8"),
            [.move(CGPoint(x: 4, y: 4)), .line(CGPoint(x: 8, y: 8))],
            "a zero radius is a straight line"
        )
        // Radii too small to reach are scaled up, not refused: the arc still
        // lands on its stated endpoint.
        let stretched = VectorPathParser.parsePathData("M0 0 A1 1 0 0 1 4 0")
        XCTAssertEqual(Self.points(in: stretched ?? []).last?.x ?? .nan, 4, accuracy: 0.0001)
        XCTAssertEqual(Self.points(in: stretched ?? []).last?.y ?? .nan, 0, accuracy: 0.0001)
    }

    func testRotatedArcRespectsItsXAxisRotation() {
        let upright = VectorPathParser.parsePathData("M0 0 A4 2 0 0 1 4 2") ?? []
        let rotated = VectorPathParser.parsePathData("M0 0 A4 2 90 0 1 4 2") ?? []

        XCTAssertEqual(Self.points(in: upright).last, Self.points(in: rotated).last, "same endpoints either way")
        XCTAssertNotEqual(
            Self.midpoint(of: upright),
            Self.midpoint(of: rotated),
            "turning the ellipse on its side changes the curve between them"
        )
    }

    func testArcFlagsMayBePackedAgainstTheirNeighbours() {
        let spaced = VectorPathParser.parsePathData("M6.25 5.5 a1.75 1.75 0 0 1 3.5 0")
        let packed = VectorPathParser.parsePathData("M6.25 5.5a1.75 1.75 0 013.5 0")

        XCTAssertNotNil(packed)
        XCTAssertEqual(packed, spaced, "single-character flags need no separator")
    }

    // MARK: - Elements

    func testCircleElementBecomesOneEllipseCommand() {
        let commands = VectorPathParser.commands(#"<circle cx="8" cy="9.1" r="1.6"/>"#)

        XCTAssertEqual(commands, [.ellipse(center: CGPoint(x: 8, y: 9.1), radii: CGSize(width: 1.6, height: 1.6))])
    }

    func testEllipseElementKeepsItsTwoRadii() {
        let commands = VectorPathParser.commands(#"<ellipse cx="8" cy="8" rx="2" ry="5.25"/>"#)

        XCTAssertEqual(commands, [.ellipse(center: CGPoint(x: 8, y: 8), radii: CGSize(width: 2, height: 5.25))])
    }

    func testSolidDotIsParsedAsFilledAndAPlainCircleAsStroked() {
        let dot = VectorPathParser.parse(#"<circle cx="8" cy="8" r="1.25" fill="currentColor" stroke="none"/>"#)
        let ring = VectorPathParser.parse(#"<circle cx="8" cy="8" r="5.25"/>"#)

        XCTAssertEqual(dot?.first?.paint, .filled)
        XCTAssertEqual(ring?.first?.paint, .stroked)
    }

    func testEveryElementOfAMultiPartIconIsKept() {
        let markup = #"<path d="M2.75 12.75 V6.5 H11.75 Z"/><path d="M5.75 6.5 V4.75 H10.25 V6.5"/>"#

        XCTAssertEqual(VectorPathParser.parse(markup)?.count, 2)
    }

    // MARK: - Groups, inheritance, and definitions

    func testAGroupHandsItsPaintToChildrenThatNameNone() {
        let markup = ##"<g fill="none" stroke="#231f20"><path d="M1 1 H5"/><path stroke="#fff" d="M1 3 H5"/></g>"##
        guard let shapes = VectorPathParser.parse(markup) else { return XCTFail("did not parse") }

        XCTAssertEqual(shapes.count, 2)
        XCTAssertEqual(shapes[0].paint, .stroked)
        XCTAssertEqual(shapes[0].colorHex, "231f20", "inherited from the group")
        XCTAssertEqual(shapes[1].colorHex, "ffffff", "its own stroke wins, and #fff expands")
    }

    /// An element that both fills and strokes becomes two shapes, in that
    /// order. Collapsing it to one would lose whichever paint came second.
    func testAnElementThatFillsAndStrokesBecomesBothInDrawingOrder() {
        let markup = ##"<g stroke="#00034a"><path fill="#9bff00" d="M1 1 H5 V5 Z"/></g>"##
        guard let shapes = VectorPathParser.parse(markup) else { return XCTFail("did not parse") }

        XCTAssertEqual(shapes.count, 2)
        XCTAssertEqual(shapes[0].paint, .filled)
        XCTAssertEqual(shapes[0].colorHex, "9bff00")
        XCTAssertEqual(shapes[1].paint, .stroked)
        XCTAssertEqual(shapes[1].colorHex, "00034a")
        XCTAssertEqual(shapes[0].commands, shapes[1].commands, "one geometry, painted twice")
    }

    func testEvenOddWindingSurvivesOnlyWhereTheArtworkAsksForIt() {
        let evenOdd = VectorPathParser.parse(##"<path fill="#fff" fill-rule="evenodd" d="M1 1 H5 V5 Z"/>"##)
        let nonZero = VectorPathParser.parse(##"<path fill="#fff" d="M1 1 H5 V5 Z"/>"##)

        XCTAssertEqual(evenOdd?.first?.usesEvenOddFill, true)
        XCTAssertEqual(nonZero?.first?.usesEvenOddFill, false)
    }

    func testUseDrawsTheDefinitionItReferences() {
        let markup = """
        <defs><path id="mark" fill="#fff" d="M1 1 H5"/></defs>\
        <g stroke="#00034a"><use href="#mark"/></g>
        """
        guard let shapes = VectorPathParser.parse(markup) else { return XCTFail("did not parse") }

        // The definition's own fill, then the stroke it inherits through `use`.
        XCTAssertEqual(shapes.count, 2)
        XCTAssertEqual(shapes[0].colorHex, "ffffff")
        XCTAssertEqual(shapes[1].colorHex, "00034a")
    }

    /// `<defs>` may be declared after the `<use>` that needs it, which is how
    /// the shipped artwork is written.
    func testUseFindsADefinitionDeclaredAfterIt() {
        let markup = ##"<g stroke="#fff"><use href="#late"/></g><defs><path id="late" d="M1 1 H5"/></defs>"##

        XCTAssertEqual(VectorPathParser.parse(markup)?.count, 1)
    }

    func testDefinitionsAndClipsDrawNothingWhereTheySit() {
        // A clip to the whole box changes no pixel, and a definition is drawn
        // only where it is used — so an icon of nothing but these is refused.
        XCTAssertNil(VectorPathParser.parse(#"<defs><path id="a" d="M1 1 H5"/></defs>"#))
        XCTAssertNil(VectorPathParser.parse(#"<clipPath id="c"><path d="M0 0h40v40H0z"/></clipPath>"#))
    }

    func testMalformedNestingIsRefusedRatherThanGuessed() {
        XCTAssertNil(VectorPathParser.parse(#"<g fill="none"><path d="M1 1 H5"/>"#), "a group that never closes")
        XCTAssertNil(VectorPathParser.parse(#"<g fill="none"><path d="M1 1 H5"/></svg>"#), "closed by the wrong tag")
        XCTAssertNil(VectorPathParser.parse(#"<g fill="none"><rect width="2" height="2"/></g>"#), "unknown element inside a group")
        XCTAssertNil(VectorPathParser.parse(##"<use href="#missing"/>"##), "a reference to nothing")
        XCTAssertNil(VectorPathParser.parse(#"<g fill="none"></g>"#), "a group that draws nothing")
    }

    // MARK: - Colour

    func testAFolderDrawsInMintUntilItChoosesAnotherTint() {
        let untouched = BookmarkFolderRecord(title: "Reading", iconID: "book", parentID: nil)

        XCTAssertNil(untouched.colorID, "a folder that never chose a tint stores nothing")
        XCTAssertEqual(untouched.resolvedColor, .mint, "and draws in the set's own accent")
    }

    func testChoosingATintKeepsItAndRejectsOneTheSetDoesNotHave() {
        let amber = BookmarkFolderRecord(title: "Invoices", iconID: "receipt", colorID: "amber", parentID: nil)
        let nonsense = BookmarkFolderRecord(title: "Odd", iconID: "folder", colorID: "chartreuse", parentID: nil)

        XCTAssertEqual(amber.resolvedColor, .amber)
        XCTAssertNil(nonsense.colorID, "an unknown tint is refused rather than stored")
        XCTAssertEqual(nonsense.resolvedColor, .mint)
    }

    func testTheFourTintsAreTheOnesTheArtworkWasDrawnAgainst() {
        XCTAssertEqual(ClearframeIconColor.allCases.map(\.rawValue), ["mint", "grey", "amber", "blue"])
        XCTAssertEqual(ClearframeIconColor.mint.hex, "66DB7D")
        XCTAssertEqual(ClearframeIconColor.grey.hex, "8A8A94")
        XCTAssertEqual(ClearframeIconColor.amber.hex, "E9B04C")
        XCTAssertEqual(ClearframeIconColor.blue.hex, "5CA0F2")

        let mint = ClearframeIconColor.mint.components
        XCTAssertEqual(mint.red, 102.0 / 255, accuracy: 0.001)
        XCTAssertEqual(mint.green, 219.0 / 255, accuracy: 0.001)
        XCTAssertEqual(mint.blue, 125.0 / 255, accuracy: 0.001)
    }

    func testAFolderSavedBeforeTintsExistedStillDecodes() throws {
        let legacy = Data("""
        {"id":"\(UUID().uuidString)","title":"Old","emoji":"\u{1F3A8}","createdAt":0}
        """.utf8)

        let folder = try JSONDecoder().decode(BookmarkFolderRecord.self, from: legacy)

        XCTAssertNil(folder.colorID)
        XCTAssertEqual(folder.resolvedColor, .mint)
        XCTAssertEqual(folder.resolvedIconID, "palette", "and still resolves its old emoji")
    }

    func testEditingAFolderCanChangeItsTintWithoutTouchingItsIcon() {
        var collection = BookmarkCollection()
        let folder = collection.createFolder(title: "Work", iconID: "briefcase", parentID: nil)
        let id = try! XCTUnwrap(folder).id

        collection.updateFolder(id: id, title: "Work", iconID: "briefcase", colorID: "blue")

        XCTAssertEqual(collection.folder(id: id)?.resolvedColor, .blue)
        XCTAssertEqual(collection.folder(id: id)?.resolvedIconID, "briefcase")
    }

    // MARK: - Refusals

    func testMalformedMarkupIsRefusedRatherThanGuessedAt() {
        XCTAssertNil(VectorPathParser.parsePathData("M1 1 X2 2"), "an unknown command is a refusal")
        XCTAssertNil(VectorPathParser.parsePathData("M1 1 L2"), "a truncated coordinate pair is a refusal")
        XCTAssertNil(VectorPathParser.parsePathData("2 2 L3 3"), "path data must start with a command")
        XCTAssertNil(VectorPathParser.parsePathData(""), "empty data draws nothing")
        XCTAssertNil(VectorPathParser.parse(""), "empty markup draws nothing")
        XCTAssertNil(VectorPathParser.parse("<rect x=\"1\" y=\"1\" width=\"2\" height=\"2\"/>"), "unknown element")
        XCTAssertNil(VectorPathParser.parse(#"<circle cx="8" cy="8"/>"#), "a circle without a radius")
        XCTAssertNil(VectorPathParser.parse(#"<circle cx="8" cy="8" r="nope"/>"#), "a radius that is not a number")
        XCTAssertNil(VectorPathParser.parse(#"<path/>"#), "a path without any data")
        XCTAssertNil(VectorPathParser.parse(#"<path d="M1 1 H2">"#), "an element that is never closed")
        XCTAssertNil(VectorPathParser.parse(#"text<path d="M1 1 H2"/>"#), "loose text between elements")
    }

    // MARK: - Helpers

    /// Points that are actually drawn, curves included.
    ///
    /// `points(in:)` returns control points too, which is what you want when
    /// checking a coordinate accumulator for drift but not when asking where
    /// the ink lands: a bézier stays inside the hull of its controls and can
    /// sit well within them. Sampling each curve answers the second question.
    private static func drawnPoints(in commands: [VectorPathCommand], samples: Int = 12) -> [CGPoint] {
        var results: [CGPoint] = []
        var current = CGPoint.zero
        for command in commands {
            switch command {
            case .move(let point), .line(let point):
                results.append(point)
                current = point
            case .quad(let to, let control):
                for step in 0...samples {
                    let t = Double(step) / Double(samples)
                    let u = 1 - t
                    results.append(
                        CGPoint(
                            x: u * u * current.x + 2 * u * t * control.x + t * t * to.x,
                            y: u * u * current.y + 2 * u * t * control.y + t * t * to.y
                        )
                    )
                }
                current = to
            case .cubic(let to, let c1, let c2):
                for step in 0...samples {
                    let t = Double(step) / Double(samples)
                    let u = 1 - t
                    results.append(
                        CGPoint(
                            x: u * u * u * current.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * to.x,
                            y: u * u * u * current.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * to.y
                        )
                    )
                }
                current = to
            case .close:
                continue
            case .ellipse(let center, let radii):
                results.append(CGPoint(x: center.x - radii.width, y: center.y - radii.height))
                results.append(CGPoint(x: center.x + radii.width, y: center.y + radii.height))
            }
        }
        return results
    }

    private static func points(in commands: [VectorPathCommand]) -> [CGPoint] {
        commands.flatMap { command -> [CGPoint] in
            switch command {
            case .move(let point), .line(let point):
                return [point]
            case .quad(let to, let control):
                return [control, to]
            case .cubic(let to, let c1, let c2):
                return [c1, c2, to]
            case .close:
                return []
            case .ellipse(let center, let radii):
                return [
                    CGPoint(x: center.x - radii.width, y: center.y - radii.height),
                    CGPoint(x: center.x + radii.width, y: center.y + radii.height)
                ]
            }
        }
    }

    /// The point halfway along a single-cubic run, for comparing two curves
    /// that share endpoints.
    private static func midpoint(of commands: [VectorPathCommand]) -> CGPoint {
        var current = CGPoint.zero
        var results: [CGPoint] = []
        for command in commands {
            switch command {
            case .move(let point):
                current = point
            case .cubic(let to, let c1, let c2):
                results.append(cubicPoint(from: current, c1: c1, c2: c2, to: to, t: 0.5))
                current = to
            default:
                break
            }
        }
        return results[results.count / 2]
    }

    private static func cubicPoint(
        from start: CGPoint,
        c1: CGPoint,
        c2: CGPoint,
        to end: CGPoint,
        t: Double
    ) -> CGPoint {
        let inverse = 1 - t
        let a = inverse * inverse * inverse
        let b = 3 * inverse * inverse * t
        let c = 3 * inverse * t * t
        let d = t * t * t
        return CGPoint(
            x: a * start.x + b * c1.x + c * c2.x + d * end.x,
            y: a * start.y + b * c1.y + c * c2.y + d * end.y
        )
    }
}

/// The folder record's side of the change: an icon is added to folders without
/// taking anything away from the ones that already exist.
final class BookmarkFolderIconTests: XCTestCase {

    func testFolderSavedBeforeIconsDecodesWithoutOneAndResolvesFromItsEmoji() throws {
        let saved = """
            {
                "id": "6C4E7C1E-7C1E-4C1E-8C1E-9C1E0C1E1C1E",
                "title": "Web Design",
                "emoji": "🎨",
                "createdAt": 745000000
            }
            """
        let folder = try JSONDecoder().decode(BookmarkFolderRecord.self, from: Data(saved.utf8))

        XCTAssertNil(folder.iconID, "an old record chose no icon, and none is invented for it")
        XCTAssertEqual(folder.emoji, "🎨", "the reader's own emoji is kept exactly as it was saved")
        XCTAssertEqual(folder.resolvedIconID, "palette")
        XCTAssertNil(folder.parentID)
    }

    func testChosenIconSurvivesAJSONRoundTripAndOutranksTheEmoji() throws {
        let folder = BookmarkFolderRecord(title: "Reading", emoji: "🎨", iconID: "library")
        let data = try JSONEncoder().encode(folder)
        let restored = try JSONDecoder().decode(BookmarkFolderRecord.self, from: data)

        XCTAssertEqual(restored, folder)
        XCTAssertEqual(restored.iconID, "library")
        XCTAssertEqual(restored.resolvedIconID, "library", "an explicit choice wins over the legacy emoji")
    }

    func testUnknownOrBlankIconIDFallsBackInsteadOfLeavingAHole() {
        let fromLaterBuild = BookmarkFolderRecord(title: "Future", emoji: "📷", iconID: "hologram")
        XCTAssertEqual(fromLaterBuild.resolvedIconID, "camera", "an unknown icon still has the emoji to fall back on")

        let blank = BookmarkFolderRecord(title: "Blank", emoji: "🐦", iconID: "   ")
        XCTAssertNil(blank.iconID, "a blank choice is no choice")
        XCTAssertEqual(blank.resolvedIconID, ClearframeIconCatalog.defaultIconID)

        XCTAssertEqual(
            ClearframeIconCatalog.resolvedIconID(iconID: "nothing-like-this", legacyEmoji: "🦄"),
            "folder",
            "an unmapped emoji and an unknown icon both land on the plain folder"
        )
    }

    func testLegacyEmojiMapCoversEveryEmojiTheOldPickerOffered() {
        // The eight buttons the old folder editor showed, plus its default.
        let offered = ["📁", "🎨", "💻", "🛍️", "📚", "✈️", "💡", "❤️"]
        let expected = ["folder", "palette", "terminal", "bag", "library", "plane", "bolt", "heart"]

        for (emoji, iconID) in zip(offered, expected) {
            XCTAssertEqual(ClearframeIconCatalog.iconID(forLegacyEmoji: emoji), iconID, "\(emoji) lost its meaning")
        }

        // Emoji people typed in by hand, which the old editor also accepted.
        let handTyped = [
            "📷": "camera", "🎵": "music", "🏠": "house", "⭐": "star", "🔒": "lock",
            "💼": "briefcase", "📰": "article", "🛒": "cart", "🌍": "globe", "🔧": "gear"
        ]
        for (emoji, iconID) in handTyped {
            XCTAssertEqual(ClearframeIconCatalog.iconID(forLegacyEmoji: emoji), iconID, "\(emoji) lost its meaning")
        }

        XCTAssertEqual(ClearframeIconCatalog.iconID(forLegacyEmoji: "🦄"), "folder", "anything unmapped is a folder")
        XCTAssertEqual(ClearframeIconCatalog.iconID(forLegacyEmoji: ""), "folder")
        XCTAssertEqual(
            ClearframeIconCatalog.iconID(forLegacyEmoji: "❤"),
            ClearframeIconCatalog.iconID(forLegacyEmoji: "❤️"),
            "a variation selector must not change the answer"
        )
    }

    func testEveryLegacyEmojiPointsAtAnIconTheCatalogActuallyHas() {
        // Every emoji in the map resolves to something drawable; a typo in the
        // table would otherwise show as a missing icon only at render time.
        let emojiToCheck = ["📁", "🎨", "💻", "🛍️", "📚", "✈️", "💡", "❤️", "📷", "🎵", "🏠", "⭐",
                            "🔒", "💼", "📰", "🛒", "🌍", "🔧", "📖", "🔖", "📝", "📅", "✅", "📦",
                            "🗄️", "🔑", "🐛", "⚙️", "📍", "🎫", "🧳", "🏨", "🗺️", "👤", "👥", "💬",
                            "✉️", "📧", "📞", "🔔", "▶️", "🎬", "🎥", "🎧", "🎤", "🖼️", "📊", "🌱",
                            "🍽️", "🩺", "🏋️", "🐶", "🚗", "☕", "☂️", "🧺", "🚩", "⚡", "🛡️", "🎯",
                            "➡️", "💎", "🌳", "⛰️", "🌊", "🌙", "☀️", "🍃", "🔥", "🧪", "📏", "✂️",
                            "⌛", "🏅", "💊", "🏆", "🗑️", "🔄", "🏷️", "💰", "💳", "🧾"]
        for emoji in emojiToCheck {
            let iconID = ClearframeIconCatalog.iconID(forLegacyEmoji: emoji)
            XCTAssertNotNil(ClearframeIconCatalog.icon(id: iconID), "\(emoji) maps to a missing icon: \(iconID)")
        }
    }

    func testCreatingAndRenamingAFolderKeepsItsIconWithoutTouchingItsEmoji() throws {
        var collection = BookmarkCollection()
        let created = try XCTUnwrap(collection.createFolder(title: "Work", iconID: "briefcase", parentID: nil))

        XCTAssertEqual(created.iconID, "briefcase")
        XCTAssertEqual(created.resolvedIconID, "briefcase")

        collection.updateFolder(id: created.id, title: "Client work", iconID: "calendar")
        let renamed = try XCTUnwrap(collection.folder(id: created.id))

        XCTAssertEqual(renamed.title, "Client work")
        XCTAssertEqual(renamed.iconID, "calendar")
        XCTAssertEqual(renamed.emoji, "📁", "the legacy field is left alone rather than rewritten")

        collection.updateFolder(id: created.id, title: "   ", iconID: "star")
        XCTAssertEqual(collection.folder(id: created.id)?.title, "Client work", "an empty name changes nothing")
    }
}
