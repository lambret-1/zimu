import XCTest
import CoreGraphics
@testable import SuperResApp

@MainActor
final class GestureCoordinatorTests: XCTestCase {
    private let canvasSize = CGSize(width: 400, height: 300)

    func testEdgeExclusionBlocksOnlyLeftTwentyPoints() {
        let coordinator = GestureCoordinator(edgeExclusionWidth: 20)
        XCTAssertFalse(coordinator.canStartDrawing(
            at: CGPoint(x: 19.9, y: 150), canvasSize: canvasSize, isProcessing: false
        ))
        XCTAssertTrue(coordinator.canStartDrawing(
            at: CGPoint(x: 20, y: 150), canvasSize: canvasSize, isProcessing: false
        ))
    }

    func testProcessingAndInvalidCanvasBlockDrawing() {
        let coordinator = GestureCoordinator()
        XCTAssertFalse(coordinator.canStartDrawing(
            at: CGPoint(x: 100, y: 150), canvasSize: canvasSize, isProcessing: true
        ))
        XCTAssertFalse(coordinator.canStartDrawing(
            at: CGPoint(x: 100, y: 150), canvasSize: .zero, isProcessing: false
        ))
    }

    func testDrawingStateCycle() {
        let coordinator = GestureCoordinator()
        coordinator.beginDrawing()
        XCTAssertEqual(coordinator.state, .drawing)
        coordinator.endDrawing()
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testPinchInterruptsDrawingAndBlocksNewStroke() {
        let coordinator = GestureCoordinator()
        coordinator.beginDrawing()
        coordinator.interruptForPinch()
        XCTAssertEqual(coordinator.state, .pinching)
        XCTAssertFalse(coordinator.canStartDrawing(
            at: CGPoint(x: 100, y: 150), canvasSize: canvasSize, isProcessing: false
        ))
        coordinator.endPinching()
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testDisableAndEnable() {
        let coordinator = GestureCoordinator()
        coordinator.disable()
        XCTAssertEqual(coordinator.state, .disabled)
        XCTAssertFalse(coordinator.canStartDrawing(
            at: CGPoint(x: 100, y: 150), canvasSize: canvasSize, isProcessing: false
        ))
        coordinator.enable()
        XCTAssertTrue(coordinator.canStartDrawing(
            at: CGPoint(x: 100, y: 150), canvasSize: canvasSize, isProcessing: false
        ))
    }

    func testEdgeReturnOwnsGestureUntilEnded() {
        let coordinator = GestureCoordinator()
        coordinator.beginEdgeReturn()
        XCTAssertEqual(coordinator.state, .edgeReturn)
        XCTAssertFalse(coordinator.canStartDrawing(
            at: CGPoint(x: 100, y: 150), canvasSize: canvasSize, isProcessing: false
        ))
        coordinator.endEdgeReturn()
        XCTAssertEqual(coordinator.state, .idle)
    }
}
