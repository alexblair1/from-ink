import SwiftUI

/// One row in the Birthdays tab — a contact card with initials avatar,
/// name, relationship context, optional long-form note, and an age label.
///
/// Layout: [ initials circle | name + relationship + note | age label ]
///
/// Stateless. The note line is shown iff `note` is non-nil; the age label
/// iff `ageLabel` is non-nil. Relationship lines are similarly optional.
///
struct BriefBirthdayRow: View {
    let model: Model

    var body: some View {
        HStack(alignment: .top, spacing: model.columnGap) {
            initialsAvatar

            VStack(alignment: .leading, spacing: model.innerSpacing) {
                Text(model.name)
                    .font(.system(size: model.nameFontSize, weight: .regular, design: .serif))
                    .foregroundStyle(model.nameColor)
                    .lineLimit(2)

                if let relationship = model.relationship {
                    Text(relationship)
                        .font(.system(size: model.relationshipFontSize, weight: .regular, design: .monospaced))
                        .foregroundStyle(model.relationshipColor)
                }

                if let note = model.note {
                    Text(note)
                        .font(.system(size: model.noteFontSize, weight: .regular))
                        .foregroundStyle(model.noteColor)
                        .lineSpacing(2)
                        .padding(.top, 4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            if let ageLabel = model.ageLabel {
                Text(ageLabel)
                    .font(.system(size: model.ageFontSize, weight: .medium, design: .monospaced))
                    .tracking(model.ageTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(model.ageColor)
                    .padding(.top, model.ageTopPadding)
            }
        }
        .padding(.vertical, model.verticalPadding)
        .overlay(alignment: .bottom) {
            if !model.hidesBottomRule {
                Rectangle()
                    .fill(model.ruleColor)
                    .frame(height: 1)
            }
        }
    }

    private var initialsAvatar: some View {
        Text(model.initials)
            .font(.system(size: model.initialsFontSize, weight: .regular, design: .serif))
            .foregroundStyle(model.nameColor)
            .frame(width: model.avatarSize, height: model.avatarSize)
            .overlay(
                Circle()
                    .stroke(model.avatarBorderColor, lineWidth: 1)
            )
    }
}

// MARK: - Model

extension BriefBirthdayRow {
    struct Model: Identifiable {
        let id: String
        let initials: String
        let name: String
        let relationship: String?
        let note: String?
        let ageLabel: String?
        /// True for the last row in a list — suppresses the bottom rule
        /// to avoid stacking with the following section header's rule.
        let hidesBottomRule: Bool

        let columnGap: CGFloat
        let innerSpacing: CGFloat
        let avatarSize: CGFloat
        let initialsFontSize: CGFloat
        let nameFontSize: CGFloat
        let relationshipFontSize: CGFloat
        let noteFontSize: CGFloat
        let ageFontSize: CGFloat
        let ageTracking: CGFloat
        let ageTopPadding: CGFloat
        let verticalPadding: CGFloat

        let avatarBorderColor: Color
        let nameColor: Color
        let relationshipColor: Color
        let noteColor: Color
        let ageColor: Color
        let ruleColor: Color
    }
}

// MARK: - Model init

extension BriefBirthdayRow.Model {
    init(
        id: String,
        initials: String,
        name: String,
        relationship: String?,
        note: String?,
        ageLabel: String?,
        hidesBottomRule: Bool = false,
        ds: DesignSystem = .standard
    ) {
        self.id = id
        self.initials = initials
        self.name = name
        self.relationship = relationship
        self.note = note
        self.ageLabel = ageLabel
        self.hidesBottomRule = hidesBottomRule

        self.columnGap = 14
        self.innerSpacing = 4
        self.avatarSize = 38
        self.initialsFontSize = 14
        self.nameFontSize = 18
        self.relationshipFontSize = 11
        self.noteFontSize = 13
        self.ageFontSize = 10
        self.ageTracking = 1.5
        self.ageTopPadding = 6
        // 14pt to match the React spec — same value as BriefEventRow.
        self.verticalPadding = 14

        self.avatarBorderColor = ds.colors.ink
        self.nameColor = ds.colors.ink
        self.relationshipColor = ds.colors.ink2
        self.noteColor = ds.colors.ink2
        self.ageColor = ds.colors.ink2
        self.ruleColor = ds.colors.rule
    }
}
