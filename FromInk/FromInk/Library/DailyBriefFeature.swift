import Foundation
import FoundationModels
import ComposableArchitecture

// MARK: - Foundation Models dependency

struct FoundationModelsService: Sendable {
    var isAvailable: @Sendable () -> Bool
    var generateBrief: @Sendable (String) async throws -> DailyBrief
}

extension FoundationModelsService: DependencyKey {
    static var liveValue: Self {
        .init(
            isAvailable: {
                SystemLanguageModel.default.isAvailable
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
            generateBrief: { _ in
                DailyBrief(
                    greeting: "Good morning.",
                    focus: "Review the product spec before the 10am meeting.",
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

func buildBriefPrompt(
    events: [CalendarEventSnapshot],
    reminders: [ReminderSnapshot],
    pendingInk: [String]
) -> String {
    var parts: [String] = [
        "Generate a concise daily brief for the user. Today is \(Date().formatted(date: .complete, time: .omitted))."
    ]
    if events.isEmpty {
        parts.append("Calendar: No events today.")
    } else {
        let formatted = events.map {
            "- \($0.startDate.formatted(.dateTime.hour().minute())): \($0.title)"
        }.joined(separator: "\n")
        parts.append("Calendar events:\n\(formatted)")
    }
    if reminders.isEmpty {
        parts.append("Reminders: None due today.")
    } else {
        let formatted = reminders.prefix(5).map { "- \($0.title)" }.joined(separator: "\n")
        parts.append("Due reminders:\n\(formatted)")
    }
    if !pendingInk.isEmpty {
        let formatted = pendingInk.prefix(5).map { "- \($0)" }.joined(separator: "\n")
        parts.append("Unrouted From Ink tasks:\n\(formatted)")
    }
    parts.append("Be concise. Focus sentence: one sentence. Suggestion: empty string if nothing useful.")
    return parts.joined(separator: "\n\n")
}

// MARK: - Reducer
//
// Manually conforms to Reducer instead of using @Reducer macro.
// @Reducer expands `body: some ReducerOf<Self>` and resolves `Self` during macro
// expansion — when @Generable types appear in State/Action this creates a circular
// macro expansion that the compiler cannot resolve. Explicit conformance breaks the loop.

struct DailyBriefFeature: Reducer {

    @ObservableState struct State: Equatable {
        var brief: DailyBrief? = nil
        var weather: WeatherSnapshot? = nil
        var weatherAttribution: WeatherAttributionSnapshot? = nil
        var isLoading: Bool = false
        var lastRefreshed: Date? = nil
        var isExpanded: Bool = false
    }

    // No @CasePathable — leaf feature, no child scoping needed.
    // Plain switch in Reduce closure works without it.
    enum Action {
        case appeared
        case refresh
        case briefLoaded(DailyBrief)
        case weatherLoaded(WeatherSnapshot?)
        case attributionLoaded(WeatherAttributionSnapshot?)
        case briefFailed
        case expandToggled
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

                            guard foundationModels.isAvailable() else {
                                await send(.briefLoaded(.raw(events: events, reminders: reminders)))
                                return
                            }

                            let prompt = buildBriefPrompt(
                                events: events,
                                reminders: reminders,
                                pendingInk: []
                            )
                            do {
                                let brief = try await foundationModels.generateBrief(prompt)
                                await send(.briefLoaded(brief))
                            } catch {
                                await send(.briefLoaded(.raw(events: events, reminders: reminders)))
                            }
                        } catch {
                            await send(.briefFailed)
                        }
                    },
                    .run { send in
                        let location = await locationService.currentLocation()
                        guard let location else {
                            await send(.weatherLoaded(nil))
                            return
                        }
                        let snapshot = await weatherService.fetch(location)
                        await send(.weatherLoaded(snapshot))
                    },
                    .run { send in
                        let attribution = await weatherService.fetchAttribution()
                        await send(.attributionLoaded(attribution))
                    }
                )

            case .briefLoaded(let brief):
                state.brief = brief
                state.isLoading = false
                state.lastRefreshed = Date()
                return .none

            case .weatherLoaded(let snapshot):
                state.weather = snapshot
                return .none

            case .attributionLoaded(let attribution):
                state.weatherAttribution = attribution
                return .none

            case .briefFailed:
                state.isLoading = false
                return .none

            case .expandToggled:
                state.isExpanded.toggle()
                return .none
            }
        }
    }
}
