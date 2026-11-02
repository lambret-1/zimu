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

    func testDetectedRegionsRasterizeIntoCoarseMask() throws {
        let region = DetectedSubtitleRegion(
            rect: NormalizedRect(
                origin: NormalizedPoint(x: 0.25, y: 0.75),
                width: 0.5,
                height: 0.1
            ),
            confidence: 0.95,
            source: .vision
        )
        let mask = try MaskProcessor.rasterize(
            regions: [region],
            targetSize: CGSize(width: 100, height: 100),
            expandPixels: 0
        )
        XCTAssertEqual(mask[80 * 100 + 50], 255)
        XCTAssertEqual(mask[20 * 100 + 50], 0)
    }

    func testManualEraserCanRemovePixelsFromAutomaticBaseMask() throws {
        let base = Data(repeating: 255, count: 64 * 64)
        let eraser = stroke(
            tool: .eraser,
            width: 0.2,
            points: [NormalizedPoint(x: 0.5, y: 0.5)]
        )
        let result = try MaskProcessor.rasterize(
            strokes: [eraser],
            targetSize: CGSize(width: 64, height: 64),
            expandPixels: 0,
            baseMask: base
        )
        XCTAssertEqual(result[32 * 64 + 32], 0)
        XCTAssertEqual(result[0], 255)
    }

    func testAutomaticMaskCanBeUsedWithoutManualStrokes() throws {
        let base = Data(repeating: 255, count: 32 * 32)
        let result = try MaskProcessor.rasterize(
            strokes: [],
            targetSize: CGSize(width: 32, height: 32),
            expandPixels: 0,
            baseMask: base
        )
        XCTAssertEqual(result, base)
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
