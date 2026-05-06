import SwiftUI
import ComposableArchitecture

struct DailyBriefCard: View {
    @Bindable var store: StoreOf<DailyBriefFeature>
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            collapseBar

            if store.isExpanded, let brief = store.brief {
                Rectangle().fill(Color.border).frame(height: 1)
                expandedContent(brief)
            }

            if store.isLoading && store.brief == nil {
                loadingView
            }
        }
        .background(Color.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.border).frame(height: 1)
        }
        .onAppear { _ = store.send(.appeared) }
    }

    // MARK: - Collapsed bar

    private var collapseBar: some View {
        Button {
            withAnimation(.linear(duration: 0.12)) {
                _ = store.send(.expandToggled)
            }
        } label: {
            HStack(spacing: 8) {
                Text(Date().formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.inkSecondary)
                    .textCase(.uppercase)
                    .kerning(0.4)

                if let brief = store.brief {
                    Text("·")
                        .foregroundStyle(Color.border)
                        .font(.system(size: 12))

                    if let weather = store.weather {
                        weatherBadge(weather)
                    }

                    if !brief.schedule.isEmpty || !brief.urgentReminders.isEmpty {
                        Text("·")
                            .foregroundStyle(Color.border)
                            .font(.system(size: 12))

                        Text(summaryCounts(brief))
                            .font(.system(size: 12))
                            .foregroundStyle(Color.inkSecondary)
                    }
                }

                Spacer()

                if store.brief != nil {
                    Text(store.isExpanded ? "COLLAPSE" : "READ MORE")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.inkSecondary)
                        .kerning(0.6)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded content

    private func expandedContent(_ brief: DailyBrief) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(brief.greeting)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.ink)

                if let weather = store.weather {
                    weatherBadge(weather)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)

            if !brief.focus.isEmpty {
                Text(brief.focus)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.inkSecondary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }

            if !brief.schedule.isEmpty {
                sectionHeader("Today")
                ForEach(Array(brief.schedule.enumerated()), id: \.offset) { _, event in
                    scheduleRow(event)
                }
                Spacer().frame(height: 12)
            }

            if !brief.urgentReminders.isEmpty {
                sectionHeader("Reminders Due")
                ForEach(Array(brief.urgentReminders.enumerated()), id: \.offset) { _, reminder in
                    reminderRow(reminder)
                }
                Spacer().frame(height: 12)
            }

            if !brief.suggestion.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.inkSecondary)
                        .frame(width: 16)
                    Text(brief.suggestion)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.inkSecondary)
                        .italic()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }

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
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
                .tint(Color.inkSecondary)
            Text("Loading brief...")
                .font(.system(size: 12))
                .foregroundStyle(Color.inkSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Row builders

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.inkSecondary)
            .textCase(.uppercase)
            .kerning(0.5)
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
    }

    private func scheduleRow(_ event: DailyBrief.BriefEvent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(event.time)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.inkSecondary)
                .frame(width: 56, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ink)
                if !event.note.isEmpty {
                    Text(event.note)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.inkSecondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 5)
    }

    private func reminderRow(_ title: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle")
                .font(.system(size: 10))
                .foregroundStyle(Color.inkSecondary)
                .padding(.top, 2)

            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Color.ink)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
    }

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

    private func summaryCounts(_ brief: DailyBrief) -> String {
        var parts: [String] = []
        if !brief.schedule.isEmpty {
            parts.append("\(brief.schedule.count) event\(brief.schedule.count == 1 ? "" : "s")")
        }
        if !brief.urgentReminders.isEmpty {
            parts.append("\(brief.urgentReminders.count) due")
        }
        return parts.joined(separator: " · ")
    }
}
