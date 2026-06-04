import SwiftUI

/// Branded overlay picker — scrim + centered card. Two phases driven by
/// `Model.phase`:
///
///   - **Notebook selection** — search field above a lazy grid of
///     `NotebookPickerNotebookCard`s.
///   - **Page selection** — three preset rows; the "Specific page" row
///     expands a thumbnail grid below itself when tapped.
///
/// Feature view: zero TCA imports. `NotebookPickerWiringView` builds
/// the `Model` from a `StoreOf<NotebookPickerFeature>`.
///
/// The header always shows the X (dismiss). The back arrow is rendered
/// only when `model.onBack != nil`, which the adapter sets exclusively
/// in the page-selection phase.
///
struct NotebookPickerView: View {
    let model: Model

    var body: some View {
        ZStack {
            // Scrim — tap to dismiss. Tap target spans the safe area
            // edge-to-edge so a tap anywhere outside the card closes.
            model.scrimColor
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: model.onScrimTap)
                .accessibilityHidden(true)

            // Card
            VStack(spacing: 0) {
                header
                HairlineRule()
                content
            }
            .frame(width: model.cardWidth)
            .frame(maxHeight: model.cardMaxHeight)
            .background(model.cardBackground)
            .overlay(
                Rectangle().strokeBorder(model.cardBorderColor, lineWidth: model.cardBorderWidth)
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: model.headerInnerSpacing) {
            if let onBack = model.onBack {
                Button(action: onBack) {
                    Image(systemName: "arrow.backward")
                        .font(.system(size: model.headerIconSize, weight: .regular))
                        .foregroundStyle(model.headerIconColor)
                        .frame(
                            width: model.headerActionFrame,
                            height: model.headerActionFrame
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.backAccessibilityLabel)
            } else {
                // Reserve the same hit-target width so the title stays
                // centered between back-affordance ON/OFF.
                Color.clear
                    .frame(width: model.headerActionFrame, height: model.headerActionFrame)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .center, spacing: 2) {
                Text(model.title)
                    .font(model.titleFont)
                    .foregroundStyle(model.titleColor)
                if let subtitle = model.subtitle {
                    Text(subtitle)
                        .font(model.subtitleFont)
                        .foregroundStyle(model.subtitleColor)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)

            Button(action: model.onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: model.headerIconSize, weight: .regular))
                    .foregroundStyle(model.headerIconColor)
                    .frame(
                        width: model.headerActionFrame,
                        height: model.headerActionFrame
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.dismissAccessibilityLabel)
        }
        .padding(.horizontal, model.headerHorizontalPadding)
        .frame(height: model.headerHeight)
    }

    // MARK: - Content (phase-driven)

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .notebookSelection(let phaseModel):
            notebookSelection(phaseModel)
        case .pageSelection(let phaseModel):
            pageSelection(phaseModel)
        }
    }

    @ViewBuilder
    private func notebookSelection(_ phase: NotebookSelectionPhaseModel) -> some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: model.searchInnerSpacing) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: model.searchIconSize, weight: .regular))
                    .foregroundStyle(model.searchIconColor)
                TextField(
                    phase.searchPlaceholder,
                    text: Binding(
                        get: { phase.searchText },
                        set: phase.onSearchChanged
                    )
                )
                .textFieldStyle(.plain)
                .font(model.searchFieldFont)
                .foregroundStyle(model.searchFieldColor)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, model.contentHorizontalPadding)
            .frame(height: model.searchBarHeight)

            HairlineRule()

            // Grid (or empty state)
            if let emptyMessage = phase.emptyMessage {
                emptyState(emptyMessage)
            } else {
                ScrollView {
                    LazyVGrid(columns: phase.gridColumns, spacing: phase.gridSpacing) {
                        ForEach(phase.notebooks, id: \.id) { card in
                            NotebookPickerNotebookCard(model: card)
                        }
                    }
                    .padding(.horizontal, model.contentHorizontalPadding)
                    .padding(.vertical, model.contentVerticalPadding)
                }
            }
        }
    }

    @ViewBuilder
    private func pageSelection(_ phase: PageSelectionPhaseModel) -> some View {
        VStack(spacing: 0) {
            NotebookPickerPresetRow(model: phase.lastEditedRow)
            HairlineRule()
            NotebookPickerPresetRow(model: phase.newPageRow)
            HairlineRule()
            NotebookPickerPresetRow(model: phase.specificPageRow)

            if phase.showsThumbnails {
                HairlineRule()
                if phase.thumbnails.isEmpty {
                    emptyState(phase.emptyThumbnailsMessage)
                } else {
                    ScrollView {
                        LazyVGrid(columns: phase.thumbnailColumns, spacing: phase.thumbnailSpacing) {
                            ForEach(phase.thumbnails, id: \.id) { card in
                                NotebookPickerPageThumbnailCard(model: card)
                            }
                        }
                        .padding(.horizontal, model.contentHorizontalPadding)
                        .padding(.vertical, model.contentVerticalPadding)
                    }
                }
            }
        }
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(model.emptyStateFont)
            .foregroundStyle(model.emptyStateColor)
            .multilineTextAlignment(.center)
            .padding(.horizontal, model.contentHorizontalPadding)
            .padding(.vertical, model.contentVerticalPadding * 2)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Model

extension NotebookPickerView {
    /// Phase-specific model the adapter resolves from the store. Each
    /// case carries everything that phase's content view needs.
    enum PhaseModel: Equatable {
        case notebookSelection(NotebookSelectionPhaseModel)
        case pageSelection(PageSelectionPhaseModel)
    }

    struct Model: Equatable {
        let phase: PhaseModel
        let title: String
        /// Optional second line — e.g., the notebook title in the
        /// page-selection phase.
        let subtitle: String?
        let onDismiss: () -> Void
        /// Non-nil only when the back affordance should render. The
        /// adapter wires this to `.backTapped` in `.pageSelection`.
        let onBack: (() -> Void)?
        /// Tap outside the card. Adapter wires this to the same action
        /// as dismiss in V1.
        let onScrimTap: () -> Void

        let backAccessibilityLabel: String
        let dismissAccessibilityLabel: String

        let cardWidth: CGFloat
        let cardMaxHeight: CGFloat
        let cardBackground: Color
        let cardBorderColor: Color
        let cardBorderWidth: CGFloat
        let scrimColor: Color

        let headerHeight: CGFloat
        let headerHorizontalPadding: CGFloat
        let headerInnerSpacing: CGFloat
        let headerActionFrame: CGFloat
        let headerIconSize: CGFloat
        let headerIconColor: Color
        let titleFont: Font
        let titleColor: Color
        let subtitleFont: Font
        let subtitleColor: Color

        let contentHorizontalPadding: CGFloat
        let contentVerticalPadding: CGFloat

        let searchBarHeight: CGFloat
        let searchInnerSpacing: CGFloat
        let searchIconSize: CGFloat
        let searchIconColor: Color
        let searchFieldFont: Font
        let searchFieldColor: Color

        let emptyStateFont: Font
        let emptyStateColor: Color

        static func == (lhs: Model, rhs: Model) -> Bool {
            lhs.phase == rhs.phase
                && lhs.title == rhs.title
                && lhs.subtitle == rhs.subtitle
                && lhs.cardWidth == rhs.cardWidth
                && lhs.cardMaxHeight == rhs.cardMaxHeight
        }
    }

    struct NotebookSelectionPhaseModel: Equatable {
        let searchText: String
        let searchPlaceholder: String
        let onSearchChanged: (String) -> Void
        let notebooks: [NotebookPickerNotebookCard.Model]
        /// Non-nil when the grid would be empty. Resolved by the
        /// adapter (no-notebooks vs. no-search-matches copy).
        let emptyMessage: String?
        let gridColumns: [GridItem]
        let gridSpacing: CGFloat

        static func == (lhs: NotebookSelectionPhaseModel, rhs: NotebookSelectionPhaseModel) -> Bool {
            lhs.searchText == rhs.searchText
                && lhs.searchPlaceholder == rhs.searchPlaceholder
                && lhs.notebooks == rhs.notebooks
                && lhs.emptyMessage == rhs.emptyMessage
                && lhs.gridSpacing == rhs.gridSpacing
        }
    }

    struct PageSelectionPhaseModel: Equatable {
        let lastEditedRow: NotebookPickerPresetRow.Model
        let newPageRow: NotebookPickerPresetRow.Model
        let specificPageRow: NotebookPickerPresetRow.Model
        let showsThumbnails: Bool
        let thumbnails: [NotebookPickerPageThumbnailCard.Model]
        let emptyThumbnailsMessage: String
        let thumbnailColumns: [GridItem]
        let thumbnailSpacing: CGFloat

        static func == (lhs: PageSelectionPhaseModel, rhs: PageSelectionPhaseModel) -> Bool {
            lhs.lastEditedRow == rhs.lastEditedRow
                && lhs.newPageRow == rhs.newPageRow
                && lhs.specificPageRow == rhs.specificPageRow
                && lhs.showsThumbnails == rhs.showsThumbnails
                && lhs.thumbnails == rhs.thumbnails
                && lhs.thumbnailSpacing == rhs.thumbnailSpacing
        }
    }
}
