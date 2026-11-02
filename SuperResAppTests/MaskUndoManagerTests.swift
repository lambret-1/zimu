import XCTest
@testable import SuperResApp

@MainActor
final class MaskUndoManagerTests: XCTestCase {
    private func makeStroke(
        _ x: Double = 0.5,
        tool: MaskBrushTool = .brush,
        pointCount: Int = 2
    ) -> MaskStroke {
        let points = (0..<pointCount).map { index in
            NormalizedPoint(x: min(1, x + Double(index) * 0.001), y: 0.5)
        }
        return MaskStroke(tool: tool, brushWidth: 0.05, points: points)
    }

    func testAppendUndoAndRedo() {
        let manager = MaskUndoManager()
        manager.appendStroke(makeStroke(0.1))
        manager.appendStroke(makeStroke(0.2))
        XCTAssertEqual(manager.strokes.count, 2)
        XCTAssertTrue(manager.canUndo)
        XCTAssertFalse(manager.canRedo)

        manager.undo()
        XCTAssertEqual(manager.strokes.count, 1)
        XCTAssertTrue(manager.canRedo)
        manager.undo()
        XCTAssertTrue(manager.strokes.isEmpty)
        XCTAssertFalse(manager.canUndo)

        manager.redo()
        XCTAssertEqual(manager.strokes.count, 1)
        manager.redo()
        XCTAssertEqual(manager.strokes.count, 2)
        XCTAssertFalse(manager.canRedo)
    }

    func testNewAppendClearsRedoHistory() {
        let manager = MaskUndoManager()
        manager.appendStroke(makeStroke(0.1))
        manager.undo()
        XCTAssertTrue(manager.canRedo)
        manager.appendStroke(makeStroke(0.3))
        XCTAssertFalse(manager.canRedo)
        XCTAssertEqual(manager.strokes.count, 1)
    }

    func testEmptyStrokeIsIgnored() {
        let manager = MaskUndoManager()
        manager.appendStroke(MaskStroke(tool: .brush, brushWidth: 0.05, points: []))
        XCTAssertTrue(manager.strokes.isEmpty)
        XCTAssertFalse(manager.canUndo)
    }

    func testMaxUndoStepsAreEnforced() {
        let manager = MaskUndoManager(maxSteps: 3)
        for index in 0..<10 {
            manager.appendStroke(makeStroke(Double(index) * 0.01))
        }
        var undoCount = 0
        while manager.canUndo {
            manager.undo()
            undoCount += 1
        }
        XCTAssertEqual(undoCount, 3)
    }

    func testResetIsUndoableAndClearsRedo() {
        let manager = MaskUndoManager()
        manager.appendStroke(makeStroke(0.1))
        manager.appendStroke(makeStroke(0.2))
        manager.reset()
        XCTAssertTrue(manager.strokes.isEmpty)
        XCTAssertTrue(manager.canUndo)
        XCTAssertFalse(manager.canRedo)
        manager.undo()
        XCTAssertEqual(manager.strokes.count, 2)
    }

    func testReleaseCachesDropsRedoAndOlderUndoSnapshots() {
        let manager = MaskUndoManager()
        manager.appendStroke(makeStroke(0.1))
        manager.appendStroke(makeStroke(0.2))
        manager.undo()
        XCTAssertTrue(manager.canRedo)
        manager.releaseCaches()
        XCTAssertFalse(manager.canRedo)
        XCTAssertTrue(manager.canUndo)
    }

    func testMemoryBudgetRejectsOversizedSingleStroke() {
        let manager = MaskUndoManager(maxMemoryBytes: 65_536)
        manager.appendStroke(makeStroke(pointCount: 5_000))
        XCTAssertTrue(manager.strokes.isEmpty)
        XCTAssertFalse(manager.canUndo)
    }

    func testEraserRemainsAnUndoableStroke() {
        let manager = MaskUndoManager()
        manager.appendStroke(makeStroke(tool: .eraser))
        XCTAssertEqual(manager.strokes.first?.tool, .eraser)
        manager.undo()
        XCTAssertTrue(manager.strokes.isEmpty)
    }
}
