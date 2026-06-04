import ComposableArchitecture
import SwiftUI

/// Wiring view for the `NotebookPickerFeature`. Converts the store into
/// a fully-resolved `NotebookPickerView.Model` and forwards user-facing
/// taps as TCA actions.
///
/// Lifecycle: the `.appeared` action is sent once on view appear so the
/// notebooks fetch kicks off without the parent having to remember to
/// dispatch it.
///
struct NotebookPickerWiringView: View {
    let store: StoreOf<NotebookPickerFeature>

    var body: some View {
        NotebookPickerView(model: makeModel())
            .onAppear { store.send(.appeared) }
    }

    private func makeModel() -> NotebookPickerView.Model {
        let ds = DesignSystem.standard
        let phaseModel = makePhaseModel(ds: ds)
        let (title, subtitle, onBack) = resolveHeader()

        return NotebookPickerView.Model(
            phase: phaseModel,
            title: title,
            subtitle: subtitle,
            onDismiss: { store.send(.dismissTapped) },
            onBack: onBack,
            onScrimTap: { store.send(.dismissTapped) },
            backAccessibilityLabel: AppStrings.NotebookPicker.backAction,
            dismissAccessibilityLabel: AppStrings.NotebookPicker.dismissAction,
            cardWidth: 360,
            // Cap the modal height so the grid scrolls inside rather
            // than the card growing to fill the screen. 560 leaves room
            // for the keyboard on iPhone in the search-active state.
            cardMaxHeight: 560,
            cardBackground: ds.colors.paper,
            cardBorderColor: ds.colors.ink,
            cardBorderWidth: ds.layout.borderWidth,
            scrimColor: ds.colors.ink.opacity(ds.layout.scrimOpacity),
            headerHeight: ds.spacing.xxl,
            headerHorizontalPadding: ds.spacing.sm,
            headerInnerSpacing: ds.spacing.sm,
            headerActionFrame: ds.layout.dismissHitTarget,
            headerIconSize: ds.layout.dismissIconSize,
            headerIconColor: ds.colors.ink2,
            titleFont: .system(size: 14, weight: .medium, design: .monospaced),
            titleColor: ds.colors.ink2,
            subtitleFont: .system(size: 11, weight: .regular, design: .serif),
            subtitleColor: ds.colors.ink3,
            contentHorizontalPadding: ds.spacing.base,
            contentVerticalPadding: ds.spacing.md,
            searchBarHeight: ds.layout.hitTarget,
            searchInnerSpacing: ds.spacing.sm,
            searchIconSize: ds.layout.searchIconSize,
            searchIconColor: ds.colors.ink3,
            searchFieldFont: .system(size: 14, weight: .regular),
            searchFieldColor: ds.colors.ink,
            emptyStateFont: .system(size: 13, weight: .regular, design: .serif),
            emptyStateColor: ds.colors.ink3
        )
    }

    // MARK: - Header resolution

    private func resolveHeader() -> (title: String, subtitle: String?, onBack: (() -> Void)?) {
        switch store.phase {
        case .notebookSelection:
            return (AppStrings.NotebookPicker.chooseNotebookTitle, nil, nil)
        case .pageSelection(_, let notebookTitle):
            return (
                AppStrings.NotebookPicker.choosePageTitle,
                notebookTitle,
                { store.send(.backTapped) }
            )
        }
    }

    // MARK: - Phase resolution

    private func makePhaseModel(ds: DesignSystem) -> NotebookPickerView.PhaseModel {
        switch store.phase {
        case .notebookSelection:
            return .notebookSelection(makeNotebookSelectionModel(ds: ds))
        case .pageSelection:
            return .pageSelection(makePageSelectionModel(ds: ds))
        }
    }

    private func makeNotebookSelectionModel(
        ds: DesignSystem
    ) -> NotebookPickerView.NotebookSelectionPhaseModel {
        let trimmedQuery = store.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = trimmedQuery.isEmpty
            ? store.notebooks
            : store.notebooks.filter { $0.title.localizedCaseInsensitiveContains(trimmedQuery) }
        let cards = filtered.map { snapshot in
            NotebookPickerNotebookCard.Model(
                snapshot: snapshot,
                pageCountSuffix: AppStrings.NotebookPicker.pageCount(snapshot.pageCount),
                onTap: { store.send(.notebookTapped(snapshot.id)) },
                ds: ds
            )
        }

        let emptyMessage: String? = {
            guard cards.isEmpty else { return nil }
            let trimmed = store.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return AppStrings.NotebookPicker.emptyNoNotebooks
            }
            return AppStrings.NotebookPicker.emptyNoSearchMatches(trimmed)
        }()

        return NotebookPickerView.NotebookSelectionPhaseModel(
            searchText: store.searchText,
            searchPlaceholder: AppStrings.NotebookPicker.searchPlaceholder,
            onSearchChanged: { store.send(.searchTextChanged($0)) },
            notebooks: cards,
            emptyMessage: emptyMessage,
            // Three-column grid sized so 360pt card minus 32pt padding
            // gives ~98pt per column with 14pt gutters — fits the
            // 116pt card width snugly without horizontal scroll.
            gridColumns: Array(
                repeating: GridItem(.flexible(), spacing: ds.spacing.md, alignment: .top),
                count: 2
            ),
            gridSpacing: ds.spacing.lg
        )
    }

    private func makePageSelectionModel(
        ds: DesignSystem
    ) -> NotebookPickerView.PageSelectionPhaseModel {
        let lastEdited = NotebookPickerPresetRow.Model(
            label: AppStrings.NotebookPicker.lastEditedPage,
            iconSystemName: "clock.arrow.circlepath",
            onTap: { store.send(.lastEditedPageTapped) },
            ds: ds
        )
        let newPage = NotebookPickerPresetRow.Model(
            label: AppStrings.NotebookPicker.newPage,
            iconSystemName: "plus.rectangle",
            onTap: { store.send(.newPageTapped) },
            ds: ds
        )
        let specificPage = NotebookPickerPresetRow.Model(
            label: AppStrings.NotebookPicker.morePages,
            iconSystemName: "rectangle.grid.2x2",
            trailingIconSystemName: "chevron.forward",
            // Rotate the chevron 90° down when the grid is expanded so
            // it reads as "open"; matches the iOS DisclosureGroup idiom
            // without dragging in the system control.
            trailingIconRotation: store.showsPageThumbnails ? 90 : 0,
            onTap: { store.send(.morePagesTapped) },
            ds: ds
        )

        let thumbnails: [NotebookPickerPageThumbnailCard.Model] =
            store.pages.enumerated().map { (index, page) in
                let oneBased = index + 1
                let caption = AppStrings.NotebookPicker.pageNumberLabel(oneBased)
                return NotebookPickerPageThumbnailCard.Model(
                    snapshot: page,
                    caption: caption,
                    accessibilityLabel: caption,
                    onTap: { store.send(.pageThumbnailTapped(page.id)) },
                    ds: ds
                )
            }

        return NotebookPickerView.PageSelectionPhaseModel(
            lastEditedRow: lastEdited,
            newPageRow: newPage,
            specificPageRow: specificPage,
            showsThumbnails: store.showsPageThumbnails,
            thumbnails: thumbnails,
            emptyThumbnailsMessage: AppStrings.NotebookPicker.emptyNoNotebooks,
            thumbnailColumns: Array(
                repeating: GridItem(.flexible(), spacing: ds.spacing.md, alignment: .top),
                count: 3
            ),
            thumbnailSpacing: ds.spacing.md
        )
    }
}

