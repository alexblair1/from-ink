import SwiftUI
import ComposableArchitecture

struct DailyBriefCard: View {
    @Bindable var store: StoreOf<DailyBriefFeature>
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Title row
            HStack(alignment: .center, spacing: 8) {
                Text("Daily Brief")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.inkSecondary)
                    .textCase(.uppercase)
                    .kerning(0.5)

                Spacer()

                if let weather = store.weather {
                    weatherBadge(weather)
                }

                if store.isLoading {
                    ProgressView()
                        .scaleEffect(0.65)
                        .tint(Color.inkSecondary)
                }

                if !store.events.isEmpty || !store.reminders.isEmpty {
                    Button { showDetails = true } label: {
                        Text("Details")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.border.opacity(0.4))
                            .overlay {
                                Rectangle().strokeBorder(Color.border, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Prose paragraph — FM brief when ready, fallback narrative while loading
            let paragraph = store.brief?.focus.isEmpty == false
                ? store.brief!.focus
                : narrativeFallback(events: store.events, reminders: store.reminders)

            if !paragraph.isEmpty {
                Text(paragraph)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ink)
                    .lineSpacing(3)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
                    .transition(.opacity)
                    .animation(.easeIn(duration: 0.25), value: store.brief?.focus)
            }
        }
        .background(Color.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.border).frame(height: 1)
        }
        .onAppear { _ = store.send(.appeared) }
        .sheet(isPresented: $showDetails) {
            BriefDetailsSheet(store: store)
        }
    }

    // MARK: - Deterministic fallback paragraph

    private func narrativeFallback(
        events: [CalendarEventSnapshot],
        reminders: [ReminderSnapshot]
    ) -> String {
        guard !events.isEmpty || !reminders.isEmpty else { return "" }

        var sentences: [String] = []

        switch events.count {
        case 0:
            sentences.append("No events scheduled today.")
        case 1:
            sentences.append(
                "You have \(events[0].title) at \(formatTime(events[0].startDate)) today."
            )
        case 2:
            sentences.append(
                "You have \(events[0].title) at \(formatTime(events[0].startDate)) and \(events[1].title) at \(formatTime(events[1].startDate)) today."
            )
        default:
            let listed = events.prefix(3).map { "\($0.title) at \(formatTime($0.startDate))" }
            let tail = events.count > 3 ? " and \(events.count - 3) more" : ""
            sentences.append("Today: \(listed.joined(separator: ", "))\(tail).")
        }

        switch reminders.count {
        case 0:
            break
        case 1:
            sentences.append("'\(reminders[0].title)' is due today.")
        default:
            sentences.append(
                "\(reminders.count) reminders are due, starting with '\(reminders[0].title)'."
            )
        }

        return sentences.joined(separator: " ")
    }

    private func formatTime(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    // MARK: - Weather badge

    @ViewBuilder
    private func weatherBadge(_ weather: WeatherSnapshot) -> some View {
        HStack(spacing: 4) {
            Image(systemName: weather.symbolName)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 12))
                .foregroundStyle(Color.inkSecondary)
            Text(weather.formattedTemperature)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.inkSecondary)
        }
    }
}

// MARK: - Details sheet

private struct BriefDetailsSheet: View {
    let store: StoreOf<DailyBriefFeature>
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Daily Brief")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.ink)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.inkSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Rectangle().fill(Color.border).frame(height: 1)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    // AI brief paragraph + suggestion
                    if let brief = store.brief {
                        VStack(alignment: .leading, spacing: 8) {
                            if !brief.greeting.isEmpty {
                                Text(brief.greeting)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.ink)
                            }
                            if !brief.focus.isEmpty {
                                Text(brief.focus)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.ink)
                                    .lineSpacing(3)
                            }
                            if !brief.suggestion.isEmpty {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "lightbulb")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.inkSecondary)
                                        .padding(.top, 1)
                                    Text(brief.suggestion)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.inkSecondary)
                                        .italic()
                                        .lineSpacing(2)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)

                        Rectangle().fill(Color.border).frame(height: 1)
                    }

                    // Events
                    sectionHeader("Today")
                    if store.events.isEmpty {
                        emptyRow("No events today")
                    } else {
                        ForEach(Array(store.events.enumerated()), id: \.offset) { _, event in
                            eventRow(event)
                            Rectangle().fill(Color.border).frame(height: 1)
                                .padding(.leading, 20)
                        }
                    }

                    Spacer().frame(height: 20)

                    // Reminders
                    sectionHeader("Reminders Due")
                    if store.reminders.isEmpty {
                        emptyRow("No reminders due today")
                    } else {
                        ForEach(Array(store.reminders.enumerated()), id: \.offset) { _, reminder in
                            reminderRow(reminder)
                            Rectangle().fill(Color.border).frame(height: 1)
                                .padding(.leading, 20)
                        }
                    }

                    // Weather attribution
                    if let attribution = store.weatherAttribution {
                        HStack {
                            Spacer()
                            Link(destination: attribution.legalPageURL) {
                                AsyncImage(url: colorScheme == .dark
                                    ? attribution.darkLogoURL
                                    : attribution.lightLogoURL
                                ) { image in
                                    image.resizable().scaledToFit()
                                } placeholder: {
                                    Color.clear
                                }
                                .frame(height: 10)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 8)
                    }
                }
                .padding(.top, 8)
            }
        }
        .background(Color.surface)
        .presentationDetents([.medium, .large])
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.inkSecondary)
            .textCase(.uppercase)
            .kerning(0.5)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
    }

    private func eventRow(_ event: CalendarEventSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(event.startDate.formatted(.dateTime.hour().minute()))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 56, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.ink)
                if !event.calendarTitle.isEmpty {
                    Text(event.calendarTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func reminderRow(_ reminder: ReminderSnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "circle")
                .font(.system(size: 11))
                .foregroundStyle(Color.inkSecondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.ink)
                if let due = reminder.dueDate {
                    Text(due.formatted(.relative(presentation: .named)))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func emptyRow(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13))
            .foregroundStyle(Color.inkSecondary.opacity(0.5))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
    }
}
