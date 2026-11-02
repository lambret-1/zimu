import CoreGraphics
import XCTest
@testable import SuperResApp

final class SubtitleRegionDetectorTests: XCTestCase {
    private func region(
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        confidence: Double = 0.9
    ) -> DetectedSubtitleRegion {
        DetectedSubtitleRegion(
            rect: NormalizedRect(
                origin: NormalizedPoint(x: x, y: y),
                width: width,
                height: height
            ),
            confidence: confidence,
            source: .vision
        )
    }

    func testVisionBoundingBoxConvertsBottomLeftToTopLeft() throws {
        let rect = try XCTUnwrap(
            SubtitleRegionDetector.normalizedRect(
                fromVisionBoundingBox: CGRect(x: 0.1, y: 0.7, width: 0.4, height: 0.1)
            )
        )
        XCTAssertEqual(rect.origin.x, 0.1, accuracy: 0.0001)
        XCTAssertEqual(rect.origin.y, 0.2, accuracy: 0.0001)
        XCTAssertEqual(rect.width, 0.4, accuracy: 0.0001)
        XCTAssertEqual(rect.height, 0.1, accuracy: 0.0001)
    }

    func testFiltersTextOutsideBottomSubtitleBand() {
        let results = SubtitleRegionDetector.filterAndMerge([
            region(x: 0.1, y: 0.12, width: 0.3, height: 0.04),
            region(x: 0.2, y: 0.82, width: 0.3, height: 0.04)
        ])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].rect.origin.y, 0.82, accuracy: 0.0001)
    }

    func testFiltersLowConfidenceCandidates() {
        let results = SubtitleRegionDetector.filterAndMerge([
            region(x: 0.1, y: 0.8, width: 0.2, height: 0.05, confidence: 0.4)
        ])
        XCTAssertTrue(results.isEmpty)
    }

    func testMergesHorizontallyAdjacentWordBoxes() {
        let results = SubtitleRegionDetector.filterAndMerge([
            region(x: 0.1, y: 0.8, width: 0.2, height: 0.05),
            region(x: 0.32, y: 0.8, width: 0.2, height: 0.05)
        ])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].rect.origin.x, 0.1, accuracy: 0.0001)
        XCTAssertEqual(results[0].rect.width, 0.42, accuracy: 0.0001)
    }

    func testMergesVerticallyAdjacentBoxesWithoutIntersection() {
        let results = SubtitleRegionDetector.filterAndMerge([
            region(x: 0.2, y: 0.78, width: 0.5, height: 0.04),
            region(x: 0.2, y: 0.83, width: 0.5, height: 0.04)
        ])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].rect.height, 0.09, accuracy: 0.0001)
    }

    func testMergeIsTransitive() {
        let results = SubtitleRegionDetector.filterAndMerge([
            region(x: 0.1, y: 0.8, width: 0.15, height: 0.04),
            region(x: 0.27, y: 0.8, width: 0.15, height: 0.04),
            region(x: 0.44, y: 0.8, width: 0.15, height: 0.04)
        ])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].rect.maxX, 0.59, accuracy: 0.0001)
    }

    func testKeepsSeparatedSubtitleRegionsSeparate() {
        let results = SubtitleRegionDetector.filterAndMerge([
            region(x: 0.05, y: 0.8, width: 0.2, height: 0.04),
            region(x: 0.6, y: 0.8, width: 0.2, height: 0.04)
        ])
        XCTAssertEqual(results.count, 2)
    }

    func testEmptyCandidatesReturnEmptyResult() {
        XCTAssertTrue(SubtitleRegionDetector.filterAndMerge([]).isEmpty)
    }
}
