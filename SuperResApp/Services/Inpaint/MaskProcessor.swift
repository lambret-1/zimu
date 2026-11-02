import CoreGraphics
import Foundation

enum MaskProcessor {
    static let expandPixelsAt1080P = 3
    private static let maxPixels = 16 * 1024 * 1024
    private static let maxSide = 8192

    static func rasterize(
        strokes: [MaskStroke],
        targetSize: CGSize,
        expandPixels: Int? = nil
    ) throws -> Data {
        guard targetSize.width.isFinite, targetSize.height.isFinite,
              targetSize.width > 0, targetSize.height > 0,
              targetSize.width <= CGFloat(maxSide), targetSize.height <= CGFloat(maxSide) else {
            throw SubtitleEraserError.make(.mediaMetadataInvalid, underlying: "mask target size invalid")
        }
        let width = Int(targetSize.width.rounded())
        let height = Int(targetSize.height.rounded())
        let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, pixelCount > 0, pixelCount <= maxPixels else {
            throw SubtitleEraserError.make(.mediaTooLarge, underlying: "mask dimensions exceed limit")
        }
        guard !strokes.isEmpty else {
            throw SubtitleEraserError.make(.inpaintFailed, underlying: "empty strokes")
        }
        let (byteCount, byteOverflow) = width.multipliedReportingOverflow(by: height)
        guard !byteOverflow else {
            throw SubtitleEraserError.make(.mediaTooLarge, underlying: "mask buffer size overflow")
        }

        var data = Data(count: byteCount)
        let rendered = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else {
                return false
            }
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.setShouldAntialias(true)
            context.setAllowsAntialiasing(true)
            for stroke in strokes {
                draw(stroke, context: context, targetSize: targetSize)
            }
            return true
        }
        guard rendered else {
            throw SubtitleEraserError.make(.inpaintFailed, underlying: "mask bitmap context unavailable")
        }

        var bytes = [UInt8](data)
        binarize(&bytes)
        let expansion = min(64, max(0, expandPixels ?? scaledExpansion(for: targetSize)))
        if expansion > 0 {
            bytes = dilate(bytes, width: width, height: height, iterations: expansion)
        }
        guard bytes.contains(255) else {
            throw SubtitleEraserError.make(.inpaintFailed, underlying: "mask contains no brush pixels")
        }
        return Data(bytes)
    }

    private static func draw(_ stroke: MaskStroke, context: CGContext, targetSize: CGSize) {
        let lineWidth = CGFloat(stroke.brushWidth) * min(targetSize.width, targetSize.height)
        guard lineWidth.isFinite, lineWidth > 0.5, !stroke.points.isEmpty else { return }

        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(lineWidth)
        if stroke.tool == .eraser {
            context.setBlendMode(.clear)
        } else {
            context.setBlendMode(.normal)
            context.setStrokeColor(gray: 1, alpha: 1)
            context.setFillColor(gray: 1, alpha: 1)
        }

        let points = stroke.points.map { $0.toCGPoint(in: targetSize) }
        if points.count == 1, let point = points.first {
            let rect = CGRect(
                x: point.x - lineWidth / 2,
                y: point.y - lineWidth / 2,
                width: lineWidth,
                height: lineWidth
            )
            context.fillEllipse(in: rect)
        } else if let first = points.first {
            context.beginPath()
            context.move(to: first)
            for point in points.dropFirst() {
                context.addLine(to: point)
            }
            context.strokePath()
        }
        context.restoreGState()
    }

    private static func scaledExpansion(for size: CGSize) -> Int {
        let scale = Double(min(size.width, size.height)) / 1080
        return max(1, Int((Double(expandPixelsAt1080P) * scale).rounded()))
    }

    private static func binarize(_ bytes: inout [UInt8]) {
        for index in bytes.indices {
            bytes[index] = bytes[index] >= 128 ? 255 : 0
        }
    }

    private static func dilate(_ source: [UInt8], width: Int, height: Int, iterations: Int) -> [UInt8] {
        var current = source
        for _ in 0..<iterations {
            var horizontal = current
            for y in 0..<height {
                let row = y * width
                for x in 0..<width {
                    let left = max(0, x - 1)
                    let right = min(width - 1, x + 1)
                    if current[row + left] == 255 || current[row + x] == 255
                        || current[row + right] == 255 {
                        horizontal[row + x] = 255
                    }
                }
            }
            var next = horizontal
            for y in 0..<height {
                let top = max(0, y - 1) * width
                let row = y * width
                let bottom = min(height - 1, y + 1) * width
                for x in 0..<width where horizontal[top + x] == 255
                    || horizontal[row + x] == 255 || horizontal[bottom + x] == 255 {
                    next[row + x] = 255
                }
            }
            current = next
        }
        return current
    }
}
