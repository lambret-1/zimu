import XCTest
@testable import SuperResApp

final class MaskProcessorFeatherTests: XCTestCase {
    private func stroke(_ points: [NormalizedPoint]) -> MaskStroke {
        MaskStroke(tool: .brush, brushWidth: 0.1, points: points)
    }

    func testFeatherWeightsKeepMaskInteriorOpaqueAndFarCornerClear() throws {
        let result = try MaskProcessor.rasterizeMask(
            strokes: [stroke([
                NormalizedPoint(x: 0.4, y: 0.5),
                NormalizedPoint(x: 0.6, y: 0.5)
            ])],
            targetSize: CGSize(width: 64, height: 64),
            expandPixels: 0,
            featherPixels: 2
        )
        XCTAssertEqual(result.width, 64)
        XCTAssertEqual(result.height, 64)
        XCTAssertEqual(result.binary.count, 64 * 64)
        XCTAssertEqual(result.softWeights.count, 64 * 64)
        XCTAssertEqual(result.softWeights[32 * 64 + 32], 255)
        XCTAssertEqual(result.softWeights[0], 0)
    }

    func testZeroFeatherMatchesBinaryMask() throws {
        let result = try MaskProcessor.rasterizeMask(
            strokes: [stroke([NormalizedPoint(x: 0.5, y: 0.5)])],
            targetSize: CGSize(width: 32, height: 32),
            expandPixels: 1,
            featherPixels: 0
        )
        XCTAssertEqual(result.softWeights, [UInt8](result.binary))
    }

    func testFeatherProducesIntermediateBoundaryWeights() throws {
        let result = try MaskProcessor.rasterizeMask(
            strokes: [stroke([NormalizedPoint(x: 0.5, y: 0.5)])],
            targetSize: CGSize(width: 64, height: 64),
            expandPixels: 0,
            featherPixels: 2
        )
        XCTAssertTrue(result.softWeights.contains { $0 > 0 && $0 < 255 })
    }
}
