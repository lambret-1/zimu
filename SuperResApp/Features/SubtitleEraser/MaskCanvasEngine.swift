import Foundation
import CoreGraphics

/// Pure geometry and sampling helpers for the mask drawing canvas.
enum MaskCanvasEngine {
    static let minimumSampleDistance: Double = 0.002

    static func normalizedPoint(from location: CGPoint, in canvasSize: CGSize) -> NormalizedPoint {
        NormalizedPoint(location, in: canvasSize)
    }

    static func shouldAppend(_ newPoint: NormalizedPoint, after lastPoint: NormalizedPoint?) -> Bool {
        guard let lastPoint else { return true }
        let dx = newPoint.x - lastPoint.x
        let dy = newPoint.y - lastPoint.y
        return (dx * dx + dy * dy).squareRoot() >= minimumSampleDistance
    }

    /// Three-point moving average; the first and last samples remain unchanged.
    static func smoothed(_ points: [NormalizedPoint]) -> [NormalizedPoint] {
        guard points.count > 2 else { return points }
        var result = [points[0]]
        result.reserveCapacity(points.count)
        for index in 1..<(points.count - 1) {
            let previous = points[index - 1]
            let current = points[index]
            let next = points[index + 1]
            result.append(NormalizedPoint(
                x: (previous.x + current.x + next.x) / 3,
                y: (previous.y + current.y + next.y) / 3
            ))
        }
        if let last = points.last { result.append(last) }
        return result
    }

    static func normalizedBrushWidth(ptWidth: CGFloat, canvasSize: CGSize) -> Double {
        let shortSide = min(canvasSize.width, canvasSize.height)
        guard shortSide > 0, ptWidth.isFinite else { return 0 }
        return max(0, Double(ptWidth / shortSide))
    }

    static func ptWidth(for normalizedWidth: Double, canvasSize: CGSize) -> CGFloat {
        let shortSide = min(canvasSize.width, canvasSize.height)
        guard normalizedWidth.isFinite else { return 0 }
        return max(0, CGFloat(normalizedWidth) * shortSide)
    }
}
