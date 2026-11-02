import SwiftUI

struct RootView: View {
    @State private var isShowingEraser = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text("AI 字幕消除")
                    .font(.largeTitle.bold())
                Button("开始使用") {
                    isShowingEraser = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
            .navigationTitle("首页")
        }
        .fullScreenCover(isPresented: $isShowingEraser) {
            SubtitleEraserView()
        }
    }
}

#Preview {
    RootView()
}
