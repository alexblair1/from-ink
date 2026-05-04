import Vision
import UIKit
import PencilKit
import FoundationModels

struct PageAnalysisResult {
    var summary: String
    var tasks: [InkTask]
    var openQuestion: String?
    /// Normalized OCR text — stored with cache entries to enable change detection.
    var normalizedOCR: String
    /// SHA256 of normalizedOCR — cache key.
    var ocrHash: String
}

@Generable
private struct PageBrief {
    @Guide(description: "A 1–2 sentence summary of what the notes are about. Be concise and specific.")
    var summary: String

    @Guide(description: "All action items and tasks extracted from the notes.")
    var tasks: [BriefTask]

    @Guide(description: "An unresolved question found in the notes, if any. Empty string if there is none.")
    var openQuestion: String
}

@Generable
private struct BriefTask {
    @Guide(description: "Short, actionable task title as written in the notes.")
    var title: String

    @Guide(description: "Additional context shown as a subtitle in the UI — deadline, project, or category. Empty string if none.")
    var detail: String

    @Guide(description: "Full description or notes for this task. May be multi-sentence. Empty string if none.")
    var body: String

    @Guide(description: "Due date as ISO 8601 string (YYYY-MM-DD) if a specific date or day is mentioned. Empty string if none.")
    var dueDateString: String

    @Guide(description: "Priority: urgent, high, medium, low, or none.")
    var priorityString: String
}

enum PageAnalyzer {

    static func analyze(drawing: PKDrawing) async -> PageAnalysisResult {
        let empty = PageAnalysisResult(summary: "", tasks: [], openQuestion: nil, normalizedOCR: "", ocrHash: "")
        guard !drawing.strokes.isEmpty else { return empty }

        let image = render(drawing)
        let rawText = await visionRecognize(image)
        print("[PageAnalyzer] vision raw → \"\(rawText)\"")
        guard !rawText.isEmpty else { return empty }

        let normalized = OCRNormalizer.normalize(rawText)
        let hash = OCRNormalizer.hash(normalized)

        return await foundationModelsExtract(rawText, normalized: normalized, hash: hash)
    }

    // MARK: - Render

    private static func render(_ drawing: PKDrawing) -> UIImage {
        let bounds = drawing.bounds.isEmpty
            ? CGRect(x: 0, y: 0, width: 400, height: 400)
            : drawing.bounds.insetBy(dx: -32, dy: -32)

        let raw = drawing.image(from: bounds, scale: 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = raw.scale
        return UIGraphicsImageRenderer(size: raw.size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: raw.size))
            raw.draw(in: CGRect(origin: .zero, size: raw.size))
        }
    }

    // MARK: - Vision

    private static func visionRecognize(_ image: UIImage) async -> String {
        await withCheckedContinuation { continuation in
            guard let cgImage = image.cgImage else {
                continuation.resume(returning: "")
                return
            }
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    print("[PageAnalyzer] vision error: \(error)")
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
                print("[PageAnalyzer] perform error: \(error)")
                continuation.resume(returning: "")
            }
        }
    }

    // MARK: - Foundation Models

    private static func foundationModelsExtract(
        _ rawText: String,
        normalized: String,
        hash: String
    ) async -> PageAnalysisResult {
        let prompt = """
        The following text was extracted via OCR from handwritten notes. \
        Extract a brief summary, all action items/tasks, and any open question.

        Notes:
        \(rawText)
        """
        let fallback = PageAnalysisResult(summary: "", tasks: [], openQuestion: nil,
                                          normalizedOCR: normalized, ocrHash: hash)

        return await withTaskGroup(of: PageAnalysisResult?.self) { group in
            group.addTask {
                do {
                    let session = LanguageModelSession()
                    let response = try await session.respond(to: prompt, generating: PageBrief.self)
                    let brief = response.content
                    let tasks = brief.tasks.map { t -> InkTask in
                        InkTask(
                            title: t.title,
                            body: t.body,
                            detail: t.detail,
                            dueDate: parseDate(t.dueDateString),
                            priority: TaskPriority.from(t.priorityString),
                            sourceOCRHash: hash
                        )
                    }
                    let question: String? = brief.openQuestion.isEmpty ? nil : brief.openQuestion
                    return PageAnalysisResult(summary: brief.summary, tasks: tasks,
                                             openQuestion: question,
                                             normalizedOCR: normalized, ocrHash: hash)
                } catch {
                    print("[PageAnalyzer] Foundation Models error: \(error)")
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(15))
                print("[PageAnalyzer] Foundation Models timed out")
                return nil
            }

            let result = await group.next() ?? nil
            group.cancelAll()
            return result ?? fallback
        }
    }

    // MARK: - Helpers

    private static func parseDate(_ iso: String) -> Date? {
        guard !iso.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: iso)
    }
}
