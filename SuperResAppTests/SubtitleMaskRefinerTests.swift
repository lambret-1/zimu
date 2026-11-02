import XCTest
@testable import SuperResApp

final class SubtitleMaskRefinerTests: XCTestCase {
    private let width = 200
    private let height = 200

    private func makeSyntheticSubtitleImage() -> Data {
        var data = Data(count: width * height * 4)
        data.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }

            for y in 0..<height {
                for x in 0..<width {
                    let index = (y * width + x) * 4
                    base[index] = 40
                    base[index + 1] = 40
                    base[index + 2] = 200
                    base[index + 3] = 255

                    if (60...140).contains(x), (60...80).contains(y) {
                        let isBorder = x < 65 || x > 135 || y < 65 || y > 75
                        let value: UInt8 = isBorder ? 10 : 255
                        base[index] = value
                        base[index + 1] = value
                        base[index + 2] = value
                    }
                }
            }
        }
        return data
    }

    private func makeCoarseMask() -> Data {
        var data = Data(count: width * height)
        data.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }
            for y in 50..<90 {
                for x in 50..<150 {
                    base[y * width + x] = 255
                }
            }
        }
        return data
    }

    func testRefineExtractsTextAndCoversBorder() throws {
        let refined = try SubtitleMaskRefiner.refine(
            imageBGRA: makeSyntheticSubtitleImage(),
            coarseMask: makeCoarseMask(),
            width: width,
            height: height,
            options: .init(dilatePixels: 3, featherPixels: 0)
        )

        XCTAssertEqual(refined.count, width * height)
        XCTAssertGreaterThan(refined[70 * width + 100], 0, "白字核心未提取")
        XCTAssertGreaterThan(refined[70 * width + 62], 0, "黑边未被膨胀覆盖")
        XCTAssertEqual(refined[55 * width + 55], 0, "粗框内无字区域未被剔除")

        let refinedCount = refined.filter { $0 > 0 }.count
        XCTAssertLessThan(refinedCount, width * height / 6)
    }

    func testEmptyCoarseMaskReturnsEmptyMask() throws {
        let emptyMask = Data(count: width * height)
        let refined = try SubtitleMaskRefiner.refine(
            imageBGRA: makeSyntheticSubtitleImage(),
            coarseMask: emptyMask,
            width: width,
            height: height
        )
        XCTAssertEqual(refined, emptyMask)
    }

    func testInvalidBufferSizeThrowsBridgeError() {
        XCTAssertThrowsError(
            try SubtitleMaskRefiner.refine(
                imageBGRA: Data(count: 16),
                coarseMask: Data(count: 4),
                width: width,
                height: height
            )
        )
    }

    func testInvalidRefinementOptionsThrowsBridgeError() {
        XCTAssertThrowsError(
            try SubtitleMaskRefiner.refine(
                imageBGRA: makeSyntheticSubtitleImage(),
                coarseMask: makeCoarseMask(),
                width: width,
                height: height,
                options: .init(dilatePixels: -1, featherPixels: 0)
            )
        )
    }
}
