import SwiftUI

/// Editorial masthead — the dominant element at the top of the home screen.
///
/// Modelled after the "Variation C · Editorial" direction from the Daily Brief
/// design spec: large serif date as a newspaper-style header, one-line weather,
/// an AI-generated brief sentence, and inline counts for events / reminders /
/// birthdays. Tapping "Read more" expands to a full editorial brief.
///
/// Entirely stateless — pass a `HomeMasthead.Model` from the feature view.
///
struct HomeMasthead: View {
    let model: Model

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Top bar ────────────────────────────
            topBar
                .padding(.horizontal, 24)

            // ── Masthead block ─────────────────────
            VStack(alignment: .leading, spacing: 0) {
                // Thick top rule — editorial weight
                Rectangle()
                    .fill(Color("ink/Ink"))
                    .frame(height: 2)

                // Topline: "DAILY BRIEF · SYNCED 2M AGO" + weather
                topline
                    .padding(.top, 14)
                    .padding(.horizontal, 24)

                // Big serif date
                dateBlock
                    .padding(.top, 8)
                    .padding(.horizontal, 24)

                // Brief sentence + counts
                briefAndCounts
                    .padding(.top, 10)
                    .padding(.horizontal, 24)

                // Expanded editorial content
                if isExpanded {
                    // Override collapse/viewDetails with local state toggle
                    HomeExpandedBrief(model: HomeExpandedBrief.Model(
                        paragraphs: model.expandedBrief.paragraphs,
                        highlights: model.expandedBrief.highlights,
                        onViewDetails: model.onViewDetails,
                        onCollapse: {
                            withAnimation(.linear(duration: 0.10)) {
                                isExpanded = false
                            }
                        }
                    ))
                    .padding(.top, 16)
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Bottom rule
                Rectangle()
                    .fill(Color("ink/Ink"))
                    .frame(height: 1)
                    .padding(.top, 16)
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            // Leading: wordmark
            Text("From Ink")
                .font(.system(size: 18, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(Color("ink/Ink"))
                .tracking(0.4)

            Spacer()

            // Trailing: new notebook
            Button(action: model.onNewNotebook) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(Color("ink/Ink"))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Topline

    private var topline: some View {
        HStack {
            MonoLabel("Daily brief · \(model.syncLabel)", color: Color("ink/Ink3"))

            Spacer()

            // Weather
            if let weather = model.weather {
                HStack(spacing: 6) {
                    Image(systemName: weather.symbolName)
                        .font(.system(size: 12, weight: .regular))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Color("ink/Ink"))

                    if let transition = weather.transitionSymbol {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8, weight: .regular))
                            .foregroundStyle(Color("ink/Ink3"))
                        Image(systemName: transition)
                            .font(.system(size: 12, weight: .regular))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(Color("ink/Ink"))
                    }

                    HairlineRule(.vertical)
                        .frame(height: 10)

                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 11, weight: .regular))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Color("ink/Ink"))
                    MonoLabel(weather.temperature, color: Color("ink/Ink2"))

                    if let sunrise = weather.sunrise, let sunset = weather.sunset {
                        MonoLabel("↑\(sunrise) ↓\(sunset)", color: Color("ink/Ink3"))
                    }
                }
            }
        }
    }

    // MARK: - Date block

    private var dateBlock: some View {
        HStack(alignment: .firstTextBaseline) {
            // Large serif date
            (
                Text(model.weekday)
                    .foregroundStyle(Color("ink/Ink"))
                +
                Text(",")
                    .foregroundStyle(Color("ink/Ink2"))
            )
            .font(.system(size: 38, weight: .light, design: .serif))
            .tracking(-0.5)

            Text("\(model.monthDay).")
                .font(.system(size: 28, weight: .light, design: .serif))
                .italic()
                .foregroundStyle(Color("ink/Ink2"))

            Spacer()

            // Read more / Collapse toggle
            Button {
                withAnimation(.linear(duration: 0.10)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(isExpanded ? "COLLAPSE" : "READ MORE")
                        .underline(color: Color("ink/Ink"))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(11 * 0.18)
                .foregroundStyle(Color("ink/Ink"))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Brief sentence + counts

    private var briefAndCounts: some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            // Brief sentence
            Text(model.briefSentence)
                .font(.system(size: 17, weight: .regular, design: .serif))
                .foregroundStyle(Color("ink/Ink"))
                .lineSpacing(4)
                .frame(maxWidth: 720, alignment: .leading)

            Spacer(minLength: 16)

            // Inline counts
            HStack(spacing: 18) {
                countBadge(icon: "calendar", count: model.eventCount, label: "events")
                countBadge(icon: "checklist", count: model.reminderCount, label: "due")
                if model.birthdayCount > 0 {
                    countBadge(icon: "person.crop.circle", count: model.birthdayCount, label: "birthday")
                }
            }
        }
    }

    private func countBadge(icon: String, count: Int, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color("ink/Ink"))
            Text("\(count)")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color("ink/Ink"))
            MonoLabel(label, color: Color("ink/Ink2"))
        }
    }
}

// MARK: - Model

extension HomeMasthead {
    struct Model {
        let weekday: String
        let monthDay: String
        let syncLabel: String
        let briefSentence: String
        let eventCount: Int
        let reminderCount: Int
        let birthdayCount: Int
        let weather: WeatherInfo?
        let expandedBrief: HomeExpandedBrief.Model
        let onNewNotebook: () -> Void
        let onViewDetails: () -> Void

        struct WeatherInfo {
            let symbolName: String
            let transitionSymbol: String?
            let temperature: String
            let sunrise: String?
            let sunset: String?
        }
    }
}
