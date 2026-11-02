import XCTest
import UIKit
@testable import SuperResApp

@MainActor
final class PhotoLibrarySavingTests: XCTestCase {
    private final class MockSaver: PhotoLibrarySaving {
        var grantPermission = true
        var saveError: Error?
        private(set) var saveCallCount = 0

        func requestPermission() async -> Bool { grantPermission }

        func save(image: UIImage) async throws {
            saveCallCount += 1
            if let saveError { throw saveError }
        }
    }

    private func makePNG() throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
        }
        return try XCTUnwrap(image.pngData())
    }

    private func preparePreview(_ viewModel: SubtitleEraserViewModel) async throws {
        await viewModel.importImage(data: try makePNG())
        viewModel.undoManager.appendStroke(MaskStroke(
            tool: .brush,
            brushWidth: 0.2,
            points: [NormalizedPoint(x: 0.25, y: 0.5), NormalizedPoint(x: 0.75, y: 0.5)]
        ))
        await viewModel.executeInpaint()
        XCTAssertNotNil(viewModel.previewImage)
    }

    func testSaveSucceedsWhenPermissionGranted() async throws {
        let saver = MockSaver()
        let model = SubtitleEraserViewModel(photoSaver: saver)
        try await preparePreview(model)
        await model.saveResult()
        XCTAssertEqual(saver.saveCallCount, 1)
        XCTAssertTrue(model.lastSaveSucceeded)
        XCTAssertEqual(model.stateMachine.state, .completed)
    }

    func testSaveFailsWhenPermissionDenied() async throws {
        let saver = MockSaver()
        saver.grantPermission = false
        let model = SubtitleEraserViewModel(photoSaver: saver)
        try await preparePreview(model)
        await model.saveResult()
        XCTAssertEqual(saver.saveCallCount, 0)
        XCTAssertEqual(model.latestError?.code, .photoPermissionDenied)
        XCTAssertEqual(model.stateMachine.state, .previewing)
    }

    func testSaveCanBeRetriedAfterSaverError() async throws {
        let saver = MockSaver()
        saver.saveError = SubtitleEraserError.make(.exportFailed, underlying: "test")
        let model = SubtitleEraserViewModel(photoSaver: saver)
        try await preparePreview(model)
        await model.saveResult()
        XCTAssertEqual(model.latestError?.code, .exportFailed)
        XCTAssertEqual(model.stateMachine.state, .previewing)
        saver.saveError = nil
        await model.saveResult()
        XCTAssertEqual(saver.saveCallCount, 2)
        XCTAssertTrue(model.lastSaveSucceeded)
        XCTAssertEqual(model.stateMachine.state, .completed)
    }
}
