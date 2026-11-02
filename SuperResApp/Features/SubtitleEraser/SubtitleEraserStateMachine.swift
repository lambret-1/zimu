import Foundation
import Combine

enum SubtitleEraserState: Equatable {
    case idle
    case importing
    case detecting
    case editing
    case processing(progress: Double)
    case previewing
    case exporting(progress: Double)
    case completed
    case failed(SubtitleEraserError)
    case cancelled(reason: SubtitleEraserError?)

    var isBusy: Bool {
        switch self {
        case .importing, .detecting, .processing, .exporting:
            return true
        default:
            return false
        }
    }

    var isInteractive: Bool {
        switch self {
        case .editing, .previewing, .completed, .failed:
            return true
        default:
            return false
        }
    }

    /// 是否允许下拉/返回关闭全屏页
    var canDismiss: Bool {
        !isBusy
    }
}

@MainActor
final class SubtitleEraserStateMachine: ObservableObject {
    @Published private(set) var state: SubtitleEraserState = .idle
    @Published private(set) var lastWarning: SubtitleEraserError?

    // MARK: - 导入

    func beginImporting() throws {
        try transitionTo(.importing)
    }

    func importSucceeded() throws {
        try transitionTo(.detecting)
    }

    func importFailed(_ error: SubtitleEraserError) {
        state = .failed(error)
    }

    // MARK: - 检测

    func detectionSucceeded() throws {
        try transitionTo(.editing)
    }

    /// 检测降级：记录警告并进入 editing，不阻塞主流程
    func detectionDegraded(_ warning: SubtitleEraserError) {
        lastWarning = warning
        if case .detecting = state {
            state = .editing
        }
    }

    // MARK: - 处理

    func beginProcessing() throws {
        try transitionTo(.processing(progress: 0))
    }

    func updateProcessing(progress: Double) {
        if case .processing = state {
            state = .processing(progress: clamp(progress))
        }
    }

    func processingSucceeded() throws {
        try transitionTo(.previewing)
    }

    func processingFailed(_ error: SubtitleEraserError) {
        state = .failed(error)
    }

    // MARK: - 导出

    func beginExporting() throws {
        try transitionTo(.exporting(progress: 0))
    }

    func updateExporting(progress: Double) {
        if case .exporting = state {
            state = .exporting(progress: clamp(progress))
        }
    }

    func exportSucceeded() throws {
        try transitionTo(.completed)
    }

    func exportFailed(_ error: SubtitleEraserError) {
        state = .failed(error)
    }

    // MARK: - 取消 / 重置

    func cancel(reason: SubtitleEraserError = .make(.userCancelled)) {
        state = .cancelled(reason: reason)
    }

    func reset() {
        state = .idle
        lastWarning = nil
    }

    // MARK: - 内部

    private func transitionTo(_ newState: SubtitleEraserState) throws {
        guard Self.allowedTransition(from: state, to: newState) else {
            throw SubtitleEraserError.make(
                .internalStateError,
                underlying: "非法状态转换 \(Self.describe(state)) -> \(Self.describe(newState))"
            )
        }
        state = newState
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    static func allowedTransition(from: SubtitleEraserState,
                                  to: SubtitleEraserState) -> Bool {
        switch (from, to) {
        case (.idle, .importing):          return true
        case (.importing, .detecting):     return true
        case (.detecting, .editing):       return true
        case (.editing, .processing):      return true
        case (.processing, .previewing):   return true
        case (.previewing, .exporting):    return true
        case (.exporting, .completed):     return true
        case (_, .failed), (_, .cancelled), (_, .idle):
            return true
        default:
            return false
        }
    }

    static func describe(_ state: SubtitleEraserState) -> String {
        switch state {
        case .idle: return "idle"
        case .importing: return "importing"
        case .detecting: return "detecting"
        case .editing: return "editing"
        case .processing(let progress): return "processing(\(progress))"
        case .previewing: return "previewing"
        case .exporting(let progress): return "exporting(\(progress))"
        case .completed: return "completed"
        case .failed(let error): return "failed(\(error.code.rawValue))"
        case .cancelled: return "cancelled"
        }
    }
}
