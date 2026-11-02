import Foundation

enum OpenCVInpaintService {
    static func performInpaint(
        imageData: Data,
        maskData: Data,
        width: Int,
        height: Int,
        radius: Int = 3
    ) throws -> Data {
        guard width > 0, height > 0, radius > 0,
              width <= Int(Int32.max), height <= Int(Int32.max),
              radius <= Int(Int32.max) else {
            throw SubtitleEraserError.make(
                .openCVBridgeError,
                underlying: "Invalid dimensions or inpaint radius."
            )
        }

        let (pixelCount, pixelCountOverflow) = width.multipliedReportingOverflow(by: height)
        let (imageByteCount, imageByteCountOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
        guard !pixelCountOverflow, !imageByteCountOverflow,
              imageData.count == imageByteCount,
              maskData.count == pixelCount else {
            throw SubtitleEraserError.make(
                .openCVBridgeError,
                underlying: "Image or mask byte count does not match its dimensions."
            )
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
            throw SubtitleEraserError.make(
                .openCVBridgeError,
                underlying: bridgeError?.localizedDescription ?? "OpenCV returned no output."
            )
        }

        return result
    }
}
