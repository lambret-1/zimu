import Foundation

enum SubtitleMaskRefiner {
    struct Options {
        var dilatePixels: Int = 4
        var featherPixels: Int = 2
    }

    /// Refines a BGRA image's coarse subtitle mask and pads the detected strokes.
    static func refine(
        imageBGRA: Data,
        coarseMask: Data,
        width: Int,
        height: Int,
        options: Options = Options()
    ) throws -> Data {
        guard width > 0, height > 0,
              width <= Int.max / height,
              width * height <= 16 * 1024 * 1024 else {
            throw SubtitleEraserError.make(
                .openCVBridgeError,
                underlying: "Image dimensions are outside the supported range."
            )
        }

        let pixelCount = width * height
        guard imageBGRA.count == pixelCount * 4 else {
            throw SubtitleEraserError.make(
                .openCVBridgeError,
                underlying: "BGRA length mismatch."
            )
        }
        guard coarseMask.count == pixelCount else {
            throw SubtitleEraserError.make(
                .openCVBridgeError,
                underlying: "Mask length mismatch."
            )
        }
        guard (0...20).contains(options.dilatePixels),
              (0...32).contains(options.featherPixels) else {
            throw SubtitleEraserError.make(
                .openCVBridgeError,
                underlying: "Refinement radius is outside the supported range."
            )
        }

        var bridgeError: NSError?
        guard let refined = superResRefineSubtitleMask(
            imageBGRA,
            coarseMask,
            width,
            height,
            dilateRadius: options.dilatePixels,
            featherPixels: options.featherPixels,
            error: &bridgeError
        ) else {
            throw SubtitleEraserError.make(
                .openCVBridgeError,
                underlying: bridgeError?.localizedDescription ?? "Unknown refine failure."
            )
        }

        return refined as Data
    }
}
