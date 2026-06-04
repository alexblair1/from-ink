import SwiftUI

/// Compact notebook card rendered inside the picker grid. Snapshot-based
/// (vs. the legacy `NotebookCard` which is `@Model`-coupled) so it can
/// live inside TCA `State` without dragging SwiftData through the picker
/// presentation chrome.
///
/// Layout: square-ish card with the spine-illustration on top, title +
/// page-count summary underneath. Sharp corners, hairline ink border,
/// no shadow — matches the rest of the brand language.
///
/// Component view: no TCA imports. The wiring view's adapter resolves a
/// `NotebookSnapshot` into the Model.
///
struct NotebookPickerNotebookCard: View {
    let model: Model

    var body: some View {
        Button(action: model.onTap) {
            VStack(alignment: .leading, spacing: model.spacing) {
                illustration
                Text(model.title)
                    .font(model.titleFont)
                    .foregroundStyle(model.titleColor)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(model.subtitle)
                    .font(model.subtitleFont)
                    .foregroundStyle(model.subtitleColor)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: model.cardWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var illustration: some View {
        ZStack {
            model.illustrationBackground

            HStack(spacing: 0) {
                Rectangle()
                    .fill(model.spineColor)
                    .frame(width: model.spineWidth)
                Rectangle()
                    .fill(model.bodyColor)
            }
            .padding(model.illustrationPadding)
        }
        .frame(width: model.illustrationWidth, height: model.illustrationHeight)
        .overlay(
            Rectangle().strokeBorder(model.borderColor, lineWidth: model.borderWidth)
        )
    }
}

// MARK: - Model

extension NotebookPickerNotebookCard {
    struct Model: Equatable {
        let id: UUID
        let title: String
        let subtitle: String
        let accessibilityLabel: String
        let onTap: () -> Void

        let cardWidth: CGFloat
        let illustrationWidth: CGFloat
        let illustrationHeight: CGFloat
        let illustrationPadding: CGFloat
        let illustrationBackground: Color
        let spineColor: Color
        let bodyColor: Color
        let spineWidth: CGFloat
        let borderColor: Color
        let borderWidth: CGFloat
        let spacing: CGFloat

        let titleFont: Font
        let titleColor: Color
        let subtitleFont: Font
        let subtitleColor: Color

        // Equatable: closures aren't, so we compare the rest. The
        // accessibility label is a function of the inputs so it's
        // covered transitively.
        static func == (lhs: Model, rhs: Model) -> Bool {
            lhs.id == rhs.id
                && lhs.title == rhs.title
                && lhs.subtitle == rhs.subtitle
                && lhs.cardWidth == rhs.cardWidth
                && lhs.illustrationWidth == rhs.illustrationWidth
                && lhs.illustrationHeight == rhs.illustrationHeight
        }
    }
}

// MARK: - Model init

extension NotebookPickerNotebookCard.Model {
    init(
        snapshot: NotebookSnapshot,
        pageCountSuffix: String,
        onTap: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.id = snapshot.id
        self.title = snapshot.title
        // "12 pages" / "1 page" — `pageCountSuffix` is the localized
        // count phrase resolved upstream so this Model stays locale-
        // agnostic (and snapshot-testable without a Locale dependency).
        self.subtitle = pageCountSuffix
        self.accessibilityLabel = "\(snapshot.title), \(pageCountSuffix)"
        self.onTap = onTap

        self.cardWidth = ds.layout.notebookCardWidth
        // Slightly shorter than `notebookCardHeight` because the
        // picker card lays the title + subtitle BELOW the illustration
        // (the library version uses a taller illustration with the
        // title overlaid). 100pt leaves room for two lines of text.
        self.illustrationWidth = ds.layout.notebookCardWidth
        self.illustrationHeight = 100
        self.illustrationPadding = ds.spacing.sm
        self.illustrationBackground = ds.colors.paper
        self.spineColor = ds.colors.ink
        self.bodyColor = ds.colors.paper
        self.spineWidth = ds.layout.notebookSpineWidth
        self.borderColor = ds.colors.rule
        self.borderWidth = ds.layout.borderWidth
        self.spacing = ds.spacing.xs

        self.titleFont = .system(size: 13, weight: .medium)
        self.titleColor = ds.colors.ink
        self.subtitleFont = .system(size: 10, weight: .regular, design: .monospaced)
        self.subtitleColor = ds.colors.ink3
    }
}
