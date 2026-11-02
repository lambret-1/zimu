import Foundation

enum OpenCVInpaintService {
    static let maxPixels = 16 * 1024 * 1024
    static let maxSide = 8192
    static let maxRadius = 20

    /// Repairs a tightly packed BGRA8888 buffer with an 8-bit, single-channel mask.
    /// The bridge repeats every safety check before entering OpenCV.
    static func inpaintBGRA(
        imageData: Data,
        maskData: Data,
        width: Int,
        height: Int,
        radius: Int = 4
    ) throws -> Data {
        guard width >= 1, height >= 1, width <= maxSide, height <= maxSide else {
            throw makeError(.mediaTooLarge, "width/height out of supported range")
        }

        let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        guard !pixelOverflow, pixelCount <= maxPixels else {
            throw makeError(.mediaTooLarge, "image exceeds 16 MP")
        }

        guard (1...maxRadius).contains(radius) else {
            throw makeError(.inpaintFailed, "radius must be between 1 and 20")
        }

        let (expectedImageBytes, imageOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
        guard !imageOverflow,
              imageData.count == expectedImageBytes,
              maskData.count == pixelCount else {
            throw makeError(.openCVBridgeError, "image or mask buffer size mismatch")
        }

        var bridgeError: NSError?
        guard let result = inpaintImage(
            imageData,
            maskData,
            Int32(width),
            Int32(height),
            Int32(radius),
            &bridgeError
        ) else {
            let code: SubtitleEraserErrorCode
            switch bridgeError?.code {
            case 1002: code = .mediaTooLarge
            case 4001: code = .inpaintFailed
            case 4002: code = .openCVBridgeError
            default: code = .openCVBridgeError
            }
            throw makeError(code, bridgeError?.localizedDescription ?? "unknown OpenCV bridge failure")
        }

        return result
    }

    private static func makeError(
        _ code: SubtitleEraserErrorCode,
        _ detail: String
    ) -> SubtitleEraserError {
        SubtitleEraserError.make(code, underlying: detail)
    }
}
