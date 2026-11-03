#if DEBUG
import Foundation

@MainActor
final class DebugSettingsStore {
    static let shared = DebugSettingsStore()
    var panelEnabled = false
    var useMaskRefiner = true

    private init() {}
}
#endif
