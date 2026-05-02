import Vision
import UIKit
import PencilKit
import FoundationModels

struct PageAnalysisResult {
    var summary: String
    var tasks: [(title: String, detail: String)]
    var openQuestion: String?
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

    @Guide(description: "Optional context such as a deadline, project, or category. Empty string if none.")
    var detail: String
}

enum PageAnalyzer {

    static func analyze(drawing: PKDrawing) async -> PageAnalysisResult {
        guard !drawing.strokes.isEmpty else {
            return PageAnalysisResult(summary: "", tasks: [], openQuestion: nil)
        }

        let image = render(drawing)
        let rawText = await visionRecognize(image)
        print("[PageAnalyzer] vision raw → \"\(rawText)\"")

        guard !rawText.isEmpty else {
            return PageAnalysisResult(summary: "", tasks: [], openQuestion: nil)
        }

        return await foundationModelsExtract(rawText)
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

    private static func foundationModelsExtract(_ rawText: String) async -> PageAnalysisResult {
        await withTaskGroup(of: PageAnalysisResult?.self) { group in
            group.addTask {
                do {
                    let session = LanguageModelSession()
                    let prompt = """
                    The following text was extracted via OCR from handwritten notes. \
                    Extract a brief summary, all action items/tasks, and any open question.

                    Notes:
                    \(rawText)
                    """
                    let response = try await session.respond(to: prompt, generating: PageBrief.self)
                    let brief = response.content
                    let tasks = brief.tasks.map { (title: $0.title, detail: $0.detail) }
                    let question: String? = brief.openQuestion.isEmpty ? nil : brief.openQuestion
                    return PageAnalysisResult(summary: brief.summary, tasks: tasks, openQuestion: question)
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
            return result ?? PageAnalysisResult(summary: "", tasks: [], openQuestion: nil)
        }
    }
}
