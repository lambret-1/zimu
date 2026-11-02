import CoreGraphics
import Foundation
import Photos
import UIKit

enum ImageExportService {
    static func uiImage(fromBGRA bgra: Data, width: Int, height: Int) throws -> UIImage {
        let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (expectedBytes, byteOverflow) = pixels.multipliedReportingOverflow(by: 4)
        guard width > 0, height > 0, !pixelOverflow, !byteOverflow,
              bgra.count == expectedBytes else {
            throw SubtitleEraserError.make(.exportFailed, underlying: "invalid BGRA buffer")
        }

        var data = bgra
        if ImageMetadataService.scanHasAlpha(data) {
            ImageMetadataService.premultiply(&data)
        } else {
            data.withUnsafeMutableBytes { buffer in
                guard let bytes = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return
                }
                for offset in stride(from: 3, to: buffer.count, by: 4) {
                    bytes[offset] = 255
                }
            }
        }

        let (bytesPerRow, rowOverflow) = width.multipliedReportingOverflow(by: 4)
        guard !rowOverflow,
              let provider = CGDataProvider(data: data as CFData) else {
            throw SubtitleEraserError.make(.exportFailed, underlying: "CGDataProvider unavailable")
        }
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        )
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            throw SubtitleEraserError.make(.exportFailed, underlying: "CGImage creation failed")
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    static func saveToPhotoLibrary(image: UIImage) async throws {
        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SubtitleEraserError.make(
                        .exportFailed,
                        underlying: error?.localizedDescription ?? "Photo library save failed",
                        retryable: true
                    ))
                }
            }
        }
    }
}
