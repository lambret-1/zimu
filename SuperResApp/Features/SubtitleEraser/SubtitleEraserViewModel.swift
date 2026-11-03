import Combine
import Foundation
import UIKit

@MainActor
final class SubtitleEraserViewModel: ObservableObject {
    @Published private(set) var displayImage: UIImage?
    @Published private(set) var previewImage: UIImage?
    @Published private(set) var activeAutoMask: Data?
    @Published private(set) var autoMaskPreviewImage: UIImage?
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
    private var cancellables = Set<AnyCancellable>()

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
        stateMachine.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
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
            autoMaskPreviewImage = nil
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
                try SubtitleAutoDetectionPipeline.run(
                    image: image,
                    source: source,
                    width: width,
                    height: height,
                    targetSize: targetSize
                )
            }.value

            guard taskController.isActive(token) else {
                Logger.info("stale subtitle detection result discarded")
                taskController.finish(token)
                return
            }
            guard let previewImage = MaskPreviewRenderer.makeImage(from: result.preview) else {
                throw SubtitleEraserError.make(.detectionFailed, underlying: "mask preview image unavailable.")
            }
            activeAutoMask = result.mask
            autoMaskPreviewImage = previewImage
            try stateMachine.detectionSucceeded()
            Logger.info("subtitle auto detection succeeded")
        } catch {
            if taskController.isActive(token) {
                let warning = SubtitleEraserError.make(
                    .detectionFailed,
                    underlying: error.localizedDescription
                )
                activeAutoMask = nil
                autoMaskPreviewImage = nil
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
        guard let source = originalBGRA else {
            latestError = .make(.inpaintFailed, underlying: "missing image")
            return
        }
        let width = Int(pixelSize.width.rounded())
        let height = Int(pixelSize.height.rounded())
        guard width > 0, height > 0 else {
            latestError = .make(.mediaMetadataInvalid)
            return
        }
        guard !undoManager.strokes.isEmpty || activeAutoMask != nil else {
            latestError = .make(.inpaintFailed, underlying: "no mask available")
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
        #if DEBUG
        let useRefiner = DebugSettingsStore.shared.useMaskRefiner
        #else
        let useRefiner = true
        #endif

        do {
            let output = try await Task.detached(priority: .userInitiated) {
                let finalMask = try SubtitleMaskExecutionPipeline.makeFinalMask(
                    imageBGRA: source,
                    strokes: strokeSnapshot,
                    baseMask: baseMaskSnapshot,
                    targetSize: targetSize,
                    width: width,
                    height: height,
                    useRefiner: useRefiner
                )
                let mask = RasterizedMask(
                    width: width,
                    height: height,
                    binary: finalMask,
                    softWeights: finalMask
                )
                return try InpaintEngine.inpaint(
                    imageBGRA: source,
                    mask: mask,
                    width: width,
                    height: height
                )
            }.value

            guard taskController.isActive(token) else {
                Logger.info("stale inpaint result discarded")
                taskController.finish(token)
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
        activeAutoMask = nil
        autoMaskPreviewImage = nil
        do {
            try stateMachine.backToEditing()
        } catch {
            latestError = .make(.internalStateError, underlying: error.localizedDescription)
        }
    }

    func resumeEditing() {
        backToEditing()
    }

    func resetMaskSelection() {
        undoManager.reset()
        activeAutoMask = nil
        autoMaskPreviewImage = nil
    }

    func resetToOriginal() {
        latestError = nil
        previewImage = nil
        showComparison = false
        comparisonSlider = 0.5
        resetMaskSelection()
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
        if case .detecting = stateMachine.state {
            stateMachine.returnToEditing()
        } else {
            stateMachine.cancel(reason: warning)
        }
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

private enum SubtitleAutoDetectionPipeline {
    static func run(
        image: CGImage,
        source: Data,
        width: Int,
        height: Int,
        targetSize: CGSize
    ) throws -> (mask: Data, preview: MaskPreviewRenderer.Pixels) {
        let regions = try SubtitleRegionDetector().detect(cgImage: image)
        guard !regions.isEmpty else {
            throw SubtitleEraserError.make(
                .detectionFailed,
                underlying: "Vision returned no subtitle candidates in the lower image band."
            )
        }
        let coarseMask = try MaskProcessor.rasterize(
            regions: regions,
            targetSize: targetSize
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
        guard let preview = MaskPreviewRenderer.makePixels(
            mask: refinedMask,
            width: width,
            height: height
        ) else {
            throw SubtitleEraserError.make(.detectionFailed, underlying: "mask preview generation failed.")
        }
        return (refinedMask, preview)
    }
}

private enum MaskPreviewRenderer {
    struct Pixels: Sendable {
        let data: Data
        let width: Int
        let height: Int
    }

    static func makePixels(mask: Data, width: Int, height: Int) -> Pixels? {
        let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, width > 0, height > 0, mask.count == pixelCount else { return nil }

        let scale = min(1, 1280.0 / Double(max(width, height)))
        let previewWidth = max(1, Int((Double(width) * scale).rounded()))
        let previewHeight = max(1, Int((Double(height) * scale).rounded()))
        let (previewPixels, previewOverflow) = previewWidth.multipliedReportingOverflow(by: previewHeight)
        guard !previewOverflow, previewPixels <= 1280 * 1280 else { return nil }
        let (byteCount, byteOverflow) = previewPixels.multipliedReportingOverflow(by: 4)
        guard !byteOverflow else { return nil }

        var rgba = Data(count: byteCount)
        let rendered = rgba.withUnsafeMutableBytes { destination -> Bool in
            guard let output = destination.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return false
            }
            return mask.withUnsafeBytes { source in
                guard let input = source.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return false
                }
                for y in 0..<previewHeight {
                    let sourceY = min(height - 1, y * height / previewHeight)
                    for x in 0..<previewWidth {
                        let sourceX = min(width - 1, x * width / previewWidth)
                        let alpha = UInt8((Int(input[sourceY * width + sourceX]) * 115 + 127) / 255)
                        let offset = (y * previewWidth + x) * 4
                        output[offset] = alpha
                        output[offset + 1] = 0
                        output[offset + 2] = 0
                        output[offset + 3] = alpha
                    }
                }
                return true
            }
        }
        guard rendered else { return nil }
        return Pixels(data: rgba, width: previewWidth, height: previewHeight)
    }

    static func makeImage(from pixels: Pixels) -> UIImage? {
        guard let provider = CGDataProvider(data: pixels.data as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
        ).union(.byteOrder32Big)
        guard let image = CGImage(
            width: pixels.width,
            height: pixels.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: pixels.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            return nil
        }
        return UIImage(cgImage: image)
    }
}

private enum SubtitleMaskExecutionPipeline {
    static func makeFinalMask(
        imageBGRA: Data,
        strokes: [MaskStroke],
        baseMask: Data?,
        targetSize: CGSize,
        width: Int,
        height: Int,
        useRefiner: Bool
    ) throws -> Data {
        let coarseMask: Data
        if FeatureFlags.featherEnabled {
            coarseMask = try MaskProcessor.rasterizeMask(
                strokes: strokes,
                targetSize: targetSize,
                featherPixels: 2,
                baseMask: baseMask
            ).binary
        } else {
            coarseMask = try MaskProcessor.rasterize(
                strokes: strokes,
                targetSize: targetSize,
                baseMask: baseMask
            )
        }

        guard useRefiner else { return coarseMask }
        return try SubtitleMaskRefiner.refine(
            imageBGRA: imageBGRA,
            coarseMask: coarseMask,
            width: width,
            height: height,
            options: SubtitleMaskRefiner.Options(dilatePixels: 4, featherPixels: 2)
        )
    }
}
