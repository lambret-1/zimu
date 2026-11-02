import XCTest
@testable import SuperResApp

final class SubtitleEraserErrorTests: XCTestCase {
    func testWarningCodesHaveWarningSeverity() {
        let warnings: [SubtitleEraserErrorCode] = [
            .detectionFailed, .modelLoadFailed, .corruptFrameSkipped, .modelUnavailable
        ]
        for code in warnings {
            XCTAssertEqual(code.defaultSeverity, .warning, "\(code.rawValue)")
        }
    }

    func testCancelledIsInfo() {
        XCTAssertEqual(SubtitleEraserErrorCode.userCancelled.defaultSeverity, .info)
    }

    func testBlockingCodesHaveErrorSeverity() {
        let blocking: [SubtitleEraserErrorCode] = [
            .internalStateError, .mediaUnreadable, .mediaTooLarge, .mediaMetadataInvalid,
            .photoPermissionDenied, .insufficientStorage, .inpaintFailed, .openCVBridgeError,
            .exportFailed, .audioWriteFailed, .colorSpaceFailed, .duplicateExportBlocked,
            .memoryWarningPaused, .backgroundInterrupted, .videoMetadataInvalid, .writerUnavailable
        ]
        for code in blocking {
            XCTAssertEqual(code.defaultSeverity, .error, "\(code.rawValue)")
        }
    }

    func testMakeBuildsErrorDescriptionWithCode() {
        let error = SubtitleEraserError.make(.mediaUnreadable)
        XCTAssertTrue(error.errorDescription?.contains("E1001") == true)
        XCTAssertTrue(error.isBlocking)
        XCTAssertFalse(error.isRetryable)
    }

    func testRetryableFlagIsPreserved() {
        let error = SubtitleEraserError.make(.exportFailed, retryable: true)
        XCTAssertTrue(error.isRetryable)
    }

    func testWarningIsNotBlocking() {
        let warning = SubtitleEraserError.make(.detectionFailed)
        XCTAssertFalse(warning.isBlocking)
    }
}
