import XCTest
@testable import SuperResApp

final class InpaintEngineTests: XCTestCase {
    private func image(width: Int, height: Int) -> Data {
        var data = Data(count: width * height * 4)
        data.withUnsafeMutableBytes { buffer in
            guard let bytes = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for index in 0..<(width * height) {
                bytes[index * 4] = UInt8((index * 3) % 255)
                bytes[index * 4 + 1] = UInt8((index * 5) % 255)
                bytes[index * 4 + 2] = UInt8((index * 7) % 255)
                bytes[index * 4 + 3] = 255
            }
        }
        return data
    }

    private func repeatingTextureImage(width: Int, height: Int) -> Data {
        var data = Data(count: width * height * 4)
        data.withUnsafeMutableBytes { buffer in
            guard let bytes = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for y in 0..<height {
                for x in 0..<width {
                    let offset = (y * width + x) * 4
                    bytes[offset] = UInt8((x % 8) * 30)
                    bytes[offset + 1] = UInt8((y % 8) * 30)
                    bytes[offset + 2] = UInt8(((x + y) % 8) * 30)
                    bytes[offset + 3] = 255
                }
            }
        }
        return data
    }

    private func mask(width: Int, height: Int, rect: CGRect) -> Data {
        var data = Data(count: width * height)
        data.withUnsafeMutableBytes { buffer in
            guard let bytes = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for y in Int(rect.minY)..<Int(rect.maxY) {
                for x in Int(rect.minX)..<Int(rect.maxX) {
                    bytes[y * width + x] = 255
                }
            }
        }
        return data
    }

    func testValidationRejectsIncorrectImageBufferLength() {
        XCTAssertThrowsError(
            try InpaintEngine.validate(
                imageBGRA: Data(count: 10),
                mask: Data(count: 10),
                width: 32,
                height: 32,
                radius: 4
            )
        )
    }

    func testValidationRejectsEmptyMask() {
        XCTAssertThrowsError(
            try InpaintEngine.validate(
                imageBGRA: image(width: 16, height: 16),
                mask: Data(count: 16 * 16),
                width: 16,
                height: 16,
                radius: 4
            )
        )
    }

    func testValidationRejectsInvalidRadius() {
        let input = image(width: 16, height: 16)
        let maskData = mask(width: 16, height: 16, rect: CGRect(x: 6, y: 6, width: 4, height: 4))
        XCTAssertThrowsError(
            try InpaintEngine.validate(
                imageBGRA: input,
                mask: maskData,
                width: 16,
                height: 16,
                radius: 0
            )
        )
    }

    func testInpaintPreservesDimensionsAndPixelsOutsideMask() throws {
        let width = 32
        let height = 32
        let input = image(width: width, height: height)
        let rect = CGRect(x: 12, y: 12, width: 8, height: 8)
        let maskData = mask(width: width, height: height, rect: rect)
        let output = try InpaintEngine.inpaint(
            imageBGRA: input,
            mask: maskData,
            width: width,
            height: height
        )
        XCTAssertEqual(output.count, width * height * 4)
        for y in 0..<height {
            for x in 0..<width where !rect.contains(CGPoint(x: x, y: y)) {
                let offset = (y * width + x) * 4
                XCTAssertEqual(output[offset], input[offset])
                XCTAssertEqual(output[offset + 1], input[offset + 1])
                XCTAssertEqual(output[offset + 2], input[offset + 2])
                XCTAssertEqual(output[offset + 3], input[offset + 3])
            }
        }
    }

    func testBackgroundPatchMatchingReconstructsRepeatedFineTexture() throws {
        let width = 192
        let height = 192
        var input = repeatingTextureImage(width: width, height: height)
        let rect = CGRect(x: 80, y: 80, width: 16, height: 8)
        let maskData = mask(width: width, height: height, rect: rect)

        input.withUnsafeMutableBytes { buffer in
            guard let bytes = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for y in Int(rect.minY)..<Int(rect.maxY) {
                for x in Int(rect.minX)..<Int(rect.maxX) {
                    let offset = (y * width + x) * 4
                    bytes[offset] = 255
                    bytes[offset + 1] = 255
                    bytes[offset + 2] = 255
                }
            }
        }

        let output = try InpaintEngine.inpaint(
            imageBGRA: input,
            mask: maskData,
            width: width,
            height: height
        )

        var totalError = 0
        var samples = 0
        output.withUnsafeBytes { buffer in
            guard let bytes = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for y in Int(rect.minY)..<Int(rect.maxY) {
                for x in Int(rect.minX)..<Int(rect.maxX) {
                    let offset = (y * width + x) * 4
                    let expected = [
                        UInt8((x % 8) * 30),
                        UInt8((y % 8) * 30),
                        UInt8(((x + y) % 8) * 30)
                    ]
                    for channel in 0..<3 {
                        totalError += abs(Int(bytes[offset + channel]) - Int(expected[channel]))
                        samples += 1
                    }
                }
            }
        }
        XCTAssertLessThan(Double(totalError) / Double(samples), 8.0)
    }

    func testBlendPreservesOriginalWhereWeightIsZeroAndPreservesAlpha() {
        let original = Data([
            10, 20, 30, 40,
            50, 60, 70, 80,
            90, 100, 110, 120
        ])
        let repaired = Data([
            200, 210, 220, 230,
            150, 160, 170, 180,
            130, 140, 150, 160
        ])

        let output = InpaintEngine.blend(
            original: original,
            inpainted: repaired,
            softWeights: [0, 255, 128]
        )

        XCTAssertEqual(Array(output[0..<4]), Array(original[0..<4]))
        XCTAssertEqual(Array(output[4..<7]), Array(repaired[4..<7]))
        XCTAssertEqual(output[7], original[7])
        XCTAssertEqual(output[11], original[11])
        XCTAssertEqual(output[3], original[3])
    }

    func testBlendRejectsMismatchedBuffersByReturningOriginal() {
        let original = Data([1, 2, 3, 4])
        let output = InpaintEngine.blend(
            original: original,
            inpainted: Data([9, 9, 9]),
            softWeights: [255]
        )
        XCTAssertEqual(output, original)
    }

    func testBGRAOutputCanBeConvertedBackToUIImage() throws {
        let width = 16
        let height = 16
        let input = image(width: width, height: height)
        let uiImage = try ImageExportService.uiImage(fromBGRA: input, width: width, height: height)
        XCTAssertEqual(uiImage.size, CGSize(width: width, height: height))
        XCTAssertEqual(uiImage.imageOrientation, .up)
    }
}
