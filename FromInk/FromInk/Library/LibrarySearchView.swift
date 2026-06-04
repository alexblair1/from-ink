import SwiftUI

/// Reusable presentation for `LibrarySearchFeature`. Search field + a
/// scrollable list of `LibrarySearchResultRow`s. No chrome (title bar,
/// dismiss button) — wrappers like `LibraryBrowseView` add that;
/// future picker / quick-switcher uses add different chrome. The view
/// stays a thin presentation surface.
///
/// Feature view: zero TCA imports. The `Model` is built by a wiring
/// view from `StoreOf<LibrarySearchFeature>`.
///
struct LibrarySearchView: View {
    let model: Model

    var body: some View {
        VStack(spacing: 0) {
            searchField
            HairlineRule()
            content
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: model.searchInnerSpacing) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: model.searchIconSize, weight: .regular))
                .foregroundStyle(model.searchIconColor)
            TextField(
                model.searchPlaceholder,
                text: Binding(
                    get: { model.query },
                    set: model.onQueryChanged
                )
            )
            .textFieldStyle(.plain)
            .font(model.searchFieldFont)
            .foregroundStyle(model.searchFieldColor)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, model.horizontalPadding)
        .frame(height: model.searchBarHeight)
    }

    // MARK: - Content (results list OR empty state)

    @ViewBuilder
    private var content: some View {
        if let empty = model.emptyMessage {
            emptyState(empty)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.rows) { row in
                        LibrarySearchResultRow(model: row)
                        HairlineRule()
                    }
                }
            }
        }
    }

    private func emptyState(_ message: String) -> some View {
        VStack(spacing: 0) {
            Spacer()
            Text(message)
                .font(model.emptyStateFont)
                .foregroundStyle(model.emptyStateColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, model.horizontalPadding)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Model

extension LibrarySearchView {
    struct Model: Equatable {
        let query: String
        let onQueryChanged: (String) -> Void
        let rows: [LibrarySearchResultRow.Model]
        /// Non-nil when the rows list would be empty. Wrappers resolve
        /// the right copy (no-results-for-query vs. empty-library).
        let emptyMessage: String?

        let searchPlaceholder: String
        let searchBarHeight: CGFloat
        let searchInnerSpacing: CGFloat
        let searchIconSize: CGFloat
        let searchIconColor: Color
        let searchFieldFont: Font
        let searchFieldColor: Color

        let horizontalPadding: CGFloat
        let emptyStateFont: Font
        let emptyStateColor: Color

        static func == (lhs: Model, rhs: Model) -> Bool {
            lhs.query == rhs.query
                && lhs.rows == rhs.rows
                && lhs.emptyMessage == rhs.emptyMessage
        }
    }
}
