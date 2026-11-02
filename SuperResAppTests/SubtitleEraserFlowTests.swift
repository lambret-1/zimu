import XCTest
import UIKit
@testable import SuperResApp

@MainActor
final class SubtitleEraserFlowTests: XCTestCase {
    private func makeSourceImage() throws -> Data {
        let size = CGSize(width: 64, height: 64)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 48, width: 64, height: 10))
        }
        return try XCTUnwrap(image.pngData())
    }

    func testImportDrawInpaintAndPreviewCompletesEndToEnd() async throws {
        let viewModel = SubtitleEraserViewModel()
        await viewModel.importImage(data: try makeSourceImage())

        XCTAssertEqual(viewModel.stateMachine.state, .editing)
        XCTAssertEqual(viewModel.pixelSize, CGSize(width: 64, height: 64))
        XCTAssertFalse(viewModel.canExecute)

        viewModel.undoManager.appendStroke(MaskStroke(
            tool: .brush,
            brushWidth: 0.15,
            points: [
                NormalizedPoint(x: 0.2, y: 0.8),
                NormalizedPoint(x: 0.8, y: 0.8)
            ]
        ))
        XCTAssertTrue(viewModel.canExecute)

        await viewModel.executeInpaint()

        XCTAssertEqual(viewModel.stateMachine.state, .previewing)
        XCTAssertNotNil(viewModel.previewImage, "BGRA → UIImage preview conversion must succeed")
        XCTAssertEqual(viewModel.previewImage?.imageOrientation, .up)
    }

    func testExecuteWithoutStrokesDoesNotEnterPreview() async throws {
        let viewModel = SubtitleEraserViewModel()
        await viewModel.importImage(data: try makeSourceImage())

        await viewModel.executeInpaint()

        XCTAssertNotEqual(viewModel.stateMachine.state, .previewing)
        XCTAssertNotNil(viewModel.latestError)
    }

    func testResumeEditingAllowsSecondPass() async throws {
        let viewModel = SubtitleEraserViewModel()
        await viewModel.importImage(data: try makeSourceImage())
        viewModel.undoManager.appendStroke(MaskStroke(
            tool: .brush,
            brushWidth: 0.12,
            points: [NormalizedPoint(x: 0.5, y: 0.8)]
        ))
        await viewModel.executeInpaint()
        XCTAssertEqual(viewModel.stateMachine.state, .previewing)

        viewModel.resumeEditing()

        XCTAssertEqual(viewModel.stateMachine.state, .editing)
        XCTAssertFalse(viewModel.showComparison)
    }
}
