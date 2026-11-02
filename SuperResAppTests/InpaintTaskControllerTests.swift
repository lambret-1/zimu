import XCTest
@testable import SuperResApp

final class InpaintTaskControllerTests: XCTestCase {
    func testBeginAndFinish() {
        let controller = InpaintTaskController()
        let token = controller.begin()
        XCTAssertTrue(controller.isActive(token))
        XCTAssertTrue(controller.isRunning)
        controller.finish(token)
        XCTAssertFalse(controller.isActive(token))
        XCTAssertFalse(controller.isRunning)
    }

    func testCancelInvalidatesToken() {
        let controller = InpaintTaskController()
        let token = controller.begin()
        controller.cancel()
        XCTAssertFalse(controller.isActive(token))
        XCTAssertFalse(controller.isRunning)
    }

    func testSecondBeginReplacesFirstToken() {
        let controller = InpaintTaskController()
        let first = controller.begin()
        let second = controller.begin()
        XCTAssertFalse(controller.isActive(first))
        XCTAssertTrue(controller.isActive(second))
    }

    func testFinishingStaleTokenDoesNotClearCurrentToken() {
        let controller = InpaintTaskController()
        let stale = controller.begin()
        controller.cancel()
        let current = controller.begin()
        controller.finish(stale)
        XCTAssertTrue(controller.isActive(current))
    }
}
