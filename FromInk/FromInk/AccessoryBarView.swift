import SwiftUI

/// The keyboard accessory bar for iPhone / iPad-compact (EDD §14.4.1) —
/// the single-row formatting surface above the soft keyboard. Component
/// view: no TCA, flat Model resolved by the wiring view; each button
/// fires an `onTap` the wiring maps to an `EditorCommand` or a textView
/// action (undo / dismiss).
///
/// **Default mode (this slice).** Aa (opens the format popover), the
/// B/I/U inline toggles, bulleted + numbered list, undo, and dismiss.
/// The selection / highlight / insert modes (EDD §14.4.1) and their
/// deferred subsystems land later; the bar is a flat list of buttons so
/// adding a mode is a Model change, not a view change.
///
/// **Chrome.** A thin opaque bar (paper background, 1pt top rule) — no
/// capsule, it spans the keyboard width. Active toggles fill with ink;
/// the leading "Aa" is a text button, the rest are SF Symbols.
struct AccessoryBarView: View {
    let model: Model

    var body: some View {
        HStack(spacing: model.buttonSpacing) {
            ForEach(model.buttons) { button in
                buttonView(button)
            }
            Spacer(minLength: 0)
            ForEach(model.trailingButtons) { button in
                buttonView(button)
            }
        }
        .padding(.horizontal, model.horizontalPadding)
        .frame(height: model.height)
        .frame(maxWidth: .infinity)
        .background(model.paper)
        .overlay(alignment: .top) {
            Rectangle().fill(model.ruleColor).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func buttonView(_ button: Button) -> some View {
        SwiftUI.Button(action: button.onTap) {
            label(button)
                .frame(minWidth: model.buttonMinWidth, minHeight: model.buttonMinHeight)
                .background(
                    RoundedRectangle(cornerRadius: model.buttonCornerRadius, style: .continuous)
                        .fill(button.isActive ? model.ink : Color.clear)
                )
                .foregroundStyle(foreground(button))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(button.isComingSoon)
        .opacity(button.isComingSoon ? model.comingSoonOpacity : 1)
        .accessibilityLabel(button.accessibilityLabel)
        .accessibilityAddTraits(button.isActive ? [.isSelected] : [])
    }

    @ViewBuilder
    private func label(_ button: Button) -> some View {
        switch button.content {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: model.iconSize, weight: .regular))
                .padding(.horizontal, model.buttonHorizontalPadding)
        case .text(let text):
            Text(text)
                .font(model.textButtonFont)
                .padding(.horizontal, model.textButtonHorizontalPadding)
        }
    }

    private func foreground(_ button: Button) -> Color {
        if button.isComingSoon { return model.ink3 }
        return button.isActive ? model.paperOnInk : model.ink
    }
}

// MARK: - Model

extension AccessoryBarView {
    struct Button: Identifiable, Equatable {
        enum Content: Equatable {
            case symbol(String)
            case text(String)
        }
        let id: String
        let content: Content
        let accessibilityLabel: String
        let isActive: Bool
        let isComingSoon: Bool
        let onTap: () -> Void

        init(
            id: String,
            content: Content,
            accessibilityLabel: String,
            isActive: Bool = false,
            isComingSoon: Bool = false,
            onTap: @escaping () -> Void
        ) {
            self.id = id
            self.content = content
            self.accessibilityLabel = accessibilityLabel
            self.isActive = isActive
            self.isComingSoon = isComingSoon
            self.onTap = onTap
        }

        static func == (lhs: Button, rhs: Button) -> Bool {
            lhs.id == rhs.id && lhs.content == rhs.content
                && lhs.accessibilityLabel == rhs.accessibilityLabel
                && lhs.isActive == rhs.isActive && lhs.isComingSoon == rhs.isComingSoon
        }
    }

    struct Model {
        /// Leading-aligned buttons (Aa, formats, lists, …).
        let buttons: [Button]
        /// Trailing-aligned buttons (undo, dismiss).
        let trailingButtons: [Button]

        let height: CGFloat
        let horizontalPadding: CGFloat
        let buttonSpacing: CGFloat
        let buttonMinWidth: CGFloat
        let buttonMinHeight: CGFloat
        let buttonHorizontalPadding: CGFloat
        let textButtonHorizontalPadding: CGFloat
        let buttonCornerRadius: CGFloat
        let iconSize: CGFloat
        let comingSoonOpacity: CGFloat

        let paper: Color
        let ink: Color
        let ink3: Color
        let paperOnInk: Color
        let ruleColor: Color
        let textButtonFont: Font
    }
}

extension AccessoryBarView.Model {
    init(
        buttons: [AccessoryBarView.Button],
        trailingButtons: [AccessoryBarView.Button],
        ds: DesignSystem = .standard
    ) {
        self.buttons = buttons
        self.trailingButtons = trailingButtons

        self.height = 48
        self.horizontalPadding = ds.spacing.sm
        self.buttonSpacing = ds.spacing.xxs
        self.buttonMinWidth = 36
        self.buttonMinHeight = 36
        self.buttonHorizontalPadding = ds.spacing.xs
        self.textButtonHorizontalPadding = ds.spacing.sm
        self.buttonCornerRadius = ds.cornerRadius.chip
        self.iconSize = 17
        self.comingSoonOpacity = 0.5

        self.paper = ds.colors.paper
        self.ink = ds.colors.ink
        self.ink3 = ds.colors.ink3
        self.paperOnInk = ds.colors.paperOnInk
        self.ruleColor = ds.colors.rule
        self.textButtonFont = .system(size: 17, weight: .medium, design: .serif)
    }
}
