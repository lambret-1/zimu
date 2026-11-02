import XCTest
@testable import SuperResApp

@MainActor
final class SubtitleEraserStateMachineTests: XCTestCase {
    func testHappyPath() throws {
        let sm = SubtitleEraserStateMachine()
        XCTAssertEqual(sm.state, .idle)
        try sm.beginImporting()
        XCTAssertEqual(sm.state, .importing)
        try sm.importSucceeded()
        XCTAssertEqual(sm.state, .detecting)
        try sm.detectionSucceeded()
        XCTAssertEqual(sm.state, .editing)
        try sm.beginProcessing()
        if case .processing = sm.state {} else { XCTFail("expected processing") }
        sm.updateProcessing(progress: 0.5)
        if case .processing(let progress) = sm.state { XCTAssertEqual(progress, 0.5) }
        try sm.processingSucceeded()
        XCTAssertEqual(sm.state, .previewing)
        try sm.beginExporting()
        try sm.exportSucceeded()
        XCTAssertEqual(sm.state, .completed)
    }

    func testIllegalTransitionThrows() {
        let sm = SubtitleEraserStateMachine()
        XCTAssertThrowsError(try sm.exportSucceeded()) { error in
            let eraserError = error as? SubtitleEraserError
            XCTAssertEqual(eraserError?.code, .internalStateError)
        }
    }

    func testDetectionDegradedEntersEditing() throws {
        let sm = SubtitleEraserStateMachine()
        try sm.beginImporting()
        try sm.importSucceeded()
        XCTAssertEqual(sm.state, .detecting)
        sm.detectionDegraded(.make(.detectionFailed))
        XCTAssertEqual(sm.state, .editing)
        XCTAssertEqual(sm.lastWarning?.code, .detectionFailed)
    }

    func testImportFailureGoesToFailed() {
        let sm = SubtitleEraserStateMachine()
        sm.importFailed(.make(.mediaUnreadable))
        if case .failed(let error) = sm.state {
            XCTAssertEqual(error.code, .mediaUnreadable)
        } else {
            XCTFail("expected failed")
        }
    }

    func testCancelFromProcessing() throws {
        let sm = SubtitleEraserStateMachine()
        try sm.beginImporting()
        try sm.importSucceeded()
        try sm.detectionSucceeded()
        try sm.beginProcessing()
        sm.cancel()
        if case .cancelled = sm.state {} else { XCTFail("expected cancelled") }
    }

    func testResetFromFailed() {
        let sm = SubtitleEraserStateMachine()
        sm.importFailed(.make(.mediaUnreadable))
        sm.reset()
        XCTAssertEqual(sm.state, .idle)
        XCTAssertNil(sm.lastWarning)
    }

    func testProgressClampedToUnitInterval() throws {
        let sm = SubtitleEraserStateMachine()
        try sm.beginImporting()
        try sm.importSucceeded()
        try sm.detectionSucceeded()
        try sm.beginProcessing()
        sm.updateProcessing(progress: 2.0)
        if case .processing(let progress) = sm.state { XCTAssertEqual(progress, 1.0) }
        sm.updateProcessing(progress: -1.0)
        if case .processing(let progress) = sm.state { XCTAssertEqual(progress, 0.0) }
    }

    func testIsBusyAndCanDismiss() throws {
        let sm = SubtitleEraserStateMachine()
        XCTAssertFalse(sm.state.isBusy)
        try sm.beginImporting()
        XCTAssertTrue(sm.state.isBusy)
        XCTAssertFalse(sm.state.canDismiss)
        try sm.importSucceeded()
        try sm.detectionSucceeded()
        XCTAssertFalse(sm.state.isBusy)
        XCTAssertTrue(sm.state.canDismiss)
    }
}
