import Foundation
import XCTest
@testable import SuperResApp

final class TemporaryFileManagerTests: XCTestCase {
    private var manager: TemporaryFileManager!

    override func setUp() {
        super.setUp()
        manager = TemporaryFileManager(
            rootDirectoryName: "SubtitleEraserTests-\(UUID().uuidString)"
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: manager.rootURL)
        manager = nil
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
        manager.cleanupAllStale()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertFalse(self.manager.taskDirectoryExists(taskID: firstID))
            XCTAssertFalse(self.manager.taskDirectoryExists(taskID: secondID))
            cleaned.fulfill()
        }
        wait(for: [cleaned], timeout: 1)
    }
}
