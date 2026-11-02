import Combine
import CoreGraphics
import Foundation

enum CanvasGestureState: Equatable {
    case idle
    case drawing
    case pinching
    case edgeReturn
    case disabled

    var allowsDrawing: Bool {
        self == .idle || self == .drawing
    }
}

@MainActor
final class GestureCoordinator: ObservableObject {
    @Published private(set) var state: CanvasGestureState = .idle
    let edgeExclusionWidth: CGFloat

    init(edgeExclusionWidth: CGFloat = 20) {
        self.edgeExclusionWidth = max(0, edgeExclusionWidth)
    }

    func canStartDrawing(at point: CGPoint, canvasSize: CGSize, isProcessing: Bool) -> Bool {
        guard !isProcessing,
              canvasSize.width > 0,
              canvasSize.height > 0,
              state.allowsDrawing else { return false }
        return point.x >= edgeExclusionWidth
    }

    func beginDrawing() {
        guard state == .idle else { return }
        state = .drawing
    }

    func endDrawing() {
        guard state == .drawing else { return }
        state = .idle
    }

    func interruptForPinch() {
        if state == .drawing { state = .pinching }
    }

    func beginPinching() {
        state = .pinching
    }

    func endPinching() {
        guard state == .pinching else { return }
        state = .idle
    }

    func beginEdgeReturn() {
        guard state == .idle else { return }
        state = .edgeReturn
    }

    func endEdgeReturn() {
        guard state == .edgeReturn else { return }
        state = .idle
    }

    func disable() {
        state = .disabled
    }

    func enable() {
        guard state == .disabled else { return }
        state = .idle
    }

    func reset() {
        state = .idle
    }
}
