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

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HairlineRule()
                .padding(.bottom, 20)

            if sizeClass == .regular {
                // Two-column layout for iPad
                HStack(alignment: .top, spacing: 0) {
                    editorialColumn
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HairlineRule(.vertical)
                        .padding(.horizontal, 28)

                    highlightsColumn
                        .frame(width: 320, alignment: .leading)
                }
            } else {
                // Stacked layout for iPhone
                editorialColumn
                highlightsColumn
                    .padding(.top, 20)
            }

            // Footer actions
            footerActions
                .padding(.top, 16)
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
                    .foregroundStyle(Color("ink/Ink2"))
                MonoLabel("Editor's note", color: Color("ink/Ink2"))
            }
            .padding(.bottom, 10)

            // Paragraphs
            ForEach(Array(model.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                Text(paragraph)
                    .font(.system(size: 15, weight: .regular, design: .serif))
                    .foregroundStyle(Color("ink/Ink"))
                    .lineSpacing(5)
                    .padding(.top, index == 0 ? 0 : 14)
            }
        }
    }

    // MARK: - Highlights column

    private var highlightsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            MonoLabel("Highlights", color: Color("ink/Ink2"))
                .padding(.bottom, 10)

            ForEach(Array(model.highlights.enumerated()), id: \.offset) { index, highlight in
                VStack(alignment: .leading, spacing: 0) {
                    if index > 0 {
                        HairlineRule()
                    }

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: highlight.icon)
                            .font(.system(size: 12, weight: .regular))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(Color("ink/Ink"))
                            .frame(width: 20, alignment: .center)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 2) {
                            MonoLabel(highlight.label, color: Color("ink/Ink2"))
                            Text(highlight.text)
                                .font(.system(size: 14, weight: .regular, design: .serif))
                                .foregroundStyle(Color("ink/Ink"))
                                .lineSpacing(3)
                        }
                    }
                    .padding(.vertical, 10)
                }
            }
        }
    }

    // MARK: - Footer actions

    private var footerActions: some View {
        VStack(spacing: 0) {
            HairlineRule()

            HStack(spacing: 14) {
                InkButton("View details →", style: .filled, action: model.onViewDetails)

                Button(action: model.onCollapse) {
                    HStack(spacing: 4) {
                        Text("COLLAPSE")
                        Image(systemName: "chevron.up")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(11 * 0.18)
                    .foregroundStyle(Color("ink/Ink2"))
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.top, 12)
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
