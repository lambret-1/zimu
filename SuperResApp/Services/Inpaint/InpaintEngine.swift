import Foundation

enum InpaintEngine {
    static let maxPixels = 16 * 1024 * 1024
    static let maxSide = 8192
    static let defaultRadius = 4

    static func inpaint(
        imageBGRA: Data,
        mask: Data,
        width: Int,
        height: Int,
        radius: Int = defaultRadius
    ) throws -> Data {
        try validate(imageBGRA: imageBGRA, mask: mask, width: width, height: height, radius: radius)
        return try OpenCVInpaintService.inpaintBGRA(
            imageData: imageBGRA,
            maskData: mask,
            width: width,
            height: height,
            radius: radius
        )
    }

    static func validate(
        imageBGRA: Data,
        mask: Data,
        width: Int,
        height: Int,
        radius: Int
    ) throws {
        guard width > 0, height > 0, width <= maxSide, height <= maxSide else {
            throw SubtitleEraserError.make(.mediaTooLarge, underlying: "size out of range")
        }
        let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        guard !pixelOverflow, pixels <= maxPixels else {
            throw SubtitleEraserError.make(.mediaTooLarge, underlying: "pixels exceed 16 MP")
        }
        let (imageBytes, imageOverflow) = pixels.multipliedReportingOverflow(by: 4)
        guard !imageOverflow, imageBGRA.count == imageBytes, mask.count == pixels else {
            throw SubtitleEraserError.make(.openCVBridgeError, underlying: "input buffer length mismatch")
        }
        guard (1...20).contains(radius) else {
            throw SubtitleEraserError.make(.inpaintFailed, underlying: "radius out of range")
        }
        guard mask.contains(255) else {
            throw SubtitleEraserError.make(.inpaintFailed, underlying: "mask is empty")
        }
    }
}
