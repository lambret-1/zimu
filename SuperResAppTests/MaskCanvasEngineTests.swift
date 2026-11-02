import XCTest
@testable import SuperResApp

final class MaskCanvasEngineTests: XCTestCase {
    func testNormalizedPointClampsToUnitSquare() {
        let point = MaskCanvasEngine.normalizedPoint(
            from: CGPoint(x: 200, y: -50),
            in: CGSize(width: 100, height: 100)
        )
        XCTAssertEqual(point.x, 1, accuracy: 1e-9)
        XCTAssertEqual(point.y, 0, accuracy: 1e-9)
    }

    func testShouldAppendRejectsTooClosePoints() {
        let last = NormalizedPoint(x: 0.5, y: 0.5)
        let close = NormalizedPoint(x: 0.5005, y: 0.5005)
        XCTAssertFalse(MaskCanvasEngine.shouldAppend(close, after: last))
    }

    func testShouldAppendAcceptsFarAndFirstPoints() {
        let last = NormalizedPoint(x: 0.5, y: 0.5)
        XCTAssertTrue(MaskCanvasEngine.shouldAppend(
            NormalizedPoint(x: 0.51, y: 0.5), after: last
        ))
        XCTAssertTrue(MaskCanvasEngine.shouldAppend(last, after: nil))
    }

    func testSmoothingPreservesEndpointsAndCount() {
        let points = [
            NormalizedPoint(x: 0, y: 0),
            NormalizedPoint(x: 0.1, y: 0.3),
            NormalizedPoint(x: 0.2, y: 0.1),
            NormalizedPoint(x: 0.3, y: 0.4)
        ]
        let result = MaskCanvasEngine.smoothed(points)
        XCTAssertEqual(result.count, points.count)
        XCTAssertEqual(result.first, points.first)
        XCTAssertEqual(result.last, points.last)
        XCTAssertNotEqual(result[1], points[1])
    }

    func testSmoothingShortInputIsUnchanged() {
        let points = [
            NormalizedPoint(x: 0.1, y: 0.2),
            NormalizedPoint(x: 0.3, y: 0.4)
        ]
        XCTAssertEqual(MaskCanvasEngine.smoothed(points), points)
        XCTAssertTrue(MaskCanvasEngine.smoothed([]).isEmpty)
    }

    func testBrushWidthRoundTripUsesCanvasShortSide() {
        let size = CGSize(width: 400, height: 200)
        let normalized = MaskCanvasEngine.normalizedBrushWidth(ptWidth: 20, canvasSize: size)
        XCTAssertEqual(normalized, 0.1, accuracy: 1e-9)
        XCTAssertEqual(
            MaskCanvasEngine.ptWidth(for: normalized, canvasSize: size),
            20,
            accuracy: 1e-6
        )
    }

    func testBrushWidthHandlesInvalidCanvasAndWidth() {
        XCTAssertEqual(
            MaskCanvasEngine.normalizedBrushWidth(ptWidth: 20, canvasSize: .zero),
            0
        )
        XCTAssertEqual(
            MaskCanvasEngine.normalizedBrushWidth(
                ptWidth: .infinity,
                canvasSize: CGSize(width: 100, height: 100)
            ),
            0
        )
    }
}
