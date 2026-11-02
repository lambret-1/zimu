import PhotosUI
import SwiftUI

struct SubtitleEraserView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SubtitleEraserViewModel
    @ObservedObject private var undoManager: MaskUndoManager
    @State private var pickerItem: PhotosPickerItem?
    @State private var isImporting = false
    @State private var showExitAlert = false

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
        }
        .overlay(alignment: .top) {
            if let error = viewModel.latestError {
                errorBanner(error)
                    .padding(.top, 8)
            }
        }
        .alert("任务正在处理", isPresented: $showExitAlert) {
            Button("继续等待", role: .cancel) {}
        } message: {
            Text("当前任务尚未结束，请完成后再返回。")
        }
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            isImporting = true
            Task {
                defer { isImporting = false }
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    await viewModel.importImage(data: Data())
                    return
                }
                await viewModel.importImage(data: data)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let image = viewModel.displayImage {
            editorView(original: image)
        } else {
            emptyView
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("选择一张图片开始")
                .font(.headline)
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("从相册选择", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            if isImporting {
                ProgressView("正在加载…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func editorView(original: UIImage) -> some View {
        VStack(spacing: 12) {
            canvasArea(original: original)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            controls
        }
        .padding(.horizontal)
        .padding(.bottom)
    }

    private func canvasArea(original: UIImage) -> some View {
        ZStack {
            Color.black.opacity(0.92)
            if let preview = viewModel.previewImage, viewModel.showComparison {
                comparisonView(original: original, preview: preview)
            } else {
                Image(uiImage: original)
                    .resizable()
                    .scaledToFit()
                MaskDrawCanvas(
                    committedStrokes: undoManager.strokes,
                    tool: viewModel.tool,
                    brushWidth: viewModel.brushWidth,
                    isEnabled: viewModel.stateMachine.state == .editing,
                    onStrokeCommitted: undoManager.appendStroke,
                    onDrawingChanged: { isDrawing in
                        if isDrawing {
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
        .aspectRatio(
            viewModel.pixelSize.width / max(viewModel.pixelSize.height, 1),
            contentMode: .fit
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func comparisonView(original: UIImage, preview: UIImage) -> some View {
        GeometryReader { geometry in
            let split = geometry.size.width * viewModel.comparisonSlider
            ZStack(alignment: .leading) {
                Image(uiImage: original)
                    .resizable()
                    .scaledToFit()
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .mask(alignment: .leading) {
                        Rectangle()
                            .frame(width: split)
                    }
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2)
                    .offset(x: split)
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                viewModel.comparisonSlider = min(
                                    max(value.location.x / geometry.size.width, 0.02),
                                    0.98
                                )
                            }
                    )
            }
        }
    }

    private var progressOverlay: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("正在修复…")
                .font(.footnote)
                .foregroundStyle(.white)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var controls: some View {
        if viewModel.showComparison {
            comparisonControls
        } else {
            drawingControls
        }
    }

    private var drawingControls: some View {
        VStack(spacing: 12) {
            Picker("工具", selection: $viewModel.tool) {
                Text("画笔").tag(MaskBrushTool.brush)
                Text("橡皮擦").tag(MaskBrushTool.eraser)
            }
            .pickerStyle(.segmented)

            HStack {
                Text("粗细")
                Slider(value: $viewModel.brushWidth, in: 10...50, step: 1)
                Text("\(Int(viewModel.brushWidth)) pt")
                    .monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
            }

            HStack(spacing: 12) {
                Button("撤销") { undoManager.undo() }
                    .disabled(!undoManager.canUndo || viewModel.isProcessing)
                Button("重做") { undoManager.redo() }
                    .disabled(!undoManager.canRedo || viewModel.isProcessing)
                Button("重置", role: .destructive) { undoManager.reset() }
                    .disabled(undoManager.strokes.isEmpty || viewModel.isProcessing)
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
            Button("重新编辑") { viewModel.resumeEditing() }
                .buttonStyle(.bordered)
            Button("重置原图", role: .destructive) { viewModel.resetToOriginal() }
                .buttonStyle(.bordered)
            Spacer(minLength: 4)
            Button {
                Task { await viewModel.saveResult() }
            } label: {
                Label("保存相册", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canSave || viewModel.isProcessing)
        }
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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("返回") {
                if viewModel.canDismiss {
                    dismiss()
                } else {
                    showExitAlert = true
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if viewModel.displayImage != nil {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Image(systemName: "photo.badge.plus")
                }
                .disabled(viewModel.isProcessing)
            }
        }
    }
}

#Preview {
    SubtitleEraserView()
}
