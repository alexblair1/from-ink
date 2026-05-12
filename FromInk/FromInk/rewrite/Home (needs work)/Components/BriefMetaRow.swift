import SwiftUI

/// "DAILY BRIEF · SYNCED JUST NOW" left, "TUE · 05.12.26" right.
/// Component view — no TCA imports.
///
struct BriefMetaRow: View {
    let model: Model

    var body: some View {
        HStack {
            MonoLabel(model.leadingText, color: model.leadingColor)
            Spacer()
            MonoLabel(model.trailingText, color: model.trailingColor)
        }
        .padding(.horizontal, model.horizontalPadding)
    }
}

// MARK: - Model

extension BriefMetaRow {
    struct Model {
        let leadingText: String
        let trailingText: String
        let leadingColor: Color
        let trailingColor: Color
        let horizontalPadding: CGFloat
    }
}

// MARK: - Model init

extension BriefMetaRow.Model {
    init(
        syncLabel: String,
        shortDate: String,
        ds: DesignSystem = .standard
    ) {
        self.leadingText = "\(AppStrings.Home.dailyBrief) · \(syncLabel)"
        self.trailingText = shortDate
        self.leadingColor = ds.colors.ink3
        self.trailingColor = ds.colors.ink3
        self.horizontalPadding = ds.spacing.lg
    }
}
