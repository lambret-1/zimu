import XCTest
@testable import SuperResApp

final class MaskProcessorTests: XCTestCase {
    private func stroke(
        tool: MaskBrushTool = .brush,
        width: Double = 0.1,
        points: [NormalizedPoint]
    ) -> MaskStroke {
        MaskStroke(tool: tool, brushWidth: width, points: points)
    }

    func testEmptyStrokesAreRejected() {
        XCTAssertThrowsError(
            try MaskProcessor.rasterize(strokes: [], targetSize: CGSize(width: 64, height: 64))
        )
    }

    func testSinglePointProducesNonEmptyMask() throws {
        let mask = try MaskProcessor.rasterize(
            strokes: [stroke(points: [NormalizedPoint(x: 0.5, y: 0.5)])],
            targetSize: CGSize(width: 64, height: 64),
            expandPixels: 0
        )
        XCTAssertEqual(mask.count, 64 * 64)
        XCTAssertEqual(mask[32 * 64 + 32], 255)
        XCTAssertEqual(mask[0], 0)
    }

    func testMaskIsBinary() throws {
        let line = stroke(points: [
            NormalizedPoint(x: 0.2, y: 0.5),
            NormalizedPoint(x: 0.8, y: 0.5)
        ])
        let mask = try MaskProcessor.rasterize(
            strokes: [line],
            targetSize: CGSize(width: 64, height: 64),
            expandPixels: 0
        )
        XCTAssertTrue(mask.allSatisfy { $0 == 0 || $0 == 255 })
        XCTAssertTrue(mask.contains(255))
    }

    func testExpansionIncreasesCoverage() throws {
        let dot = stroke(points: [NormalizedPoint(x: 0.5, y: 0.5)])
        let size = CGSize(width: 64, height: 64)
        let plain = try MaskProcessor.rasterize(strokes: [dot], targetSize: size, expandPixels: 0)
        let expanded = try MaskProcessor.rasterize(strokes: [dot], targetSize: size, expandPixels: 2)
        XCTAssertGreaterThan(expanded.filter { $0 == 255 }.count, plain.filter { $0 == 255 }.count)
    }

    func testEraserClearsEarlierBrushCoverage() throws {
        let point = [NormalizedPoint(x: 0.5, y: 0.5)]
        let brush = stroke(width: 0.2, points: point)
        let eraser = stroke(tool: .eraser, width: 0.2, points: point)
        let mask = try MaskProcessor.rasterize(
            strokes: [brush, eraser],
            targetSize: CGSize(width: 64, height: 64),
            expandPixels: 0
        )
        XCTAssertEqual(mask.filter { $0 == 255 }.count, 0)
    }

    func testRejectsInvalidTargetSize() {
        XCTAssertThrowsError(
            try MaskProcessor.rasterize(
                strokes: [stroke(points: [NormalizedPoint(x: 0.5, y: 0.5)])],
                targetSize: .zero
            )
        )
    }
}
