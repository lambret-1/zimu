import Foundation

enum FeatureFlags {
    #if DEBUG
    @MainActor
    static var debugPanelEnabled: Bool {
        DebugSettingsStore.shared.panelEnabled
    }
    #endif

    static let featherEnabled = true
}
