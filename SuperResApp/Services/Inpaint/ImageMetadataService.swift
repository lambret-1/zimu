import CoreImage
import Foundation
import ImageIO
import UIKit

struct LoadedImage {
    let displayImage: UIImage
    let pixelSize: CGSize
    let bgra: Data
    let hasAlpha: Bool
}

enum ImageMetadataService {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private static let maxSide = 8192
    private static let maxPixels = 16 * 1024 * 1024

    static func load(from data: Data) throws -> LoadedImage {
        guard let image = UIImage(data: data) else {
            throw SubtitleEraserError.make(.mediaUnreadable, underlying: "UIImage decode failed")
        }
        return try load(from: image)
    }

    static func load(from image: UIImage) throws -> LoadedImage {
        guard let cgImage = normalizedCGImage(from: image) else {
            throw SubtitleEraserError.make(.mediaUnreadable, underlying: "CGImage unavailable")
        }
        let width = cgImage.width
        let height = cgImage.height
        try validate(width: width, height: height)

        guard var bgra = decodeBGRA(from: cgImage) else {
            throw SubtitleEraserError.make(.mediaUnreadable, underlying: "BGRA decode failed")
        }
        let hasAlpha = scanHasAlpha(bgra)
        if hasAlpha {
            unpremultiply(&bgra)
        }

        return LoadedImage(
            displayImage: UIImage(cgImage: cgImage),
            pixelSize: CGSize(width: width, height: height),
            bgra: bgra,
            hasAlpha: hasAlpha
        )
    }

    static func scanHasAlpha(_ bgra: Data) -> Bool {
        guard bgra.count.isMultiple(of: 4) else { return false }
        return bgra.withUnsafeBytes { buffer in
            guard let bytes = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return false
            }
            return stride(from: 3, to: buffer.count, by: 4).contains { bytes[$0] < 255 }
        }
    }

    static func unpremultiply(_ bgra: inout Data) {
        transformAlpha(in: &bgra, premultiply: false)
    }

    static func premultiply(_ bgra: inout Data) {
        transformAlpha(in: &bgra, premultiply: true)
    }

    private static func validate(width: Int, height: Int) throws {
        guard width > 0, height > 0 else {
            throw SubtitleEraserError.make(.mediaMetadataInvalid, underlying: "zero pixel size")
        }
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, width <= maxSide, height <= maxSide, pixels <= maxPixels else {
            throw SubtitleEraserError.make(.mediaTooLarge, underlying: "image exceeds supported dimensions")
        }
        let (_, byteOverflow) = pixels.multipliedReportingOverflow(by: 4)
        guard !byteOverflow else {
            throw SubtitleEraserError.make(.mediaTooLarge, underlying: "image buffer size overflow")
        }
    }

    private static func normalizedCGImage(from image: UIImage) -> CGImage? {
        guard let cgImage = image.cgImage else { return nil }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        guard orientation != .up else { return cgImage }
        let oriented = CIImage(cgImage: cgImage).oriented(orientation)
        return ciContext.createCGImage(oriented, from: oriented.extent)
    }

    private static func decodeBGRA(from cgImage: CGImage) -> Data? {
        let width = cgImage.width
        let height = cgImage.height
        let (bytesPerRow, rowOverflow) = width.multipliedReportingOverflow(by: 4)
        let (byteCount, dataOverflow) = bytesPerRow.multipliedReportingOverflow(by: height)
        guard !rowOverflow, !dataOverflow else { return nil }

        var data = Data(count: byteCount)
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        )
        let rendered = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: bitmapInfo.rawValue
                  ) else {
                return false
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return rendered ? data : nil
    }

    private static func transformAlpha(in bgra: inout Data, premultiply: Bool) {
        guard bgra.count.isMultiple(of: 4) else { return }
        bgra.withUnsafeMutableBytes { buffer in
            guard let bytes = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }
            for offset in stride(from: 0, to: buffer.count, by: 4) {
                let alpha = Int(bytes[offset + 3])
                if alpha == 0 {
                    if premultiply {
                        for channel in 0..<3 {
                            bytes[offset + channel] = 0
                        }
                    }
                    continue
                }
                guard alpha < 255 else { continue }
                for channel in 0..<3 {
                    let value = Int(bytes[offset + channel])
                    let adjusted: Int
                    if premultiply {
                        adjusted = (value * alpha + 127) / 255
                    } else {
                        adjusted = min(255, (value * 255 + alpha / 2) / alpha)
                    }
                    bytes[offset + channel] = UInt8(adjusted)
                }
            }
        }
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
