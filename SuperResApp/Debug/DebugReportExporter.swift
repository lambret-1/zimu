#if DEBUG
import Foundation

enum DebugReportExporter {
    static func makeReport(state: SubtitleEraserState, strokes: Int) -> String {
        let description = SubtitleEraserStateMachine.describe(state)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        {
          "state": "\(description)",
          "strokes": \(strokes),
          "memoryWarnings": \(MemoryMonitor.shared.warningCount)
        }
        """
    }
}
#endif
