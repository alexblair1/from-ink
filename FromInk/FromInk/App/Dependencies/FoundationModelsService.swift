import ComposableArchitecture
import Foundation
import FoundationModels

/// TCA dependency wrapping Apple's on-device Foundation Models
/// framework. Three capabilities:
///
/// - `isAvailable` — whether the device has Apple Intelligence and
///   the system model is loaded.
/// - `supportsLocale` — whether the on-device model can produce
///   output in a given user locale. The framework does NOT
///   auto-detect or fall back across locales (per Apple's docs at
///   `supporting-languages-and-locales`); callers must gate non-
///   English output on this.
/// - `generateBrief` — produces a structured `DailyBrief` from a
///   prompt. The output type is `@Generable` (see `DailyBrief.swift`)
///   so the model's constrained decoding produces parseable Swift.
///
/// Lives at the dependency layer rather than colocated with the
/// brief feature so it can be reused by future on-device FM
/// callers (Dispatch task extraction, OCR refinement, etc.).
///
struct FoundationModelsService: Sendable {
    var isAvailable: @Sendable () -> Bool

    /// Whether Apple's on-device model can produce output in the given
    /// user locale. Per Apple's docs (`supporting-languages-and-locales`),
    /// the framework does NOT auto-detect or fall back across locales —
    /// callers must check support before requesting non-English output.
    /// `SystemLanguageModel.supportedLanguages.supportsLocale(_:)` does
    /// fuzzy matching (Catalan → Spanish, etc.), which is what we want.
    var supportsLocale: @Sendable (Locale) -> Bool

    var generateBrief: @Sendable (String) async throws -> DailyBrief
}

extension FoundationModelsService: DependencyKey {
    static var liveValue: Self {
        .init(
            isAvailable: { SystemLanguageModel.default.isAvailable },
            supportsLocale: { locale in
                SystemLanguageModel.default.supportedLanguages.contains { language in
                    language.languageCode == locale.language.languageCode
                }
            },
            generateBrief: { prompt in
                let session = LanguageModelSession()
                let response = try await session.respond(to: prompt, generating: DailyBrief.self)
                return response.content
            }
        )
    }

    static var testValue: Self {
        .init(
            isAvailable: { true },
            // Tests assume the model supports any locale — the actual
            // gating logic is exercised via the live implementation.
            supportsLocale: { _ in true },
            generateBrief: { _ in
                DailyBrief(
                    greeting: "Good morning.",
                    focus: "Your 10am product review is the priority today.",
                    schedule: [
                        DailyBrief.BriefEvent(time: "10:00 AM", title: "Product Review", note: ""),
                        DailyBrief.BriefEvent(time: "2:00 PM", title: "1:1 with Sarah", note: "")
                    ],
                    urgentReminders: ["Follow up with Sarah re: Q3 budget"],
                    pendingFromInk: [],
                    suggestion: ""
                )
            }
        )
    }
}

extension DependencyValues {
    var foundationModelsService: FoundationModelsService {
        get { self[FoundationModelsService.self] }
        set { self[FoundationModelsService.self] = newValue }
    }
}
