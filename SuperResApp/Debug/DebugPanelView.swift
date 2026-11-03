#if DEBUG
import SwiftUI

struct DebugPanelContainer: View {
    let viewModel: SubtitleEraserViewModel

    var body: some View {
        DebugPanelView(viewModel: viewModel)
    }
}

struct DebugPanelView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: SubtitleEraserViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("状态") {
                    Text(SubtitleEraserStateMachine.describe(viewModel.stateMachine.state))
                        .font(.body.monospaced())
                    Text("笔画数：\(viewModel.strokes.count)")
                    Text("内存警告次数：\(MemoryMonitor.shared.warningCount)")
                }
                Section("画质调优") {
                    Toggle("启用智能 Mask 细化（Refiner）", isOn: Binding(
                        get: { DebugSettingsStore.shared.useMaskRefiner },
                        set: { DebugSettingsStore.shared.useMaskRefiner = $0 }
                    ))
                }
                Section("故障注入") {
                    Button("模拟内存警告") {
                        MemoryMonitor.shared.simulateWarning()
                    }
                    Button("模拟用户取消") {
                        viewModel.cancelCurrent()
                    }
                }
                Section("报告") {
                    ShareLink(item: DebugReportExporter.makeReport(
                        state: viewModel.stateMachine.state,
                        strokes: viewModel.strokes.count
                    )) {
                        Text("导出调试报告")
                    }
                }
            }
            .navigationTitle("调试面板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
#endif
