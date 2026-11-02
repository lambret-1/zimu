#if DEBUG
import SwiftUI

struct DebugOverlayView: View {
    let state: SubtitleEraserState
    let strokeCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(SubtitleEraserStateMachine.describe(state))
            Text("strokes: \(strokeCount)")
            Text("warnings: \(MemoryMonitor.shared.warningCount)")
        }
        .font(.caption2.monospaced())
        .foregroundStyle(.white)
        .padding(6)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        .padding(8)
    }
}
#endif
