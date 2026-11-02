import Combine
import Foundation

/// Stroke history with bounded undo/redo snapshots.
@MainActor
final class MaskUndoManager: ObservableObject {
    @Published private(set) var strokes: [MaskStroke] = []
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    let maxSteps: Int
    let maxMemoryBytes: Int

    private var undoStack: [[MaskStroke]] = []
    private var redoStack: [[MaskStroke]] = []

    init(maxSteps: Int = 20, maxMemoryBytes: Int = 8 * 1024 * 1024) {
        self.maxSteps = max(1, maxSteps)
        self.maxMemoryBytes = max(64 * 1024, maxMemoryBytes)
    }

    func appendStroke(_ stroke: MaskStroke) {
        guard !stroke.points.isEmpty,
              estimatedBytes(for: strokes + [stroke]) <= maxMemoryBytes else { return }
        undoStack.append(strokes)
        if undoStack.count > maxSteps {
            undoStack.removeFirst(undoStack.count - maxSteps)
        }
        strokes.append(stroke)
        redoStack.removeAll()
        trimForMemory()
        refreshFlags()
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(strokes)
        strokes = snapshot
        trimForMemory()
        refreshFlags()
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(strokes)
        strokes = snapshot
        trimForMemory()
        refreshFlags()
    }

    func reset() {
        guard !strokes.isEmpty else { return }
        undoStack.append(strokes)
        if undoStack.count > maxSteps {
            undoStack.removeFirst(undoStack.count - maxSteps)
        }
        strokes.removeAll()
        redoStack.removeAll()
        trimForMemory()
        refreshFlags()
    }

    func releaseCaches() {
        redoStack.removeAll()
        if let latest = undoStack.last {
            undoStack = [latest]
        } else {
            undoStack.removeAll()
        }
        trimForMemory()
        refreshFlags()
    }

    private func refreshFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    private func trimForMemory() {
        while estimatedTotalBytes() > maxMemoryBytes, !undoStack.isEmpty {
            undoStack.removeFirst()
        }
        while estimatedTotalBytes() > maxMemoryBytes, !redoStack.isEmpty {
            redoStack.removeFirst()
        }
    }

    private func estimatedTotalBytes() -> Int {
        let historyBytes = (undoStack + redoStack).reduce(0) {
            addingSaturated($0, estimatedBytes(for: $1))
        }
        return addingSaturated(estimatedBytes(for: strokes), historyBytes)
    }

    private func estimatedBytes(for values: [MaskStroke]) -> Int {
        values.reduce(0) { total, stroke in
            let pointBytes = stroke.points.count.multipliedReportingOverflow(by: 16)
            let bytes = addingSaturated(64, pointBytes.overflow ? Int.max : pointBytes.partialValue)
            return addingSaturated(total, bytes)
        }
    }

    private func addingSaturated(_ lhs: Int, _ rhs: Int) -> Int {
        let sum = lhs.addingReportingOverflow(rhs)
        return sum.overflow ? Int.max : sum.partialValue
    }
}
