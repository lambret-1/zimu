import XCTest
import UIKit
@testable import SuperResApp

final class ImageMetadataServiceTests: XCTestCase {
    private func makeImage(size: CGSize, color: UIColor, alpha: CGFloat = 1) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = alpha == 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.withAlphaComponent(alpha).setFill()
            context.cgContext.fill(CGRect(origin: .zero, size: size))
        }
    }

    func testLoadOpaqueImageReturnsTightlyPackedBGRA() throws {
        let loaded = try ImageMetadataService.load(
            from: makeImage(size: CGSize(width: 32, height: 24), color: .red)
        )
        XCTAssertEqual(loaded.pixelSize, CGSize(width: 32, height: 24))
        XCTAssertEqual(loaded.bgra.count, 32 * 24 * 4)
        XCTAssertFalse(loaded.hasAlpha)
        XCTAssertEqual(loaded.displayImage.imageOrientation, .up)
    }

    func testLoadTransparentImageDetectsAlphaAndUnpremultiplies() throws {
        let loaded = try ImageMetadataService.load(
            from: makeImage(size: CGSize(width: 16, height: 16), color: .blue, alpha: 0.5)
        )
        XCTAssertTrue(loaded.hasAlpha)
        XCTAssertEqual(loaded.bgra.count, 16 * 16 * 4)
    }

    func testLoadAppliesUIImageOrientationToPixelDimensions() throws {
        let upright = makeImage(size: CGSize(width: 30, height: 20), color: .green)
        let oriented = UIImage(cgImage: try XCTUnwrap(upright.cgImage), scale: 1, orientation: .right)
        let loaded = try ImageMetadataService.load(from: oriented)
        XCTAssertEqual(loaded.pixelSize, CGSize(width: 20, height: 30))
        XCTAssertEqual(loaded.displayImage.imageOrientation, .up)
    }

    func testLoadRetainsSourceColorSpace() throws {
        let displayP3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: displayP3,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        let cgImage = try XCTUnwrap(context.makeImage())
        let loaded = try ImageMetadataService.load(from: UIImage(cgImage: cgImage))
        XCTAssertEqual(loaded.colorSpace.name, displayP3.name)
    }

    func testExportUsesProvidedSourceColorSpace() throws {
        let displayP3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let image = try ImageExportService.uiImage(
            fromBGRA: Data(repeating: 128, count: 8 * 8 * 4),
            width: 8,
            height: 8,
            colorSpace: displayP3
        )
        XCTAssertEqual(image.cgImage?.colorSpace?.name, displayP3.name)
    }

    func testRejectsInvalidImageData() {
        XCTAssertThrowsError(try ImageMetadataService.load(from: Data([0, 1, 2, 3])))
    }

    func testAlphaPremultiplyRoundTripIsBounded() {
        var pixels = Data([100, 120, 140, 128, 20, 40, 60, 255])
        ImageMetadataService.premultiply(&pixels)
        ImageMetadataService.unpremultiply(&pixels)
        XCTAssertEqual(pixels[3], 128)
        XCTAssertEqual(pixels[7], 255)
        XCTAssertLessThanOrEqual(abs(Int(pixels[0]) - 100), 2)
        XCTAssertLessThanOrEqual(abs(Int(pixels[1]) - 120), 2)
        XCTAssertLessThanOrEqual(abs(Int(pixels[2]) - 140), 2)
    }
}
