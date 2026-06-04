import ComposableArchitecture
import SwiftUI

/// Reusable wiring view that maps `StoreOf<LibrarySearchFeature>` into
/// the `LibrarySearchView.Model`. Embed this inside any consumer's
/// chrome — the browse surface, a picker phase, a quick-switcher — and
/// the search machine runs the same way every time.
///
struct LibrarySearchWiringView: View {
    let store: StoreOf<LibrarySearchFeature>

    var body: some View {
        LibrarySearchView(model: makeModel())
            .onAppear { store.send(.appeared) }
    }

    private func makeModel() -> LibrarySearchView.Model {
        let ds = DesignSystem.standard
        let rows = store.results.map { result in
            LibrarySearchResultRow.Model(
                result: result,
                onTap: { store.send(.resultTapped(result.id)) },
                ds: ds
            )
        }

        let emptyMessage: String? = {
            guard rows.isEmpty, store.hasLoadedOnce else { return nil }
            let trimmed = store.query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return AppStrings.LibrarySearch.emptyLibrary
            }
            return AppStrings.LibrarySearch.emptyNoResults(trimmed)
        }()

        return LibrarySearchView.Model(
            query: store.query,
            onQueryChanged: { store.send(.queryChanged($0)) },
            rows: rows,
            emptyMessage: emptyMessage,
            searchPlaceholder: AppStrings.LibrarySearch.searchPlaceholder,
            searchBarHeight: ds.layout.hitTarget,
            searchInnerSpacing: ds.spacing.sm,
            searchIconSize: ds.layout.searchIconSize,
            searchIconColor: ds.colors.ink3,
            searchFieldFont: .system(size: 14, weight: .regular),
            searchFieldColor: ds.colors.ink,
            horizontalPadding: ds.spacing.base,
            emptyStateFont: .system(size: 13, weight: .regular, design: .serif),
            emptyStateColor: ds.colors.ink3
        )
    }
}
