#if DEBUG
import SwiftUI

struct DebugLogView: View {
    var body: some View {
        List {
            Section("内存警告") {
                Text("累计：\(MemoryMonitor.shared.warningCount)")
            }
        }
        .navigationTitle("调试日志")
    }
}
#endif
