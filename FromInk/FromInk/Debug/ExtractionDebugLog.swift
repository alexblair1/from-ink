#if DEBUG
import Foundation

@MainActor
@Observable
final class ExtractionDebugLog {
    static let shared = ExtractionDebugLog()
    private init() {}

    // MARK: - Models

    struct Run: Identifiable {
        let id = UUID()
        let startedAt = Date()
        let scope: String  // "Lasso" or "Page"
        var entries: [Entry] = []
    }

    struct Entry: Identifiable {
        let id = UUID()
        let phase: Phase
        let label: String
        let content: String
        var isWarning = false
        var isError = false

        enum Phase: String, CaseIterable {
            case ocr      = "Vision OCR"
            case nlStage1 = "Stage 1 · NL Analysis"
            case fmStage2 = "Stage 2 · Foundation Models"
            case result   = "Result"
        }
    }

    // MARK: - State

    private(set) var runs: [Run] = []
    private var currentRun: Run?

    // MARK: - API

    func startRun(scope: String) {
        currentRun = Run(scope: scope)
    }

    func log(
        phase: Entry.Phase,
        label: String,
        content: String,
        isWarning: Bool = false,
        isError: Bool = false
    ) {
        currentRun?.entries.append(
            Entry(phase: phase, label: label, content: content,
                  isWarning: isWarning, isError: isError)
        )
    }

    func commitRun() {
        if let run = currentRun, !run.entries.isEmpty {
            runs.insert(run, at: 0)
            if runs.count > 20 { runs.removeLast() }
        }
        currentRun = nil
    }

    func clear() { runs.removeAll() }
}
#endif
