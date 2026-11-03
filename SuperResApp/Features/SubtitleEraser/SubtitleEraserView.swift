import PhotosUI
import SwiftUI

struct SubtitleEraserView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @StateObject private var viewModel: SubtitleEraserViewModel
    @ObservedObject private var undoManager: MaskUndoManager
    @State private var pickerItem: PhotosPickerItem?
    @State private var isImporting = false
    @State private var showDebugPanel = false
    @State private var versionTapCount = 0

    private var isLandscape: Bool { verticalSizeClass == .compact }

    init() {
        let model = SubtitleEraserViewModel()
        _viewModel = StateObject(wrappedValue: model)
        _undoManager = ObservedObject(wrappedValue: model.undoManager)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("字幕消除")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .interactiveDismissDisabled(!viewModel.canDismiss)
                .alert("正在处理中", isPresented: $viewModel.showExitConfirm) {
                    Button("继续处理", role: .cancel) {}
                    Button("取消并返回", role: .destructive) {
                        viewModel.confirmExit()
                        dismiss()
                    }
                } message: {
                    Text("当前任务会被取消，临时数据将清理。")
                }
                .sheet(isPresented: $showDebugPanel) {
                    #if DEBUG
                    DebugPanelContainer(viewModel: viewModel)
                    #endif
                }
        }
        .overlay(alignment: .top) {
            if let error = viewModel.latestError {
                errorBanner(error).padding(.top, 8)
            } else if let warning = viewModel.lastWarning {
                warningBanner(warning).padding(.top, 8)
            }
        }
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            isImporting = true
            Task {
                defer {
                    isImporting = false
                    pickerItem = nil
                }
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await viewModel.importImage(data: data)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            #if DEBUG
            if FeatureFlags.debugPanelEnabled {
                DebugOverlayView(state: viewModel.stateMachine.state, strokeCount: viewModel.strokes.count)
            }
            #endif
        }
    }

    @ViewBuilder
    private var content: some View {
        if let image = viewModel.displayImage {
            editorLayout(original: image)
        } else {
            emptyView
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("选择一张图片开始").font(.headline)
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("从相册选择", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            if isImporting {
                ProgressView("正在加载…")
            }
            Text("v0.1.0")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 24)
                .onTapGesture {
                    #if DEBUG
                    versionTapCount += 1
                    if versionTapCount >= 5 {
                        versionTapCount = 0
                        DebugSettingsStore.shared.panelEnabled.toggle()
                        showDebugPanel = true
                    }
                    #endif
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private func editorLayout(original: UIImage) -> some View {
        if isLandscape {
            HStack(spacing: 12) {
                canvasArea(original: original)
                ScrollView { controls }
                    .frame(maxWidth: 320)
            }
            .padding()
        } else {
            VStack(spacing: 12) {
                canvasArea(original: original)
                controls
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    private func canvasArea(original: UIImage) -> some View {
        ZStack {
            Color.black.opacity(0.92)
            if let preview = viewModel.previewImage, viewModel.showComparison {
                comparisonView(original: original, preview: preview)
            } else {
                Image(uiImage: original).resizable().scaledToFit()
                if let maskPreview = viewModel.autoMaskPreviewImage {
                    Image(uiImage: maskPreview)
                        .resizable()
                        .scaledToFit()
                        .allowsHitTesting(false)
                }
                MaskDrawCanvas(
                    committedStrokes: undoManager.strokes,
                    tool: viewModel.tool,
                    brushWidth: viewModel.brushWidth,
                    isEnabled: viewModel.stateMachine.state == .editing,
                    onStrokeCommitted: undoManager.appendStroke,
                    onDrawingChanged: { drawing in
                        if drawing {
                            viewModel.gestureCoordinator.beginDrawing()
                        } else {
                            viewModel.gestureCoordinator.endDrawing()
                        }
                    }
                )
            }
            if viewModel.isProcessing {
                progressOverlay
            }
        }
        .aspectRatio(viewModel.pixelSize.width / max(viewModel.pixelSize.height, 1), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func comparisonView(original: UIImage, preview: UIImage) -> some View {
        GeometryReader { geometry in
            let split = geometry.size.width * viewModel.comparisonSlider
            ZStack(alignment: .leading) {
                Image(uiImage: original).resizable().scaledToFit()
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: split)
                    }
                Rectangle().fill(.white).frame(width: 2).offset(x: split)
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0).onChanged { value in
                            viewModel.comparisonSlider = min(
                                max(value.location.x / geometry.size.width, 0.05),
                                0.95
                            )
                        }
                    )
            }
            .accessibilityElement()
            .accessibilityLabel("原图与修复图对比")
            .accessibilityValue("\(Int(viewModel.comparisonSlider * 100))%")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    viewModel.comparisonSlider = min(0.95, viewModel.comparisonSlider + 0.05)
                case .decrement:
                    viewModel.comparisonSlider = max(0.05, viewModel.comparisonSlider - 0.05)
                @unknown default: break
                }
            }
        }
    }

    private var progressOverlay: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text(progressLabel).font(.footnote).foregroundStyle(.white)
            Button("取消", role: .destructive) { viewModel.cancelCurrent() }
                .buttonStyle(.bordered)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var progressLabel: String {
        switch viewModel.stateMachine.state {
        case .processing: return "正在修复…"
        case .exporting: return "正在保存…"
        case .importing: return "正在导入…"
        case .detecting: return "正在识别字幕…"
        default: return "处理中…"
        }
    }

    @ViewBuilder
    private var controls: some View {
        if viewModel.showComparison {
            comparisonControls
        } else {
            drawingControls
        }
    }

    // swiftlint:disable:next function_body_length
    private var drawingControls: some View {
        VStack(spacing: 12) {
            Button {
                Task { await viewModel.autoDetectSubtitles() }
            } label: {
                if case .detecting = viewModel.stateMachine.state {
                    ProgressView("正在智能抓取…")
                } else {
                    Label("智能抓取", systemImage: "text.viewfinder")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canAutoDetect)

            Picker("工具", selection: $viewModel.tool) {
                Text("画笔").tag(MaskBrushTool.brush)
                Text("橡皮擦").tag(MaskBrushTool.eraser)
            }
            .pickerStyle(.segmented)
            HStack {
                Text("粗细")
                Slider(value: $viewModel.brushWidth, in: 10...50, step: 1)
                    .accessibilityLabel("画笔粗细")
                Text("\(Int(viewModel.brushWidth)) pt")
                    .monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
            }
            if undoManager.strokes.isEmpty && viewModel.activeAutoMask == nil {
                Text("请涂抹字幕区域，或点击“智能抓取”自动识别")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(viewModel.activeAutoMask == nil ? "手动画框已就绪" : "自动选区已生成，可继续手动补充或擦除")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                Button("撤销") { undoManager.undo() }
                    .disabled(!undoManager.canUndo || viewModel.isProcessing)
                Button("重做") { undoManager.redo() }
                    .disabled(!undoManager.canRedo || viewModel.isProcessing)
                Button("重置", role: .destructive) { viewModel.resetMaskSelection() }
                    .disabled(
                        undoManager.strokes.isEmpty && viewModel.activeAutoMask == nil
                            || viewModel.isProcessing
                    )
                Spacer(minLength: 4)
                Button {
                    Task { await viewModel.executeInpaint() }
                } label: {
                    Label("执行消除", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canExecute)
            }
            .buttonStyle(.bordered)
        }
    }

    private var comparisonControls: some View {
        HStack(spacing: 10) {
            Button("重新编辑") { viewModel.backToEditing() }
                .buttonStyle(.bordered)
            Button("重置原图", role: .destructive) { viewModel.resetToOriginal() }
                .buttonStyle(.bordered)
            Spacer(minLength: 4)
            Button {
                Task { await viewModel.saveResult() }
            } label: {
                Label("保存到相册", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canSave || viewModel.isProcessing)
        }
        .buttonStyle(.bordered)
    }

    private func errorBanner(_ error: SubtitleEraserError) -> some View {
        HStack(spacing: 8) {
            Image(systemName: error.isBlocking ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(error.isBlocking ? .red : .orange)
            Text(error.errorDescription ?? error.userMessage)
                .font(.footnote)
                .lineLimit(2)
            Spacer(minLength: 8)
            if error.isRetryable {
                Button("重试") {
                    Task {
                        if viewModel.previewImage == nil {
                            await viewModel.executeInpaint()
                        } else {
                            await viewModel.saveResult()
                        }
                    }
                }
                .font(.footnote.bold())
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }

    private func warningBanner(_ warning: SubtitleEraserError) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(.orange)
            Text(warning.userMessage).font(.footnote).lineLimit(2)
            Spacer()
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button("返回") {
                if viewModel.canDismiss {
                    dismiss()
                } else {
                    viewModel.showExitConfirm = true
                }
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack {
                #if DEBUG
                if FeatureFlags.debugPanelEnabled {
                    Button {
                        showDebugPanel = true
                    } label: {
                        Image(systemName: "ladybug")
                    }
                }
                #endif
                if viewModel.displayImage != nil {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Image(systemName: "photo.badge.plus")
                    }
                    .disabled(viewModel.isProcessing)
                }
            }
        }
    }
}

#Preview {
    SubtitleEraserView()
}
