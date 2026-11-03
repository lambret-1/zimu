import XCTest
@testable import SuperResApp

final class OpenCVInpaintServiceTests: XCTestCase {
    private func makeBGRA(
        width: Int,
        height: Int,
        blue: UInt8 = 30,
        green: UInt8 = 90,
        red: UInt8 = 160,
        alpha: UInt8 = 128
    ) -> Data {
        var bytes = Data(count: width * height * 4)
        bytes.withUnsafeMutableBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }
            for pixel in 0..<(width * height) {
                base[pixel * 4] = blue
                base[pixel * 4 + 1] = green
                base[pixel * 4 + 2] = red
                base[pixel * 4 + 3] = alpha
            }
        }
        return bytes
    }

    private func makeGradientBGRA(width: Int, height: Int) -> Data {
        var bytes = Data(count: width * height * 4)
        bytes.withUnsafeMutableBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }
            for y in 0..<height {
                for x in 0..<width {
                    let offset = (y * width + x) * 4
                    base[offset] = UInt8((x * 255) / max(width - 1, 1))
                    base[offset + 1] = UInt8((y * 255) / max(height - 1, 1))
                    base[offset + 2] = UInt8(((x + y) * 255) / max(width + height - 2, 1))
                    base[offset + 3] = 173
                }
            }
        }
        return bytes
    }

    private func makeMask(width: Int, height: Int, rect: CGRect) -> Data {
        var bytes = Data(count: width * height)
        let minX = Int(rect.minX)
        let minY = Int(rect.minY)
        let maxX = Int(rect.maxX)
        let maxY = Int(rect.maxY)
        bytes.withUnsafeMutableBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }
            for row in minY..<maxY {
                for column in minX..<maxX {
                    base[row * width + column] = 255
                }
            }
        }
        return bytes
    }

    func testAdvancedInpaintPreservesAlphaAndOutputLength() throws {
        let width = 48
        let height = 48
        let image = makeGradientBGRA(width: width, height: height)
        let mask = makeMask(
            width: width,
            height: height,
            rect: CGRect(x: 18, y: 30, width: 10, height: 6)
        )

        let output = try OpenCVInpaintService.inpaintAdvancedBGRA(
            imageData: image,
            maskData: mask,
            width: width,
            height: height
        )

        XCTAssertEqual(output.count, image.count)
        for pixel in 0..<(width * height) {
            XCTAssertEqual(output[pixel * 4 + 3], image[pixel * 4 + 3])
        }
    }

    func testAdvancedInpaintEmptyMaskReturnsOriginal() throws {
        let width = 16
        let height = 16
        let image = makeGradientBGRA(width: width, height: height)
        let output = try OpenCVInpaintService.inpaintAdvancedBGRA(
            imageData: image,
            maskData: Data(count: width * height),
            width: width,
            height: height
        )
        XCTAssertEqual(output, image)
    }

    func testOutputSizeAndLength() throws {
        let width = 64
        let height = 64
        let image = makeGradientBGRA(width: width, height: height)
        let mask = makeMask(width: width, height: height, rect: CGRect(x: 28, y: 28, width: 8, height: 8))

        let output = try OpenCVInpaintService.inpaintBGRA(
            imageData: image, maskData: mask, width: width, height: height
        )
        XCTAssertEqual(output.count, width * height * 4)
    }

    func testAlphaChannelIsPreserved() throws {
        let width = 32
        let height = 32
        let image = makeBGRA(width: width, height: height, alpha: 117)
        let mask = makeMask(width: width, height: height, rect: CGRect(x: 12, y: 12, width: 8, height: 8))

        let output = try OpenCVInpaintService.inpaintBGRA(
            imageData: image, maskData: mask, width: width, height: height
        )
        for pixel in 0..<(width * height) {
            XCTAssertEqual(output[pixel * 4 + 3], image[pixel * 4 + 3])
        }
    }

    func testPixelsOutsideMaskRemainUnchanged() throws {
        let width = 32
        let height = 32
        let image = makeGradientBGRA(width: width, height: height)
        let maskX = 12
        let maskY = 12
        let maskWidth = 8
        let maskHeight = 8
        let mask = makeMask(
            width: width, height: height,
            rect: CGRect(x: maskX, y: maskY, width: maskWidth, height: maskHeight)
        )

        let output = try OpenCVInpaintService.inpaintBGRA(
            imageData: image, maskData: mask, width: width, height: height
        )
        for y in 0..<height {
            for x in 0..<width {
                if (maskX..<(maskX + maskWidth)).contains(x)
                    && (maskY..<(maskY + maskHeight)).contains(y) {
                    continue
                }
                let offset = (y * width + x) * 4
                XCTAssertEqual(output[offset], image[offset])
                XCTAssertEqual(output[offset + 1], image[offset + 1])
                XCTAssertEqual(output[offset + 2], image[offset + 2])
            }
        }
    }

    func testMaskedRegionIsModified() throws {
        let width = 32
        let height = 32
        let image = makeGradientBGRA(width: width, height: height)
        let mask = makeMask(width: width, height: height, rect: CGRect(x: 12, y: 12, width: 8, height: 8))
        let output = try OpenCVInpaintService.inpaintBGRA(
            imageData: image, maskData: mask, width: width, height: height
        )

        var changed = false
        for y in 12..<20 {
            for x in 12..<20 {
                let offset = (y * width + x) * 4
                if output[offset] != image[offset]
                    || output[offset + 1] != image[offset + 1]
                    || output[offset + 2] != image[offset + 2] {
                    changed = true
                    break
                }
            }
            if changed { break }
        }
        XCTAssertTrue(changed, "Telea should modify at least part of the masked region.")
    }

    func testNonSquareImage() throws {
        let width = 64
        let height = 32
        let image = makeGradientBGRA(width: width, height: height)
        let mask = makeMask(width: width, height: height, rect: CGRect(x: 28, y: 12, width: 8, height: 8))
        let output = try OpenCVInpaintService.inpaintBGRA(
            imageData: image, maskData: mask, width: width, height: height
        )
        XCTAssertEqual(output.count, width * height * 4)
    }

    func testZeroMaskReturnsOriginalImage() throws {
        let width = 16
        let height = 16
        let image = makeGradientBGRA(width: width, height: height)
        let mask = Data(count: width * height)

        let output = try OpenCVInpaintService.inpaintBGRA(
            imageData: image, maskData: mask, width: width, height: height
        )
        XCTAssertEqual(output, image)
    }

    func testFullCoverageMaskIsRejected() {
        let width = 16
        let height = 16
        let image = makeGradientBGRA(width: width, height: height)
        let mask = Data(repeating: 255, count: width * height)

        XCTAssertThrowsError(
            try OpenCVInpaintService.inpaintBGRA(
                imageData: image, maskData: mask, width: width, height: height
            )
        ) { error in
            XCTAssertEqual((error as? SubtitleEraserError)?.code, .inpaintFailed)
        }
    }

    func testHighCoverageMaskTouchingImageEdgeIsRejected() {
        let width = 16
        let height = 16
        let image = makeGradientBGRA(width: width, height: height)
        var mask = Data(repeating: 255, count: width * height)
        // Leave a 2x2 unmasked island: coverage is above 95%, and the mask
        // touches every image edge.
        mask[7 * width + 7] = 0
        mask[7 * width + 8] = 0
        mask[8 * width + 7] = 0
        mask[8 * width + 8] = 0

        XCTAssertThrowsError(
            try OpenCVInpaintService.inpaintBGRA(
                imageData: image, maskData: mask, width: width, height: height
            )
        ) { error in
            XCTAssertEqual((error as? SubtitleEraserError)?.code, .inpaintFailed)
        }
    }

    func testInvalidRadiusIsRejected() {
        let width = 16
        let height = 16
        let image = makeGradientBGRA(width: width, height: height)
        let mask = makeMask(width: width, height: height, rect: CGRect(x: 6, y: 6, width: 4, height: 4))

        for radius in [0, 21] {
            XCTAssertThrowsError(
                try OpenCVInpaintService.inpaintBGRA(
                    imageData: image, maskData: mask,
                    width: width, height: height, radius: radius
                )
            ) { error in
                XCTAssertEqual((error as? SubtitleEraserError)?.code, .inpaintFailed)
            }
        }
    }

    func testMismatchedBufferSizesAreRejected() {
        let width = 16
        let height = 16
        let image = Data(count: 32)
        let mask = Data(count: width * height)

        XCTAssertThrowsError(
            try OpenCVInpaintService.inpaintBGRA(
                imageData: image, maskData: mask, width: width, height: height
            )
        ) { error in
            XCTAssertEqual((error as? SubtitleEraserError)?.code, .openCVBridgeError)
        }
    }

    func testOversizedImageIsRejectedBeforeBufferValidation() {
        let image = Data()
        let mask = Data()

        XCTAssertThrowsError(
            try OpenCVInpaintService.inpaintBGRA(
                imageData: image, maskData: mask, width: 5000, height: 5000
            )
        ) { error in
            XCTAssertEqual((error as? SubtitleEraserError)?.code, .mediaTooLarge)
        }
    }

    func testSideLimitIsEnforced() {
        XCTAssertThrowsError(
            try OpenCVInpaintService.inpaintBGRA(
                imageData: Data(), maskData: Data(), width: 8193, height: 1
            )
        ) { error in
            XCTAssertEqual((error as? SubtitleEraserError)?.code, .mediaTooLarge)
        }
    }
}
