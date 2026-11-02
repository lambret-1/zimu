import Foundation

enum SubtitleEraserErrorSeverity: String, Codable, Equatable {
    case info
    case warning
    case error
}

enum SubtitleEraserErrorCode: String, CaseIterable, Equatable {
    case internalStateError     = "E0001"
    case mediaUnreadable        = "E1001"
    case mediaTooLarge          = "E1002"
    case mediaMetadataInvalid   = "E1003"
    case photoPermissionDenied  = "E2001"
    case insufficientStorage    = "E2002"
    case detectionFailed        = "E3001"
    case modelLoadFailed        = "E3002"
    case inpaintFailed          = "E4001"
    case openCVBridgeError      = "E4002"
    case exportFailed           = "E5001"
    case audioWriteFailed       = "E5002"
    case colorSpaceFailed       = "E5003"
    case duplicateExportBlocked = "E5004"
    case userCancelled          = "E6001"
    case memoryWarningPaused    = "E7001"
    case backgroundInterrupted  = "E7002"
    case modelUnavailable       = "E8001"
    case videoMetadataInvalid   = "E9001"
    case writerUnavailable      = "E9002"
    case corruptFrameSkipped    = "E9003"
}

extension SubtitleEraserErrorCode {
    var defaultSeverity: SubtitleEraserErrorSeverity {
        switch self {
        case .detectionFailed,
             .modelLoadFailed,
             .corruptFrameSkipped,
             .modelUnavailable:
            return .warning
        case .userCancelled:
            return .info
        default:
            return .error
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    var defaultUserMessage: String {
        switch self {
        case .internalStateError:     return "内部状态异常，请重启页面后重试。"
        case .mediaUnreadable:        return "无法读取素材，请更换文件后重试。"
        case .mediaTooLarge:          return "素材分辨率或时长超出支持范围。"
        case .mediaMetadataInvalid:   return "素材元数据异常，无法处理。"
        case .photoPermissionDenied:  return "未获得相册权限，请在设置中开启。"
        case .insufficientStorage:    return "存储空间不足，请清理后重试。"
        case .detectionFailed:        return "自动检测失败，已切换为手动模式。"
        case .modelLoadFailed:        return "模型加载失败，已降级为规则检测。"
        case .inpaintFailed:          return "修复过程失败，请重试或更换素材。"
        case .openCVBridgeError:      return "底层图像处理异常，请重试。"
        case .exportFailed:           return "导出失败，请检查权限与空间后重试。"
        case .audioWriteFailed:       return "音频写入失败，可尝试无音频导出。"
        case .colorSpaceFailed:       return "色彩空间转换失败，已回退 sRGB。"
        case .duplicateExportBlocked: return "正在导出中，请稍候。"
        case .userCancelled:          return "已取消。"
        case .memoryWarningPaused:    return "内存压力过高，已暂停任务。"
        case .backgroundInterrupted:  return "应用进入后台，任务已中断。"
        case .modelUnavailable:       return "当前设备不支持增强模型，已降级。"
        case .videoMetadataInvalid:   return "视频元数据异常，无法读取。"
        case .writerUnavailable:      return "视频写入组件不可用。"
        case .corruptFrameSkipped:    return "部分帧损坏，已跳过。"
        }
    }
}

struct SubtitleEraserError: LocalizedError, Equatable {
    let code: SubtitleEraserErrorCode
    let severity: SubtitleEraserErrorSeverity
    let userMessage: String
    let underlyingDescription: String?
    let isRetryable: Bool

    var errorDescription: String? {
        "\(code.rawValue) · \(userMessage)"
    }

    var isBlocking: Bool {
        severity == .error
    }

    static func make(_ code: SubtitleEraserErrorCode,
                     underlying: String? = nil,
                     retryable: Bool = false) -> SubtitleEraserError {
        SubtitleEraserError(
            code: code,
            severity: code.defaultSeverity,
            userMessage: code.defaultUserMessage,
            underlyingDescription: underlying,
            isRetryable: retryable
        )
    }
}
