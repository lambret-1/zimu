import Foundation
import CoreGraphics

// MARK: - 素材

enum SubtitleEraserMediaKind: String, Codable, Equatable {
    case image
    case video
}

struct SubtitleEraserMedia: Equatable {
    let id: UUID
    let kind: SubtitleEraserMediaKind
    let sourceURL: URL
    /// 正方向像素尺寸（已应用 orientation）
    let pixelSize: CGSize
    /// 视频时长；图片为 nil
    let durationSeconds: Double?
    let isHDR: Bool

    // swiftlint:disable:next function_parameter_count
    init(id: UUID = UUID(),
         kind: SubtitleEraserMediaKind,
         sourceURL: URL,
         pixelSize: CGSize,
         durationSeconds: Double? = nil,
         isHDR: Bool = false) {
        self.id = id
        self.kind = kind
        self.sourceURL = sourceURL
        self.pixelSize = pixelSize
        self.durationSeconds = durationSeconds
        self.isHDR = isHDR
    }
}

// MARK: - 归一化坐标

struct NormalizedPoint: Codable, Equatable, Hashable {
    let x: Double
    let y: Double

    init(x: Double, y: Double) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
    }

    init(_ point: CGPoint, in size: CGSize) {
        let sx = size.width > 0 ? Double(size.width) : 1
        let sy = size.height > 0 ? Double(size.height) : 1
        self.init(x: Double(point.x) / sx, y: Double(point.y) / sy)
    }

    func toCGPoint(in size: CGSize) -> CGPoint {
        CGPoint(x: x * Double(size.width), y: y * Double(size.height))
    }
}

struct NormalizedRect: Codable, Equatable, Hashable {
    let origin: NormalizedPoint
    let width: Double
    let height: Double

    init(origin: NormalizedPoint, width: Double, height: Double) {
        self.origin = origin
        self.width = max(0, min(width, 1 - origin.x))
        self.height = max(0, min(height, 1 - origin.y))
    }

    var maxX: Double { origin.x + width }
    var maxY: Double { origin.y + height }

    func toCGRect(in size: CGSize) -> CGRect {
        CGRect(x: origin.x * Double(size.width),
               y: origin.y * Double(size.height),
               width: width * Double(size.width),
               height: height * Double(size.height))
    }
}

// MARK: - 手绘笔画

enum MaskBrushTool: String, Codable, Equatable {
    case brush
    case eraser
}

struct MaskStroke: Equatable {
    let id: UUID
    let tool: MaskBrushTool
    /// 归一化宽度：相对画布短边
    let brushWidth: Double
    let points: [NormalizedPoint]
    let isClosed: Bool

    init(id: UUID = UUID(),
         tool: MaskBrushTool,
         brushWidth: Double,
         points: [NormalizedPoint],
         isClosed: Bool = false) {
        self.id = id
        self.tool = tool
        self.brushWidth = max(0, brushWidth)
        self.points = points
        self.isClosed = isClosed
    }
}

// MARK: - 自动检测

enum DetectionSource: String, Codable, Equatable {
    case rule
    case vision
    case coreML
}

struct DetectedSubtitleRegion: Equatable {
    let rect: NormalizedRect
    let confidence: Double
    let source: DetectionSource
}

// MARK: - 进度

enum InpaintPhase: String, Equatable {
    case decoding
    case detecting
    case masking
    case inpaint
    case encoding
    case saving
    case done
}

struct InpaintProgress: Equatable {
    let phase: InpaintPhase
    /// 0...1
    let fraction: Double
    let message: String?

    init(phase: InpaintPhase, fraction: Double, message: String? = nil) {
        self.phase = phase
        self.fraction = min(max(fraction, 0), 1)
        self.message = message
    }
}
