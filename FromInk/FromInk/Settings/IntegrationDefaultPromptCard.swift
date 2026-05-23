import SwiftUI

/// "Just added — Make X your default?" prompt. Appears below the
/// provider list as a bordered card after the user adds a 2nd+
/// account for a provider that already has a default. Two side-by-
/// side buttons inside an ink-bordered strip; tapping outside the
/// card dismisses it without committing either way.
///
/// Component view: zero state, zero TCA.
///
struct IntegrationDefaultPromptCard: View {
    let model: Model

    private let ds = DesignSystem.standard

    var body: some View {
        VStack(alignment: .leading, spacing: ds.spacing.sm) {
            MonoLabel(model.caption, color: ds.colors.ink2)

            Text(model.question)
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(ds.colors.ink)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 0) {
                Button(action: model.onKeepCurrent) {
                    Text(model.keepCurrentLabel)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(ds.colors.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: ds.layout.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Rectangle()
                    .fill(ds.colors.ink)
                    .frame(width: 1)

                Button(action: model.onMakeDefault) {
                    Text(model.switchLabel)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ds.colors.paperOnInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: ds.layout.hitTarget)
                        .background(ds.colors.ink)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .overlay(
                Rectangle().strokeBorder(ds.colors.ink, lineWidth: 1)
            )
        }
        .padding(.horizontal, ds.spacing.sm)
        .padding(.vertical, ds.spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(ds.colors.ink).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(ds.colors.ink).frame(height: 1)
        }
    }
}

// MARK: - Model

extension IntegrationDefaultPromptCard {
    struct Model: Equatable {
        let caption: String
        let question: String
        let keepCurrentLabel: String
        let switchLabel: String
        let onMakeDefault: () -> Void
        let onKeepCurrent: () -> Void

        static func == (lhs: Model, rhs: Model) -> Bool {
            lhs.caption == rhs.caption
                && lhs.question == rhs.question
                && lhs.keepCurrentLabel == rhs.keepCurrentLabel
                && lhs.switchLabel == rhs.switchLabel
        }
    }
}
