import SwiftUI

struct SubtitleEraserView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var undoManager = MaskUndoManager()
    @StateObject private var gestureCoordinator = GestureCoordinator()
    @State private var tool: MaskBrushTool = .brush
    @State private var brushWidth: CGFloat = 20

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.black.opacity(0.92))
                    VStack {
                        Spacer()
                        Text("字幕样例")
                            .font(.title.bold())
                            .foregroundStyle(.white)
                            .padding(.bottom, 24)
                    }
                    MaskDrawCanvas(
                        committedStrokes: undoManager.strokes,
                        tool: tool,
                        brushWidth: brushWidth,
                        isEnabled: gestureCoordinator.state != .disabled,
                        onStrokeCommitted: undoManager.appendStroke,
                        onDrawingChanged: { isDrawing in
                            if isDrawing {
                                gestureCoordinator.beginDrawing()
                            } else {
                                gestureCoordinator.endDrawing()
                            }
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("字幕遮罩绘制区域")

                controls
            }
            .padding()
            .navigationTitle("字幕消除 · 2.2")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("返回") { dismiss() }
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Picker("工具", selection: $tool) {
                Text("画笔").tag(MaskBrushTool.brush)
                Text("橡皮擦").tag(MaskBrushTool.eraser)
            }
            .pickerStyle(.segmented)

            HStack {
                Text("粗细")
                Slider(value: $brushWidth, in: 10...50, step: 1)
                Text("\(Int(brushWidth)) pt")
                    .monospacedDigit()
                    .frame(width: 56, alignment: .trailing)
            }

            HStack(spacing: 16) {
                Button("撤销") { undoManager.undo() }
                    .disabled(!undoManager.canUndo)
                Button("重做") { undoManager.redo() }
                    .disabled(!undoManager.canRedo)
                Button("重置", role: .destructive) { undoManager.reset() }
                    .disabled(undoManager.strokes.isEmpty)
            }
            .buttonStyle(.bordered)
        }
    }
}

#Preview {
    SubtitleEraserView()
}
