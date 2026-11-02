import Foundation

/// Manages per-task temporary directories used by media processing.
final class TemporaryFileManager {
    static let shared = TemporaryFileManager()

    let rootURL: URL

    private let fileManager: FileManager
    private let cleanupQueue = DispatchQueue(
        label: "TemporaryFileManager.cleanup",
        qos: .utility
    )

    init(fileManager: FileManager = .default, rootDirectoryName: String = "SubtitleEraser") {
        self.fileManager = fileManager
        rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(rootDirectoryName, isDirectory: true)
        try? fileManager.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
    }

    @discardableResult
    func makeTaskDirectory(taskID: UUID) throws -> URL {
        let directory = taskDirectoryURL(taskID: taskID)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    func cleanup(taskID: UUID) {
        let directory = taskDirectoryURL(taskID: taskID)
        let manager = fileManager
        cleanupQueue.async {
            try? manager.removeItem(at: directory)
        }
    }

    func cleanupSynchronously(taskID: UUID) {
        try? fileManager.removeItem(at: taskDirectoryURL(taskID: taskID))
    }

    func cleanupAllStale(completion: (() -> Void)? = nil) {
        let root = rootURL
        let manager = fileManager
        cleanupQueue.async {
            defer { completion?() }
            guard let items = try? manager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil
            ) else {
                return
            }
            items.forEach { try? manager.removeItem(at: $0) }
        }
    }

    func taskDirectoryExists(taskID: UUID) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(
            atPath: taskDirectoryURL(taskID: taskID).path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }

    private func taskDirectoryURL(taskID: UUID) -> URL {
        rootURL.appendingPathComponent(taskID.uuidString, isDirectory: true)
    }
}
