import XCTest
import UIKit
@testable import SuperResApp

@MainActor
final class SubtitleEraserViewModelStateTests: XCTestCase {
    private final class MockSaver: PhotoLibrarySaving {
        func requestPermission() async -> Bool { true }
        func save(image: UIImage) async throws {}
    }

    private func makePNG() throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48), format: format).image { context in
            UIColor.systemPink.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
        }
        return try XCTUnwrap(image.pngData())
    }

    private func addStroke(to model: SubtitleEraserViewModel) {
        model.undoManager.appendStroke(MaskStroke(
            tool: .brush,
            brushWidth: 0.2,
            points: [NormalizedPoint(x: 0.3, y: 0.5), NormalizedPoint(x: 0.7, y: 0.5)]
        ))
    }

    func testFullStateSequenceAndReturnToEditing() async throws {
        let model = SubtitleEraserViewModel(photoSaver: MockSaver())
        XCTAssertEqual(model.stateMachine.state, .idle)
        await model.importImage(data: try makePNG())
        XCTAssertEqual(model.stateMachine.state, .editing)
        addStroke(to: model)
        await model.executeInpaint()
        XCTAssertEqual(model.stateMachine.state, .previewing)
        XCTAssertNotNil(model.previewImage)
        model.backToEditing()
        XCTAssertEqual(model.stateMachine.state, .editing)
        XCTAssertNil(model.previewImage)
    }

    func testCompletedCanReturnToEditingAndReset() async throws {
        let model = SubtitleEraserViewModel(photoSaver: MockSaver())
        await model.importImage(data: try makePNG())
        addStroke(to: model)
        await model.executeInpaint()
        await model.saveResult()
        XCTAssertEqual(model.stateMachine.state, .completed)
        model.resetToOriginal()
        XCTAssertEqual(model.stateMachine.state, .editing)
        XCTAssertTrue(model.strokes.isEmpty)
    }

    func testCancelDuringProcessingReturnsToEditing() async throws {
        let model = SubtitleEraserViewModel(photoSaver: MockSaver())
        await model.importImage(data: try makePNG())
        try model.stateMachine.beginProcessing()
        model.cancelCurrent()
        XCTAssertEqual(model.stateMachine.state, .editing)
        XCTAssertEqual(model.lastWarning?.code, .userCancelled)
    }

    func testMemoryWarningInvalidatesBusyTask() async throws {
        let monitor = MemoryMonitor(observeSystem: false)
        let model = SubtitleEraserViewModel(photoSaver: MockSaver(), memoryMonitor: monitor)
        await model.importImage(data: try makePNG())
        try model.stateMachine.beginProcessing()
        monitor.simulateWarning()
        XCTAssertEqual(model.stateMachine.state, .cancelled(reason: .make(.memoryWarningPaused)))
        XCTAssertEqual(model.lastWarning?.code, .memoryWarningPaused)
    }

    func testRetryExportTransitionFromCompleted() throws {
        let machine = SubtitleEraserStateMachine()
        try machine.beginImporting()
        try machine.importSucceeded()
        try machine.detectionSucceeded()
        try machine.beginProcessing()
        try machine.processingSucceeded()
        try machine.beginExporting()
        try machine.exportSucceeded()
        try machine.retryExport()
        if case .exporting = machine.state {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected exporting state")
        }
    }
}
