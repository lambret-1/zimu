import UIKit

protocol PhotoLibrarySaving {
    func requestPermission() async -> Bool
    func save(image: UIImage) async throws
}

struct SystemPhotoLibrarySaver: PhotoLibrarySaving {
    func requestPermission() async -> Bool {
        await PhotoLibraryPermissionService.requestAddOnly()
    }

    func save(image: UIImage) async throws {
        try await ImageExportService.saveToPhotoLibrary(image: image)
    }
}
