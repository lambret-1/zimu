import Foundation
import UIKit

@MainActor
final class MemoryMonitor {
    static let shared = MemoryMonitor()

    private(set) var warningCount = 0
    var onMemoryWarning: (() -> Void)?
    private var observer: NSObjectProtocol?

    init(observeSystem: Bool = true) {
        guard observeSystem else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleWarning() }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func handleWarning() {
        warningCount += 1
        onMemoryWarning?()
    }

    #if DEBUG
    func simulateWarning() {
        handleWarning()
    }
    #endif
}
