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
    @Binding var isExpanded: Bool

    private let ds = DesignSystem.standard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Masthead block ─────────────────────
            VStack(alignment: .leading, spacing: 0) {
                // Thick top rule — editorial weight
                Rectangle()
                    .fill(ds.colors.ink)
                    .frame(height: 2)

                // Topline: "DAILY BRIEF · SYNCED 2M AGO" + weather
                topline
                    .padding(.top, ds.spacing.md)

                // Big serif date
                dateBlock
                    .padding(.top, ds.spacing.sm)

                // Brief sentence + counts
                briefAndCounts
                    .padding(.top, ds.spacing.sm)

                // Expanded editorial content
                if isExpanded {
                    // Override collapse/viewDetails with local state toggle
                    HomeExpandedBrief(model: HomeExpandedBrief.Model(
                        paragraphs: model.expandedBrief.paragraphs,
                        highlights: model.expandedBrief.highlights,
                        onViewDetails: model.onViewDetails,
                        onCollapse: {
                            withAnimation(ds.animation.standard) {
                                isExpanded = false
                            }
                        }
                    ))
                    .padding(.top, ds.spacing.base)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Bottom rule
                Rectangle()
                    .fill(ds.colors.ink)
                    .frame(height: 1)
                    .padding(.top, ds.spacing.base)
            }
            .padding(.horizontal, ds.spacing.lg)
        }
    }

    // MARK: - Topline

    private var topline: some View {
        HStack {
            MonoLabel("\(AppStrings.Home.dailyBrief) · \(model.syncLabel)", color: ds.colors.ink3)

            Spacer()

            // Weather
            if let weather = model.weather {
                HStack(spacing: 6) {
                    Image(systemName: weather.symbolName)
                        .font(ds.typography.caption)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(ds.colors.ink)

                    if let transition = weather.transitionSymbol {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8, weight: .regular))
                            .foregroundStyle(ds.colors.ink3)
                        Image(systemName: transition)
                            .font(ds.typography.caption)
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(ds.colors.ink)
                    }

                    HairlineRule(.vertical)
                        .frame(height: 10)

                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 11, weight: .regular))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(ds.colors.ink)
                    MonoLabel(weather.temperature, color: ds.colors.ink2)

                    if let sunrise = weather.sunrise, let sunset = weather.sunset {
                        MonoLabel("↑\(sunrise) ↓\(sunset)", color: ds.colors.ink3)
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
                    .foregroundStyle(ds.colors.ink)
                +
                Text(",")
                    .foregroundStyle(ds.colors.ink2)
            )
            .font(ds.typography.display(size: 38))
            .tracking(-0.5)

            Text("\(model.monthDay).")
                .font(ds.typography.display(size: 28))
                .italic()
                .foregroundStyle(ds.colors.ink2)

            Spacer()

            // Read more / Collapse toggle
            Button {
                withAnimation(ds.animation.standard) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(isExpanded ? AppStrings.Home.collapse.uppercased() : AppStrings.Home.readMore.uppercased())
                        .underline(color: ds.colors.ink)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                }
                .font(ds.typography.monoLabel)
                .tracking(11 * 0.18)
                .foregroundStyle(ds.colors.ink)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Brief sentence + counts

    private var briefAndCounts: some View {
        HStack(alignment: .firstTextBaseline, spacing: ds.spacing.lg) {
            // Brief sentence
            Text(model.briefSentence)
                .font(.system(size: 17, weight: .regular, design: .serif))
                .foregroundStyle(ds.colors.ink)
                .lineSpacing(ds.spacing.xs)
                .frame(maxWidth: 720, alignment: .leading)

            Spacer(minLength: ds.spacing.base)

            // Inline counts
            HStack(spacing: 18) {
                countBadge(icon: "calendar", count: model.eventCount, label: AppStrings.Home.events)
                countBadge(icon: "checklist", count: model.reminderCount, label: AppStrings.Home.due)
                if model.birthdayCount > 0 {
                    countBadge(icon: "person.crop.circle", count: model.birthdayCount, label: AppStrings.Home.birthday)
                }
            }
        }
    }

    private func countBadge(icon: String, count: Int, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(ds.typography.footnote)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(ds.colors.ink)
            Text("\(count)")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(ds.colors.ink)
            MonoLabel(label, color: ds.colors.ink2)
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
