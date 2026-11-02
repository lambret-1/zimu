import Combine
import Foundation
import UIKit

@MainActor
final class SubtitleEraserViewModel: ObservableObject {
    @Published private(set) var displayImage: UIImage?
    @Published private(set) var previewImage: UIImage?
    @Published private(set) var pixelSize: CGSize = .zero
    @Published private(set) var latestError: SubtitleEraserError?
    @Published private(set) var lastSaveSucceeded = false
    @Published var tool: MaskBrushTool = .brush
    @Published var brushWidth: CGFloat = 20
    @Published var showComparison = false
    @Published var comparisonSlider = 0.5

    let stateMachine: SubtitleEraserStateMachine
    let undoManager: MaskUndoManager
    let gestureCoordinator: GestureCoordinator

    private var originalBGRA: Data?
    private var originalHasAlpha = false

    init(
        stateMachine: SubtitleEraserStateMachine = SubtitleEraserStateMachine(),
        undoManager: MaskUndoManager = MaskUndoManager(),
        gestureCoordinator: GestureCoordinator = GestureCoordinator()
    ) {
        self.stateMachine = stateMachine
        self.undoManager = undoManager
        self.gestureCoordinator = gestureCoordinator
    }

    var canExecute: Bool {
        !undoManager.strokes.isEmpty && stateMachine.state == .editing && displayImage != nil
    }

    var canSave: Bool {
        previewImage != nil && stateMachine.state == .previewing
    }

    var isProcessing: Bool { stateMachine.state.isBusy }
    var canDismiss: Bool { stateMachine.state.canDismiss }

    func importImage(data: Data) async {
        latestError = nil
        lastSaveSucceeded = false
        if stateMachine.state != .idle {
            stateMachine.reset()
        }
        do {
            try stateMachine.beginImporting()
            let loaded = try await Task.detached(priority: .userInitiated) {
                try ImageMetadataService.load(from: data)
            }.value
            displayImage = loaded.displayImage
            pixelSize = loaded.pixelSize
            originalBGRA = loaded.bgra
            originalHasAlpha = loaded.hasAlpha
            previewImage = nil
            showComparison = false
            undoManager.reset()
            try stateMachine.importSucceeded()
            try stateMachine.detectionSucceeded()
        } catch {
            let failure = normalize(error, fallback: .mediaUnreadable)
            latestError = failure
            stateMachine.importFailed(failure)
        }
    }

    func executeInpaint() async {
        latestError = nil
        guard let source = originalBGRA, !undoManager.strokes.isEmpty else {
            latestError = .make(.inpaintFailed, underlying: "missing image or strokes")
            return
        }
        let width = Int(pixelSize.width)
        let height = Int(pixelSize.height)
        guard width > 0, height > 0 else {
            latestError = .make(.mediaMetadataInvalid)
            return
        }
        do {
            if case .failed = stateMachine.state {
                stateMachine.returnToEditing()
            }
            try stateMachine.beginProcessing()
            let strokeSnapshot = undoManager.strokes
            let result = try await Task.detached(priority: .userInitiated) {
                let mask = try MaskProcessor.rasterize(
                    strokes: strokeSnapshot,
                    targetSize: CGSize(width: width, height: height)
                )
                return try InpaintEngine.inpaint(
                    imageBGRA: source,
                    mask: mask,
                    width: width,
                    height: height,
                    radius: InpaintEngine.defaultRadius
                )
            }.value
            let image = try await Task.detached(priority: .userInitiated) {
                try ImageExportService.uiImage(fromBGRA: result, width: width, height: height)
            }.value
            previewImage = image
            showComparison = true
            try stateMachine.processingSucceeded()
        } catch {
            let failure = normalize(error, fallback: .inpaintFailed)
            latestError = failure
            stateMachine.processingFailed(failure)
            stateMachine.returnToEditing()
        }
    }

    func saveResult() async {
        latestError = nil
        lastSaveSucceeded = false
        guard let image = previewImage else {
            latestError = .make(.exportFailed, underlying: "preview image unavailable")
            return
        }
        do {
            if case .failed = stateMachine.state {
                stateMachine.returnToPreviewing()
            }
            try stateMachine.beginExporting()
            guard await PhotoLibraryPermissionService.requestAddOnly() else {
                throw SubtitleEraserError.make(.photoPermissionDenied, retryable: true)
            }
            guard StorageSpaceService.hasEnoughSpace() else {
                throw SubtitleEraserError.make(.insufficientStorage, retryable: true)
            }
            try await ImageExportService.saveToPhotoLibrary(image: image)
            try stateMachine.exportSucceeded()
            lastSaveSucceeded = true
        } catch {
            let failure = normalize(error, fallback: .exportFailed)
            latestError = failure
            stateMachine.exportFailed(failure)
            stateMachine.returnToPreviewing()
        }
    }

    func resumeEditing() {
        guard previewImage != nil else { return }
        stateMachine.returnToEditing()
        showComparison = false
    }

    func resetToOriginal() {
        previewImage = nil
        showComparison = false
        comparisonSlider = 0.5
        undoManager.reset()
        stateMachine.returnToEditing()
    }

    func cancelCurrent() {
        stateMachine.cancel()
        gestureCoordinator.reset()
    }

    private func normalize(_ error: Error, fallback: SubtitleEraserErrorCode) -> SubtitleEraserError {
        (error as? SubtitleEraserError)
            ?? .make(fallback, underlying: error.localizedDescription)
    }
}
