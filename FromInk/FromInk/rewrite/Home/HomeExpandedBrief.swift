import SwiftUI

/// The expanded editorial brief — shown when "Read more" is tapped on the masthead.
///
/// Two-column layout on iPad:
///   Left:  Multi-paragraph editorial note in serif (the AI's "editor's note")
///   Right: Highlight column — next event, overdue reminders, birthdays
///
/// Single-column on iPhone — highlights stack beneath the editorial.
///
struct HomeExpandedBrief: View {
    let model: Model

    private let ds = DesignSystem.standard
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HairlineRule()
                .padding(.bottom, ds.spacing.base)

            if sizeClass == .regular {
                // Two-column layout for iPad
                HStack(alignment: .top, spacing: 0) {
                    editorialColumn
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HairlineRule(.vertical)
                        .padding(.horizontal, ds.spacing.lg)

                    highlightsColumn
                        .frame(width: 320, alignment: .leading)
                }
            } else {
                // Stacked layout for iPhone
                editorialColumn
                highlightsColumn
                    .padding(.top, ds.spacing.base)
            }

            // Footer actions
            footerActions
                .padding(.top, ds.spacing.base)
        }
    }

    // MARK: - Editorial column

    private var editorialColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section label
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(ds.colors.ink2)
                MonoLabel(AppStrings.Home.editorsNote, color: ds.colors.ink2)
            }
            .padding(.bottom, ds.spacing.sm)

            // Paragraphs
            ForEach(Array(model.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                Text(paragraph)
                    .font(.system(size: 15, weight: .regular, design: .serif))
                    .foregroundStyle(ds.colors.ink)
                    .lineSpacing(5)
                    .padding(.top, index == 0 ? 0 : ds.spacing.md)
            }
        }
    }

    // MARK: - Highlights column

    private var highlightsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            MonoLabel(AppStrings.Home.highlights, color: ds.colors.ink2)
                .padding(.bottom, ds.spacing.sm)

            ForEach(Array(model.highlights.enumerated()), id: \.offset) { index, highlight in
                VStack(alignment: .leading, spacing: 0) {
                    if index > 0 {
                        HairlineRule()
                    }

                    HStack(alignment: .top, spacing: ds.spacing.sm) {
                        Image(systemName: highlight.icon)
                            .font(ds.typography.caption)
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(ds.colors.ink)
                            .frame(width: 20, alignment: .center)
                            .padding(.top, ds.spacing.xxs)

                        VStack(alignment: .leading, spacing: ds.spacing.xxs) {
                            MonoLabel(highlight.label, color: ds.colors.ink2)
                            Text(highlight.text)
                                .font(.system(size: 14, weight: .regular, design: .serif))
                                .foregroundStyle(ds.colors.ink)
                                .lineSpacing(3)
                        }
                    }
                    .padding(.vertical, ds.spacing.sm)
                }
            }
        }
    }

    // MARK: - Footer actions

    private var footerActions: some View {
        VStack(spacing: 0) {
            HairlineRule()

            HStack(spacing: ds.spacing.md) {
                InkButton("\(AppStrings.Home.viewDetails) →", style: .filled, action: model.onViewDetails)

                Button(action: model.onCollapse) {
                    HStack(spacing: ds.spacing.xs) {
                        Text(AppStrings.Home.collapse.uppercased())
                        Image(systemName: "chevron.up")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .font(ds.typography.monoLabel)
                    .tracking(11 * 0.18)
                    .foregroundStyle(ds.colors.ink2)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.top, ds.spacing.md)
        }
    }
}

// MARK: - Model

extension HomeExpandedBrief {
    struct Model {
        let paragraphs: [String]
        let highlights: [Highlight]
        let onViewDetails: () -> Void
        let onCollapse: () -> Void

        struct Highlight {
            let icon: String
            let label: String
            let text: String
        }
    }
}
