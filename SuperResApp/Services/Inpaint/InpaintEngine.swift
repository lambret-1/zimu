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
        return try OpenCVInpaintService.inpaintAdvancedBGRA(
            imageData: imageBGRA,
            maskData: mask,
            width: width,
            height: height,
            radius: radius
        )
    }

    /// 带羽化混合的修复。旧 Data 版 inpaint API 保持不变。
    static func inpaint(
        imageBGRA: Data,
        mask: RasterizedMask,
        width: Int,
        height: Int,
        radius: Int = defaultRadius
    ) throws -> Data {
        guard width == mask.width, height == mask.height else {
            throw SubtitleEraserError.make(.openCVBridgeError, underlying: "mask size mismatch")
        }
        try validate(
            imageBGRA: imageBGRA,
            mask: mask.binary,
            width: width,
            height: height,
            radius: radius
        )
        guard mask.softWeights.count == width * height else {
            throw SubtitleEraserError.make(.openCVBridgeError, underlying: "soft mask length mismatch")
        }
        let repaired = try OpenCVInpaintService.inpaintAdvancedBGRA(
            imageData: imageBGRA,
            maskData: mask.binary,
            width: width,
            height: height,
            radius: radius
        )
        return blend(original: imageBGRA, inpainted: repaired, softWeights: mask.softWeights)
    }

    /// 逐像素混合：mask 内取修复，mask 外取原图；Alpha 一律取原图。
    static func blend(original: Data, inpainted: Data, softWeights: [UInt8]) -> Data {
        let pixelCount = softWeights.count
        guard original.count == pixelCount * 4, inpainted.count == pixelCount * 4 else {
            return original
        }
        var result = original
        result.withUnsafeMutableBytes { resultBuffer in
            guard let resultBytes = resultBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }
            original.withUnsafeBytes { originalBuffer in
                guard let originalBytes = originalBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return
                }
                inpainted.withUnsafeBytes { repairedBuffer in
                    guard let repairedBytes = repairedBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return
                    }
                    for index in 0..<pixelCount {
                        let weight = Double(softWeights[index]) / 255.0
                        let offset = index * 4
                        for channel in 0..<3 {
                            let originalValue = Double(originalBytes[offset + channel])
                            let repairedValue = Double(repairedBytes[offset + channel])
                            let value = originalValue * (1 - weight) + repairedValue * weight
                            resultBytes[offset + channel] = UInt8(min(max(value.rounded(), 0), 255))
                        }
                        resultBytes[offset + 3] = originalBytes[offset + 3]
                    }
                }
            }
        }
        return result
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
