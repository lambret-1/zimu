import Foundation

enum StorageSpaceService {
    static let minimumBytes: Int64 = 500 * 1024 * 1024

    static func availableBytes() -> Int64 {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        guard let values = try? home.resourceValues(forKeys: keys) else { return 0 }
        return values.volumeAvailableCapacityForImportantUsage
            ?? Int64(values.volumeAvailableCapacity ?? 0)
    }

    static func hasEnoughSpace(minimumBytes: Int64 = minimumBytes) -> Bool {
        availableBytes() >= max(0, minimumBytes)
    }
}
