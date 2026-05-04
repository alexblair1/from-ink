import Vision
import UIKit
import PencilKit
import NaturalLanguage
import FoundationModels

// MARK: - Scope & Result

enum TaskExtractionScope {
    /// Lasso selection — expects exactly one task.
    case single
    /// Full page bolt — expects all tasks, a summary, and an open question.
    case page
}

struct TaskExtractionResult {
    var tasks: [InkTask]
    var summary: String
    var openQuestion: String?

    static let empty = TaskExtractionResult(tasks: [], summary: "", openQuestion: nil)
}

// MARK: - Foundation Models structured output
    
@Generable
private struct FMSingleTask {
    @Guide(description: "Short, actionable task title in imperative form. Only the cleaned title — nothing else.")
    var title: String

    @Guide(description: "Display subtitle: deadline, project, or category phrase. Empty string if none.")
    var detail: String

    @Guide(description: "Additional context or notes from the text. Empty string if none.")
    var body: String

    @Guide(description: "Priority level: urgent, high, medium, low, or empty string if unclear.")
    var priorityString: String
}

@Generable
private struct FMSummary {
    @Guide(description: "1–2 sentence summary of what the notes are about. Concise and specific.")
    var summary: String

    @Guide(description: "An unresolved question found in the notes, if any. Empty string if there is none.")
    var openQuestion: String
}

// MARK: - Extractor

enum InkTaskExtractor {

    // MARK: - Public entry points

    /// Lasso path: extract a single task from a cropped UIImage.
    static func extract(image: UIImage, scope: TaskExtractionScope = .single) async -> TaskExtractionResult {
        debugStartRun("Lasso")
        let flat = whiteBackground(image)
        let rawText = await visionOCR(flat)
        debugLog(.ocr, "Raw OCR", rawText.isEmpty ? "(empty)" : rawText)
        guard !rawText.isEmpty else { debugCommitRun(); return .empty }

        let stage1 = extractCandidates(from: rawText)
        debugLogStage1(stage1)

        let result = await stage2(stage1: stage1, scope: scope)
        debugLogResult(result)
        debugCommitRun()
        return result
    }

    /// Page path: render a PKDrawing then run the full pipeline.
    static func extract(drawing: PKDrawing, scope: TaskExtractionScope = .page) async -> TaskExtractionResult {
        debugStartRun("Page")
        guard !drawing.strokes.isEmpty else { debugCommitRun(); return .empty }
        let image = renderDrawing(drawing)
        let rawText = await visionOCR(image)
        debugLog(.ocr, "Raw OCR", rawText.isEmpty ? "(empty)" : rawText)
        guard !rawText.isEmpty else { debugCommitRun(); return .empty }

        let stage1 = extractCandidates(from: rawText)
        debugLogStage1(stage1)

        let result = await stage2(stage1: stage1, scope: scope)
        debugLogResult(result)
        debugCommitRun()
        return result
    }

    // MARK: - Stage 1: Deterministic extraction

    private static func extractCandidates(from text: String) -> CandidateExtraction {
        let allDates = detectDates(in: text)
        let (allPersons, _, _) = extractEntities(from: text)

        // Split into sentences
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let s = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { sentences.append(s) }
            return true
        }

        var candidates: [CandidateExtraction.TaskCandidate] = []
        for sentence in sentences {
            guard isTaskCandidate(sentence) else { continue }
            let (persons, orgs, places) = extractEntities(from: sentence)
            candidates.append(CandidateExtraction.TaskCandidate(
                sentence: sentence,
                detectedDates: detectDates(in: sentence),
                detectedPersons: persons,
                detectedOrganizations: orgs,
                detectedPlaces: places
            ))
        }

        return CandidateExtraction(
            candidates: candidates,
            allDates: allDates,
            allPersons: Array(Set(allPersons)),
            rawText: text
        )
    }

    /// Returns true if the sentence looks like an imperative task.
    private static func isTaskCandidate(_ sentence: String) -> Bool {
        let lower = sentence.lowercased()

        // Explicit task markers take priority
        let taskMarkers = ["todo:", "to do:", "action:", "[ ]", "☐", "→ ", "- [ ]"]
        if taskMarkers.contains(where: { lower.hasPrefix($0) || lower.contains($0) }) {
            return true
        }

        // Heuristic: sentence starts with a verb (imperative form)
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = sentence
        var firstTag: NLTag?
        tagger.enumerateTags(
            in: sentence.startIndex..<sentence.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: [.omitPunctuation, .omitWhitespace]
        ) { tag, _ in
            firstTag = tag
            return false
        }
        return firstTag == .verb
    }

    /// NLTagger-based named entity extraction.
    private static func extractEntities(from text: String) -> (persons: [String], orgs: [String], places: [String]) {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var persons: [String] = []
        var orgs: [String] = []
        var places: [String] = []
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitPunctuation, .omitWhitespace, .joinNames]
        ) { tag, range in
            let entity = String(text[range])
            switch tag {
            case .personalName:    persons.append(entity)
            case .organizationName: orgs.append(entity)
            case .placeName:        places.append(entity)
            default: break
            }
            return true
        }
        return (persons, orgs, places)
    }

    /// NSDataDetector-based date extraction — far more reliable than asking FM for dates.
    private static func detectDates(in text: String) -> [Date] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return [] }
        let matches = detector.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        return matches.compactMap { $0.date }
    }

    // MARK: - Stage 2: Foundation Models enrichment

    private static func stage2(
        stage1: CandidateExtraction,
        scope: TaskExtractionScope
    ) async -> TaskExtractionResult {
        switch scope {
        case .single: return await stage2Single(stage1: stage1)
        case .page:   return await stage2Page(stage1: stage1)
        }
    }

    private static func stage2Single(stage1: CandidateExtraction) async -> TaskExtractionResult {
        let prompt = buildSinglePrompt(stage1: stage1)
        let fallback = TaskExtractionResult(
            tasks: [InkTask(title: stage1.rawText.trimmingCharacters(in: .whitespacesAndNewlines))],
            summary: "",
            openQuestion: nil
        )

        return await withTaskGroup(of: TaskExtractionResult?.self) { group in
            group.addTask {
                do {
                    let session = LanguageModelSession()
                    let response = try await session.respond(to: prompt, generating: FMSingleTask.self)
                    let fm = response.content
                    guard !fm.title.isEmpty else { return nil }

                    let dueDate = stage1.allDates.first
                        ?? detectDates(in: fm.title + " " + fm.detail).first

                    let detail = fm.detail.isEmpty
                        ? detailFromDate(dueDate)
                        : fm.detail

                    let task = InkTask(
                        title: fm.title,
                        body: fm.body,
                        detail: detail,
                        dueDate: dueDate,
                        priority: TaskPriority.from(fm.priorityString)
                    )
                    return TaskExtractionResult(tasks: [task], summary: "", openQuestion: nil)
                } catch let error as LanguageModelSession.GenerationError
                    where "\(error)".contains("guardrail") {
                    print("[InkTaskExtractor] single guardrail — falling back to Stage 1")
                    return stage1ResultSingle(stage1: stage1)
                } catch {
                    print("[InkTaskExtractor] single FM error: \(error)")
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(8))
                print("[InkTaskExtractor] single FM timeout")
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result ?? fallback
        }
    }

    private static func stage2Page(stage1: CandidateExtraction) async -> TaskExtractionResult {
        // If Stage 1 found no candidates the note-writing style doesn't match the
        // imperative-verb heuristic. Fall back to the same single-FM-call path the
        // lasso uses so we always produce output.
        if stage1.candidates.isEmpty {
            debugLog(.nlStage1, "No candidates — falling back to full-text FM", stage1.rawText)
            return await stage2Single(stage1: stage1)
        }

        // Each candidate is processed independently so a guardrail on one sentence
        // doesn't block the others. Clean tasks get FM polish; flagged ones show a warning.
        async let indexedTasks: [(Int, InkTask)] = withTaskGroup(of: (Int, InkTask).self) { group in
            for (i, candidate) in stage1.candidates.enumerated() {
                group.addTask {
                    let task = await extractCandidate(candidate, pageAllDates: stage1.allDates)
                    return (i, task)
                }
            }
            var results: [(Int, InkTask)] = []
            for await result in group { results.append(result) }
            return results
        }

        // Summary uses only candidate sentences — no raw OCR — to minimise guardrail surface.
        async let summaryResult: (String, String?) = extractPageSummary(stage1: stage1)

        let tasks = await indexedTasks
            .sorted { $0.0 < $1.0 }
            .map(\.1)
        let (summary, openQuestion) = await summaryResult

        return TaskExtractionResult(tasks: tasks, summary: summary, openQuestion: openQuestion)
    }

    /// Processes a single Stage 1 candidate through FM.
    /// On guardrail violation returns a warning task so the user knows which sentence was flagged.
    private static func extractCandidate(
        _ candidate: CandidateExtraction.TaskCandidate,
        pageAllDates: [Date]
    ) async -> InkTask {
        let dueDate = candidate.detectedDates.first ?? pageAllDates.first

        return await withTaskGroup(of: InkTask?.self) { group in
            group.addTask {
                do {
                    var parts = ["Extract one actionable task from this text. Fix any OCR errors."]
                    if !candidate.detectedDates.isEmpty {
                        parts.append("Dates: \(candidate.detectedDates.map { $0.formatted(date: .abbreviated, time: .omitted) }.joined(separator: ", "))")
                    }
                    if !candidate.detectedPersons.isEmpty {
                        parts.append("People: \(candidate.detectedPersons.joined(separator: ", "))")
                    }
                    parts.append("\nText: \(candidate.sentence)")

                    let prompt = parts.joined(separator: "\n")
                    debugLog(.fmStage2, "Prompt · \(candidate.sentence.prefix(30))…", prompt)
                    let session = LanguageModelSession()
                    let response = try await session.respond(to: prompt, generating: FMSingleTask.self)
                    let fm = response.content
                    debugLog(.fmStage2, "Response · \(candidate.sentence.prefix(30))…",
                             "title: \(fm.title)\ndetail: \(fm.detail)\nbody: \(fm.body)\npriority: \(fm.priorityString)")
                    guard !fm.title.isEmpty else { return nil }
                    let resolvedDate = dueDate ?? detectDates(in: fm.detail).first
                    return InkTask(
                        title: fm.title,
                        body: fm.body,
                        detail: fm.detail.isEmpty ? detailFromDate(resolvedDate) : fm.detail,
                        dueDate: resolvedDate,
                        priority: TaskPriority.from(fm.priorityString),
                    )
                } catch let error as LanguageModelSession.GenerationError
                    where "\(error)".contains("guardrail") {
                    print("[InkTaskExtractor] candidate guardrail: \"\(candidate.sentence.prefix(40))\"")
                    debugLog(.fmStage2, "⚠ Guardrail · \(candidate.sentence.prefix(30))…",
                             candidate.sentence, isWarning: true)
                    return InkTask(
                        title: candidate.sentence,
                        detail: guardrailDetail(dueDate: dueDate),
                        dueDate: dueDate,
                    )
                } catch {
                    print("[InkTaskExtractor] candidate FM error: \(error)")
                    debugLog(.fmStage2, "✕ Error · \(candidate.sentence.prefix(30))…",
                             "\(error)", isError: true)
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(8))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            // FM failed or timed out but no guardrail — use raw Stage 1 sentence
            return result ?? InkTask(
                title: candidate.sentence,
                detail: detailFromDate(dueDate),
                dueDate: dueDate
            )
        }
    }

    /// Extracts a page summary from candidate sentences only (avoids sending raw OCR to FM).
    private static func extractPageSummary(
        stage1: CandidateExtraction
    ) async -> (summary: String, openQuestion: String?) {
        guard !stage1.candidates.isEmpty else { return ("", nil) }
        let text = stage1.candidates.map(\.sentence).joined(separator: "\n")

        return await withTaskGroup(of: (String, String?)?.self) { group in
            group.addTask {
                let prompt = "Summarize these notes in 1–2 sentences and identify any open question:\n\(text)"
                debugLog(.fmStage2, "Summary Prompt", prompt)
                do {
                    let session = LanguageModelSession()
                    let response = try await session.respond(to: prompt, generating: FMSummary.self)
                    let fm = response.content
                    debugLog(.fmStage2, "Summary Response",
                             "summary: \(fm.summary)\nopen question: \(fm.openQuestion)")
                    return (fm.summary, fm.openQuestion.isEmpty ? nil : fm.openQuestion)
                } catch {
                    print("[InkTaskExtractor] summary FM error: \(error)")
                    debugLog(.fmStage2, "✕ Summary Error", "\(error)", isError: true)
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(10))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result ?? ("", nil)
        }
    }

    // MARK: - Stage 1 fallback results (used when FM guardrails fire)

    private static func stage1ResultSingle(stage1: CandidateExtraction) -> TaskExtractionResult {
        let sentence = stage1.candidates.first?.sentence
            ?? stage1.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let dueDate = stage1.candidates.first?.detectedDates.first ?? stage1.allDates.first
        let task = InkTask(
            title: sentence,
            body: stage1.rawText,
            detail: guardrailDetail(dueDate: dueDate),
            dueDate: dueDate
        )
        return TaskExtractionResult(tasks: [task], summary: "", openQuestion: nil)
    }

    private static func guardrailDetail(dueDate: Date?) -> String {
        let flag = "⚠ AI review skipped"
        guard let date = dueDate else { return flag }
        return "\(flag) · Due \(date.formatted(date: .abbreviated, time: .omitted))"
    }

    // MARK: - Prompt builders

    private static func buildSinglePrompt(stage1: CandidateExtraction) -> String {
        var parts: [String] = [
            "Fix OCR errors and extract one actionable task from this handwritten selection."
        ]
        if !stage1.allDates.isEmpty {
            let formatted = stage1.allDates.map { $0.formatted(date: .abbreviated, time: .omitted) }.joined(separator: ", ")
            parts.append("Dates detected: \(formatted)")
        }
        if !stage1.allPersons.isEmpty {
            parts.append("People mentioned: \(stage1.allPersons.joined(separator: ", "))")
        }
        parts.append("\nText:\n\(stage1.rawText)")
        return parts.joined(separator: "\n")
    }

    // MARK: - Vision OCR

    private static func visionOCR(_ image: UIImage) async -> String {
        await withCheckedContinuation { continuation in
            guard let cgImage = image.cgImage else {
                continuation.resume(returning: "")
                return
            }
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    print("[InkTaskExtractor] OCR error: \(error)")
                    continuation.resume(returning: "")
                    return
                }
                let text = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n") ?? ""
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]
            do {
                try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            } catch {
                print("[InkTaskExtractor] OCR perform error: \(error)")
                continuation.resume(returning: "")
            }
        }
    }

    // MARK: - Image helpers

    private static func renderDrawing(_ drawing: PKDrawing) -> UIImage {
        let bounds = drawing.bounds.isEmpty
            ? CGRect(x: 0, y: 0, width: 400, height: 400)
            : drawing.bounds.insetBy(dx: -32, dy: -32)
        let raw = drawing.image(from: bounds, scale: 3)
        let format = UIGraphicsImageRendererFormat()
        format.scale = raw.scale
        return UIGraphicsImageRenderer(size: raw.size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: raw.size))
            raw.draw(in: CGRect(origin: .zero, size: raw.size))
        }
    }

    private static func whiteBackground(_ image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: image.size))
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    // MARK: - Helpers

    /// Generates a human-readable detail string from a due date.
    private static func detailFromDate(_ date: Date?) -> String {
        guard let date else { return "" }
        return "Due \(date.formatted(date: .abbreviated, time: .omitted))"
    }

    // MARK: - Debug logging

    private static func debugStartRun(_ scope: String) {
        #if DEBUG
        Task { @MainActor in ExtractionDebugLog.shared.startRun(scope: scope) }
        #endif
    }

    private static func debugCommitRun() {
        #if DEBUG
        Task { @MainActor in ExtractionDebugLog.shared.commitRun() }
        #endif
    }

    private static func debugLog(
        _ phase: ExtractionDebugLog.Entry.Phase,
        _ label: String,
        _ content: String,
        isWarning: Bool = false,
        isError: Bool = false
    ) {
        #if DEBUG
        Task { @MainActor in
            ExtractionDebugLog.shared.log(phase: phase, label: label, content: content,
                                          isWarning: isWarning, isError: isError)
        }
        #endif
    }

    private static func debugLogStage1(_ stage1: CandidateExtraction) {
        #if DEBUG
        let datesStr = stage1.allDates.isEmpty ? "(none)" :
            stage1.allDates.map { $0.formatted(date: .abbreviated, time: .omitted) }.joined(separator: ", ")
        debugLog(.nlStage1, "Dates Detected", datesStr)

        let personsStr = stage1.allPersons.isEmpty ? "(none)" : stage1.allPersons.joined(separator: ", ")
        debugLog(.nlStage1, "Persons Detected", personsStr)

        if stage1.candidates.isEmpty {
            debugLog(.nlStage1, "Task Candidates", "(none found — will use full text)")
        } else {
            for (i, c) in stage1.candidates.enumerated() {
                let dates = c.detectedDates.map { $0.formatted(date: .abbreviated, time: .omitted) }.joined(separator: ", ")
                debugLog(.nlStage1, "Candidate \(i + 1)",
                         "\(c.sentence)\n\ndates: \(dates.isEmpty ? "none" : dates)\npersons: \(c.detectedPersons.joined(separator: ", "))")
            }
        }
        #endif
    }

    private static func debugLogResult(_ result: TaskExtractionResult) {
        #if DEBUG
        if result.tasks.isEmpty {
            debugLog(.result, "Tasks", "(none extracted)")
        } else {
            for (i, task) in result.tasks.enumerated() {
                debugLog(.result, "Task \(i + 1) · \(task.title.prefix(30))",
                         "title: \(task.title)\ndetail: \(task.detail)\nbody: \(task.body)\npriority: \(task.priority)\ndueDate: \(task.dueDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "none")",
                         isWarning: task.detail.contains("⚠"))
            }
        }
        if !result.summary.isEmpty {
            debugLog(.result, "Summary", result.summary)
        }
        if let q = result.openQuestion {
            debugLog(.result, "Open Question", q)
        }
        #endif
    }
}
