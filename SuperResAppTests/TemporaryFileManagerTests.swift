import Foundation
import XCTest
@testable import SuperResApp

final class TemporaryFileManagerTests: XCTestCase {
    private let manager = TemporaryFileManager(
        rootDirectoryName: "SubtitleEraserTests-\(UUID().uuidString)"
    )

    override func tearDown() {
        try? FileManager.default.removeItem(at: manager.rootURL)
        super.tearDown()
    }

    func testMakeTaskDirectoryCreatesFolder() throws {
        let taskID = UUID()
        let directory = try manager.makeTaskDirectory(taskID: taskID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertTrue(manager.taskDirectoryExists(taskID: taskID))
    }

    func testMakeTaskDirectoryIsIdempotent() throws {
        let taskID = UUID()
        _ = try manager.makeTaskDirectory(taskID: taskID)
        _ = try manager.makeTaskDirectory(taskID: taskID)
        XCTAssertTrue(manager.taskDirectoryExists(taskID: taskID))
    }

    func testTaskDirectoriesAreIsolated() throws {
        let firstID = UUID()
        let secondID = UUID()
        let first = try manager.makeTaskDirectory(taskID: firstID)
        let second = try manager.makeTaskDirectory(taskID: secondID)
        XCTAssertNotEqual(first, second)
    }

    func testCleanupRemovesDirectoryAndContents() throws {
        let taskID = UUID()
        let directory = try manager.makeTaskDirectory(taskID: taskID)
        let file = directory.appendingPathComponent("fixture.bin")
        XCTAssertTrue(FileManager.default.createFile(
            atPath: file.path,
            contents: Data(repeating: 0, count: 16)
        ))

        manager.cleanupSynchronously(taskID: taskID)
        XCTAssertFalse(manager.taskDirectoryExists(taskID: taskID))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testCleanupAllStale() throws {
        let firstID = UUID()
        let secondID = UUID()
        _ = try manager.makeTaskDirectory(taskID: firstID)
        _ = try manager.makeTaskDirectory(taskID: secondID)

        let cleaned = expectation(description: "temporary task directories cleaned")
        manager.cleanupAllStale {
            cleaned.fulfill()
        }
        // CI simulators can be heavily loaded; allow the serial utility queue
        // enough time to enumerate and remove both directories before asserting.
        wait(for: [cleaned], timeout: 5)
        XCTAssertFalse(manager.taskDirectoryExists(taskID: firstID))
        XCTAssertFalse(manager.taskDirectoryExists(taskID: secondID))
    }
}
