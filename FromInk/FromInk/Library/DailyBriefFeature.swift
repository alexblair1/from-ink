import Foundation
import FoundationModels
import ComposableArchitecture

// MARK: - Foundation Models dependency
//
// Kept separate from DailyBrief.swift (@Generable) to avoid circular macro expansion.
// DailyBriefFeature conforms to Reducer manually for the same reason — see comment below.

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

// MARK: - Prompt builder

private func buildBriefPrompt(
    events: [CalendarEventSnapshot],
    reminders: [ReminderSnapshot]
) -> String {
    var parts: [String] = [
        "Generate a concise daily brief. Today is \(Date().formatted(date: .complete, time: .omitted))."
    ]
    if events.isEmpty {
        parts.append("Calendar: No events today.")
    } else {
        let list = events.map { "- \($0.startDate.formatted(.dateTime.hour().minute())): \($0.title)" }
            .joined(separator: "\n")
        parts.append("Calendar events:\n\(list)")
    }
    if !reminders.isEmpty {
        let list = reminders.prefix(5).map { "- \($0.title)" }.joined(separator: "\n")
        parts.append("Due reminders:\n\(list)")
    }
    parts.append("Write 'focus' as a 2–3 sentence paragraph in plain English. Name events by title and time, mention any overdue reminders by name, and close with what matters most. No bullet points or headers. Suggestion: one short actionable tip, or empty string if nothing useful.")
    return parts.joined(separator: "\n\n")
}

// MARK: - Reducer
//
// Manually conforms to Reducer instead of using @Reducer macro.
// @Reducer resolves `ReducerOf<Self>` during macro expansion. When @Generable types
// appear in State/Action this creates a circular macro expansion the compiler cannot
// resolve. Explicit conformance breaks the loop.

struct DailyBriefFeature: Reducer {

    @ObservableState struct State: Equatable {
        var events: [CalendarEventSnapshot] = []
        var reminders: [ReminderSnapshot] = []
        var brief: DailyBrief? = nil
        var weather: WeatherSnapshot? = nil
        var weatherAttribution: WeatherAttributionSnapshot? = nil
        var isLoading: Bool = false
        var lastRefreshed: Date? = nil
    }

    enum Action {
        case appeared
        case refresh
        case rawDataLoaded([CalendarEventSnapshot], [ReminderSnapshot])
        case briefLoaded(DailyBrief)
        case weatherLoaded(WeatherSnapshot?)
        case attributionLoaded(WeatherAttributionSnapshot?)
        case loadFailed
    }

    @Dependency(\.foundationModelsService) var foundationModels
    @Dependency(\.eventKitService) var eventKit
    @Dependency(\.weatherService) var weatherService
    @Dependency(\.locationService) var locationService

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {

            case .appeared:
                if let last = state.lastRefreshed,
                   Date().timeIntervalSince(last) < 1800 { return .none }
                return .send(.refresh)

            case .refresh:
                state.isLoading = true
                return .merge(
                    .run { send in
                        do {
                            let events = try await eventKit.fetchTodayEvents()
                            let reminders = try await eventKit.fetchDueReminders()
                            await send(.rawDataLoaded(events, reminders))

                            // Generate FM brief from the same data
                            guard foundationModels.isAvailable() else { return }
                            
                            let prompt = buildBriefPrompt(events: events, reminders: reminders)
                            
                            do {
                                let brief = try await foundationModels.generateBrief(prompt)
                                await send(.briefLoaded(brief))
                            } catch {
                                // FM failed or guardrailed — raw data already shown, brief stays nil
                            }
                        } catch {
                            await send(.loadFailed)
                        }
                    },
                    .run { send in
                        let location = await locationService.currentLocation()
                        guard let location else { await send(.weatherLoaded(nil)); return }
                        let snapshot = await weatherService.fetch(location)
                        await send(.weatherLoaded(snapshot))
                    },
                    .run { send in
                        let attribution = await weatherService.fetchAttribution()
                        await send(.attributionLoaded(attribution))
                    }
                )

            case .rawDataLoaded(let events, let reminders):
                state.events = events
                state.reminders = reminders
                state.isLoading = false
                state.lastRefreshed = Date()
                return .none

            case .briefLoaded(let brief):
                state.brief = brief
                return .none

            case .weatherLoaded(let snapshot):
                state.weather = snapshot
                return .none

            case .attributionLoaded(let attribution):
                state.weatherAttribution = attribution
                return .none

            case .loadFailed:
                state.isLoading = false
                return .none
            }
        }
    }
}
