import Foundation
import Photos

enum PhotoLibraryPermissionService {
    static func requestAddOnly() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            let requested = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            return requested == .authorized || requested == .limited
        @unknown default:
            return false
        }
    }
}
