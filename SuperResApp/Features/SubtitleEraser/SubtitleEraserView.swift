import SwiftUI

struct SubtitleEraserView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("字幕消除编辑页（骨架）")
                    .font(.headline)
                Text("第二阶段在此接入导入、检测、涂抹、执行与导出。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("字幕消除")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("返回") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(false)
    }
}

#Preview {
    SubtitleEraserView()
}
