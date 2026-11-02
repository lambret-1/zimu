import Foundation
import os

/// Redacted application logger. Never pass image data, file paths, or user identifiers.
enum Logger {
    private static let osLogger: os.Logger = {
        let subsystem = Bundle.main.bundleIdentifier ?? "SuperResApp"
        return os.Logger(subsystem: subsystem, category: "app")
    }()

    enum Level: String {
        case debug
        case info
        case warning
        case error
    }

    static func log(_ level: Level, _ message: String) {
        switch level {
        case .debug:
            osLogger.debug("\(message, privacy: .public)")
        case .info:
            osLogger.info("\(message, privacy: .public)")
        case .warning:
            osLogger.warning("\(message, privacy: .public)")
        case .error:
            osLogger.error("\(message, privacy: .public)")
        }
    }

    static func debug(_ message: String) { log(.debug, message) }
    static func info(_ message: String) { log(.info, message) }
    static func warning(_ message: String) { log(.warning, message) }
    static func error(_ message: String) { log(.error, message) }
}
