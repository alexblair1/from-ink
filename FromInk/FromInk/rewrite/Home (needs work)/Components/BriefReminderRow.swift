import SwiftUI

/// One row in the Reminders tab — a single reminder.
///
/// Layout mirrors `BriefEventRow`: [ time | check + title | list name ].
///
/// Originally the meta line ("Today · 5pm" / "Overdue · 2 days") sat under
/// the title — that made reminders feel different from events at a glance.
/// Reading the two tabs side-by-side felt visually choppy. The meta now
/// occupies the same left-side time column the calendar tab uses, with
/// overdue strings rendering in full ink.
///
/// The check is a circle (open) or an outlined circle with a "!" inside
/// when the reminder is flagged or overdue.
///
/// Stateless.
///
struct BriefReminderRow: View {
    let model: Model

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: model.columnGap) {
            Text(model.metaText)
                .font(.system(size: model.metaFontSize, weight: .regular, design: .monospaced))
                .foregroundStyle(model.isOverdue ? model.metaOverdueColor : model.metaColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
                .frame(width: model.timeColumnWidth, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: model.titleInnerSpacing) {
                checkIndicator
                Text(model.title)
                    .font(.system(size: model.titleFontSize, weight: .regular, design: .serif))
                    .foregroundStyle(model.titleColor)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if let listName = model.listName {
                Text(listName)
                    .font(.system(size: model.listFontSize, weight: .medium, design: .monospaced))
                    .tracking(model.listTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(model.listColor)
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

    @ViewBuilder
    private var checkIndicator: some View {
        if model.isFlagged || model.isOverdue {
            ZStack {
                Circle()
                    .stroke(model.flagBorderColor, lineWidth: 1.4)
                    .frame(width: model.checkSize, height: model.checkSize)
                Text("!")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(model.flagBorderColor)
            }
        } else {
            Circle()
                .stroke(model.checkBorderColor, lineWidth: 1.4)
                .frame(width: model.checkSize, height: model.checkSize)
        }
    }
}

// MARK: - Model

extension BriefReminderRow {
    struct Model: Identifiable {
        let id: String
        let title: String
        /// "Today · 5pm" / "Overdue · 2 days" / "Tomorrow" — pre-formatted
        /// in the wiring view via RelativeDateTimeFormatter or equivalent.
        let metaText: String
        let listName: String?
        let isFlagged: Bool
        let isOverdue: Bool
        /// True for the last row in a list — suppresses the bottom rule
        /// to avoid stacking with the following section header's rule.
        let hidesBottomRule: Bool

        let columnGap: CGFloat
        let timeColumnWidth: CGFloat
        let titleInnerSpacing: CGFloat
        let titleFontSize: CGFloat
        let metaFontSize: CGFloat
        let listFontSize: CGFloat
        let listTracking: CGFloat
        let checkSize: CGFloat
        let verticalPadding: CGFloat

        let titleColor: Color
        let metaColor: Color
        let metaOverdueColor: Color
        let listColor: Color
        let checkBorderColor: Color
        let flagBorderColor: Color
        let ruleColor: Color
    }
}

// MARK: - Model init

extension BriefReminderRow.Model {
    init(
        id: String,
        title: String,
        metaText: String,
        listName: String?,
        isFlagged: Bool,
        isOverdue: Bool,
        hidesBottomRule: Bool = false,
        ds: DesignSystem = .standard
    ) {
        self.id = id
        self.title = title
        self.metaText = metaText
        self.listName = listName
        self.isFlagged = isFlagged
        self.isOverdue = isOverdue
        self.hidesBottomRule = hidesBottomRule

        // Geometry mirrors BriefEventRow so the two row types align
        // visually when stacked. The time/meta column is the same
        // 64pt fixed-width column on the leading side.
        self.columnGap = 18
        self.timeColumnWidth = 64
        self.titleInnerSpacing = 10
        self.titleFontSize = 18
        self.metaFontSize = 12
        self.listFontSize = 10
        self.listTracking = 1.5
        self.checkSize = 14
        self.verticalPadding = 14

        self.titleColor = ds.colors.ink
        self.metaColor = ds.colors.ink2
        self.metaOverdueColor = ds.colors.ink
        self.listColor = ds.colors.ink2
        self.checkBorderColor = ds.colors.ink2
        self.flagBorderColor = ds.colors.ink
        self.ruleColor = ds.colors.rule
    }
}
