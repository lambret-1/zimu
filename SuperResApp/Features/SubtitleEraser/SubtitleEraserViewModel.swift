import Combine
import Foundation
import UIKit

@MainActor
final class SubtitleEraserViewModel: ObservableObject {
    @Published private(set) var displayImage: UIImage?
    @Published private(set) var previewImage: UIImage?
    @Published private(set) var activeAutoMask: Data?
    @Published private(set) var autoMaskPreview: [NormalizedRect] = []
    @Published private(set) var pixelSize: CGSize = .zero
    @Published private(set) var latestError: SubtitleEraserError?
    @Published private(set) var lastWarning: SubtitleEraserError?
    @Published private(set) var lastSaveSucceeded = false
    @Published var showExitConfirm = false

    @Published var tool: MaskBrushTool = .brush
    @Published var brushWidth: CGFloat = 20
    @Published var showComparison = false
    @Published var comparisonSlider = 0.5

    let stateMachine: SubtitleEraserStateMachine
    let undoManager: MaskUndoManager
    let gestureCoordinator: GestureCoordinator

    private let photoSaver: PhotoLibrarySaving
    private let taskController: InpaintTaskController
    private let memoryMonitor: MemoryMonitor
    private var originalBGRA: Data?

    init(
        photoSaver: PhotoLibrarySaving = SystemPhotoLibrarySaver(),
        taskController: InpaintTaskController = InpaintTaskController(),
        memoryMonitor: MemoryMonitor? = nil
    ) {
        self.photoSaver = photoSaver
        self.taskController = taskController
        let monitor = memoryMonitor ?? MemoryMonitor.shared
        self.memoryMonitor = monitor
        stateMachine = SubtitleEraserStateMachine()
        undoManager = MaskUndoManager()
        gestureCoordinator = GestureCoordinator()
        monitor.onMemoryWarning = { [weak self] in
            self?.handleMemoryWarning()
        }
    }

    var strokes: [MaskStroke] { undoManager.strokes }
    var isProcessing: Bool { stateMachine.state.isBusy }
    var canDismiss: Bool { stateMachine.state.canDismiss }

    var canExecute: Bool {
        guard displayImage != nil,
              !undoManager.strokes.isEmpty || activeAutoMask != nil else { return false }
        switch stateMachine.state {
        case .editing, .previewing: return true
        default: return false
        }
    }

    var canAutoDetect: Bool {
        displayImage != nil && stateMachine.state == .editing
    }

    var canSave: Bool {
        previewImage != nil && (stateMachine.state == .previewing || stateMachine.state == .completed)
    }

    var canReturnToEditing: Bool {
        stateMachine.state == .previewing || stateMachine.state == .completed
    }

    func importImage(data: Data) async {
        latestError = nil
        lastWarning = nil
        lastSaveSucceeded = false
        taskController.cancel()
        do {
            if stateMachine.state != .idle {
                stateMachine.reset()
            }
            try stateMachine.beginImporting()
            let loaded = try await Task.detached(priority: .userInitiated) {
                try ImageMetadataService.load(from: data)
            }.value
            displayImage = loaded.displayImage
            pixelSize = loaded.pixelSize
            originalBGRA = loaded.bgra
            undoManager.reset()
            activeAutoMask = nil
            autoMaskPreview = []
            previewImage = nil
            showComparison = false
            comparisonSlider = 0.5
            try stateMachine.importSucceeded()
            try stateMachine.detectionSucceeded()
            Logger.info("image import succeeded")
        } catch {
            fail(with: error, fallback: .mediaUnreadable)
        }
    }

    /// Runs on-device Vision text recognition, filters the lower subtitle band, then refines the mask.
    func autoDetectSubtitles() async {
        latestError = nil
        lastWarning = nil
        guard let image = displayImage?.cgImage,
              let source = originalBGRA else {
            latestError = .make(.mediaUnreadable)
            return
        }
        guard canAutoDetect else { return }

        let width = Int(pixelSize.width.rounded())
        let height = Int(pixelSize.height.rounded())
        guard width > 0, height > 0 else {
            latestError = .make(.mediaMetadataInvalid)
            return
        }

        do {
            try stateMachine.beginDetection()
        } catch {
            latestError = normalize(error, fallback: .internalStateError)
            return
        }

        taskController.cancel()
        let token = taskController.begin()
        let targetSize = pixelSize
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                let regions = try SubtitleRegionDetector().detect(cgImage: image)
                guard !regions.isEmpty else {
                    throw SubtitleEraserError.make(
                        .detectionFailed,
                        underlying: "Vision returned no subtitle candidates in the lower image band."
                    )
                }
                let coarseMask = try MaskProcessor.rasterize(
                    regions: regions,
                    targetSize: targetSize,
                    expandPixels: 3
                )
                let refinedMask = try SubtitleMaskRefiner.refine(
                    imageBGRA: source,
                    coarseMask: coarseMask,
                    width: width,
                    height: height,
                    options: SubtitleMaskRefiner.Options(dilatePixels: 4, featherPixels: 2)
                )
                guard refinedMask.contains(where: { $0 > 0 }) else {
                    throw SubtitleEraserError.make(.detectionFailed, underlying: "refined subtitle mask is empty.")
                }
                return (regions, refinedMask)
            }.value

            guard taskController.isActive(token) else {
                Logger.info("stale subtitle detection result discarded")
                taskController.finish(token)
                return
            }
            activeAutoMask = result.1
            autoMaskPreview = result.0.map(\.rect)
            try stateMachine.detectionSucceeded()
            Logger.info("subtitle auto detection succeeded")
        } catch {
            if taskController.isActive(token) {
                let warning = SubtitleEraserError.make(
                    .detectionFailed,
                    underlying: error.localizedDescription
                )
                stateMachine.detectionDegraded(warning)
                lastWarning = warning
                Logger.warning("subtitle detection degraded to manual mode")
            }
        }
        taskController.finish(token)
    }

    func executeInpaint() async {
        latestError = nil
        lastWarning = nil
        lastSaveSucceeded = false
        guard let source = originalBGRA,
              !undoManager.strokes.isEmpty || activeAutoMask != nil else {
            latestError = .make(.inpaintFailed, underlying: "missing image, automatic mask, or strokes")
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
        } catch {
            fail(with: error, fallback: .internalStateError)
            return
        }

        let token = taskController.begin()
        let strokeSnapshot = undoManager.strokes
        let baseMaskSnapshot = activeAutoMask
        let targetSize = pixelSize
        do {
            let output = try await Task.detached(priority: .userInitiated) {
                let mask: RasterizedMask
                if FeatureFlags.featherEnabled {
                    mask = try MaskProcessor.rasterizeMask(
                        strokes: strokeSnapshot,
                        targetSize: targetSize,
                        featherPixels: 2,
                        baseMask: baseMaskSnapshot
                    )
                } else {
                    let binary = try MaskProcessor.rasterize(
                        strokes: strokeSnapshot,
                        targetSize: targetSize,
                        baseMask: baseMaskSnapshot
                    )
                    mask = RasterizedMask(
                        width: width,
                        height: height,
                        binary: binary,
                        softWeights: [UInt8](binary)
                    )
                }
                return try InpaintEngine.inpaint(
                    imageBGRA: source,
                    mask: mask,
                    width: width,
                    height: height
                )
            }.value

            guard taskController.isActive(token) else {
                Logger.info("stale inpaint result discarded")
                return
            }
            let image = try ImageExportService.uiImage(fromBGRA: output, width: width, height: height)
            previewImage = image
            showComparison = true
            try stateMachine.processingSucceeded()
            Logger.info("inpaint succeeded")
        } catch {
            if taskController.isActive(token) {
                fail(with: error, fallback: .inpaintFailed)
            }
        }
        taskController.finish(token)
    }

    func saveResult() async {
        latestError = nil
        lastSaveSucceeded = false
        guard let image = previewImage else {
            latestError = .make(.exportFailed, underlying: "preview image unavailable")
            return
        }
        do {
            if stateMachine.state == .completed {
                try stateMachine.retryExport()
            } else {
                try stateMachine.beginExporting()
            }
            guard await photoSaver.requestPermission() else {
                throw SubtitleEraserError.make(.photoPermissionDenied, retryable: true)
            }
            guard StorageSpaceService.hasEnoughSpace() else {
                throw SubtitleEraserError.make(.insufficientStorage, retryable: true)
            }
            try await photoSaver.save(image: image)
            try stateMachine.exportSucceeded()
            lastSaveSucceeded = true
            Logger.info("photo library save succeeded")
        } catch {
            let failure = normalize(error, fallback: .exportFailed)
            latestError = failure
            stateMachine.exportFailed(failure)
            stateMachine.returnToPreviewing()
            Logger.error("photo library save failed: \(failure.code.rawValue)")
        }
    }

    func backToEditing() {
        latestError = nil
        previewImage = nil
        showComparison = false
        do {
            try stateMachine.backToEditing()
        } catch {
            latestError = .make(.internalStateError, underlying: error.localizedDescription)
        }
    }

    func resumeEditing() {
        backToEditing()
    }

    func resetToOriginal() {
        latestError = nil
        previewImage = nil
        showComparison = false
        comparisonSlider = 0.5
        undoManager.reset()
        activeAutoMask = nil
        autoMaskPreview = []
        if stateMachine.state == .previewing || stateMachine.state == .completed {
            try? stateMachine.backToEditing()
        } else {
            stateMachine.returnToEditing()
        }
    }

    func cancelCurrent() {
        taskController.cancel()
        lastWarning = .make(.userCancelled)
        gestureCoordinator.reset()
        guard stateMachine.state.isBusy else { return }
        switch stateMachine.state {
        case .processing, .exporting:
            try? stateMachine.backToEditing()
        case .detecting:
            stateMachine.returnToEditing()
        default:
            stateMachine.cancel()
        }
        Logger.info("current task cancelled")
    }

    func confirmExit() {
        taskController.cancel()
        stateMachine.cancel()
        showExitConfirm = false
    }

    private func handleMemoryWarning() {
        undoManager.releaseCaches()
        guard stateMachine.state.isBusy else { return }
        taskController.cancel()
        let warning = SubtitleEraserError.make(.memoryWarningPaused)
        stateMachine.cancel(reason: warning)
        lastWarning = warning
        Logger.warning("memory warning; active task invalidated")
    }

    private func fail(with error: Error, fallback: SubtitleEraserErrorCode) {
        let failure = normalize(error, fallback: fallback)
        latestError = failure
        if stateMachine.state.isBusy {
            switch stateMachine.state {
            case .exporting: stateMachine.exportFailed(failure)
            case .processing: stateMachine.processingFailed(failure)
            default: stateMachine.importFailed(failure)
            }
        } else {
            stateMachine.importFailed(failure)
        }
        Logger.error("operation failed: \(failure.code.rawValue)")
    }

    private func normalize(_ error: Error, fallback: SubtitleEraserErrorCode) -> SubtitleEraserError {
        (error as? SubtitleEraserError)
            ?? .make(fallback, underlying: error.localizedDescription)
    }
}
