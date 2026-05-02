import Vision
import UIKit
import FoundationModels

@Generable
private struct CorrectedText {
    @Guide(description: "The corrected text with handwriting OCR errors fixed. Only the corrected text, nothing else.")
    var text: String
}

enum LassoOCR {
    /// Composite `image` onto a white background so Vision can see the ink.
    private static func whiteBackground(_ image: UIImage) -> UIImage {
        let size = image.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    static func recognize(image: UIImage) async -> String {
        let flatImage = whiteBackground(image)
        print("[OCR] starting recognition, image=\(flatImage.size) scale=\(flatImage.scale)")
        let raw = await visionRecognize(flatImage)
        print("[OCR] vision raw → \"\(raw)\"")
        guard !raw.isEmpty else { return raw }
        let corrected = await foundationModelsCorrect(raw)
        print("[OCR] corrected → \"\(corrected)\"")
        return corrected
    }

    // MARK: - Vision

    private static func visionRecognize(_ image: UIImage) async -> String {
        await withCheckedContinuation { continuation in
            guard let cgImage = image.cgImage else {
                print("[OCR] no cgImage — aborting")
                continuation.resume(returning: "")
                return
            }

            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    print("[OCR] vision error: \(error)")
                    continuation.resume(returning: "")
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation],
                      !observations.isEmpty else {
                    print("[OCR] no observations")
                    continuation.resume(returning: "")
                    return
                }
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: " ")
                print("[OCR] recognized \(observations.count) observations → \"\(text)\"")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]

            do {
                try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
            } catch {
                print("[OCR] perform error: \(error)")
                continuation.resume(returning: "")
            }
        }
    }

    // MARK: - Foundation Models correction

    private static func foundationModelsCorrect(_ rawText: String) async -> String {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                do {
                    let session = LanguageModelSession()
                    let response = try await session.respond(
                        to: "Fix any handwriting OCR errors in this text, correcting misread characters and broken words while preserving the original meaning: \(rawText)",
                        generating: CorrectedText.self
                    )
                    return response.content.text.trimmingCharacters(in: .whitespacesAndNewlines)
                } catch {
                    print("[OCR] Foundation Models error: \(error)")
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(8))
                print("[OCR] Foundation Models timed out — using raw text")
                return nil
            }

            let result = await group.next() ?? nil
            group.cancelAll()
            return result ?? rawText
        }
    }
}
