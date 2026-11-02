import Foundation

/// Logical cancellation: OpenCV cannot be interrupted, so stale results are discarded by token.
final class InpaintTaskController: @unchecked Sendable {
    private let lock = NSLock()
    private var activeTokenStorage: UUID?

    var activeToken: UUID? {
        lock.lock()
        defer { lock.unlock() }
        return activeTokenStorage
    }

    var isRunning: Bool { activeToken != nil }

    func begin() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        let token = UUID()
        activeTokenStorage = token
        return token
    }

    func isActive(_ token: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeTokenStorage == token
    }

    func finish(_ token: UUID) {
        lock.lock()
        defer { lock.unlock() }
        if activeTokenStorage == token {
            activeTokenStorage = nil
        }
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        activeTokenStorage = nil
    }
}
