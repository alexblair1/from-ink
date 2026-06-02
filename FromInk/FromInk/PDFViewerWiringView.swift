import ComposableArchitecture
import SwiftUI

/// Wiring view for `PDFFeature`. Owns the top-bar chrome (title +
/// dismiss) and switches the body across the three load states.
/// Imports TCA — this is the wiring tier per the view layer EDD.
struct PDFViewerWiringView: View {
    @Bindable var store: StoreOf<PDFFeature>

    private let ds = DesignSystem.standard

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Rectangle()
                .fill(ds.colors.rule)
                .frame(height: ds.layout.borderWidth)
            content
        }
        .background(ds.colors.paper)
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear { store.send(.onAppear) }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: ds.spacing.sm) {
            Button { store.send(.dismissTapped) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(ds.colors.inkPure)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.Common.cancel)

            if store.isSearchActive {
                searchFieldGroup
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.title)
                        .font(ds.typography.cardTitle)
                        .foregroundStyle(ds.colors.ink)
                        .lineLimit(1)
                    MonoLabel(
                        pageLabel,
                        size: 10,
                        color: ds.colors.ink2
                    )
                }

                Spacer()

                Button { store.send(.searchToggled) } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(ds.colors.inkPure)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppStrings.Library.searchButton)
            }
        }
        .padding(.horizontal, ds.spacing.base)
        .frame(height: 56)
        .background(ds.colors.paper)
    }

    /// Search field + result counter + step chevrons + close button.
    /// Rendered in place of the title when `isSearchActive`. The field
    /// auto-focuses via `@FocusState`-on-appearance.
    private var searchFieldGroup: some View {
        HStack(spacing: ds.spacing.xs) {
            TextField(
                AppStrings.Library.searchFieldPlaceholder,
                text: Binding(
                    get: { store.searchQuery },
                    set: { store.send(.searchQueryChanged($0)) }
                )
            )
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .foregroundStyle(ds.colors.ink)
            .submitLabel(.search)
            .onSubmit { store.send(.searchSubmitted) }
            .autocorrectionDisabled(true)
            .textInputAutocapitalization(.never)

            MonoLabel(searchCountLabel, size: 10, color: ds.colors.ink2)

            Button { store.send(.stepMatch(.previous)) } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(ds.colors.inkPure)
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.searchResultCount == 0)
            .accessibilityLabel(AppStrings.Library.searchPreviousMatchButton)

            Button { store.send(.stepMatch(.next)) } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(ds.colors.inkPure)
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.searchResultCount == 0)
            .accessibilityLabel(AppStrings.Library.searchNextMatchButton)

            Button { store.send(.searchToggled) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(ds.colors.ink2)
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.Library.searchCloseButton)
        }
    }

    /// "3 / 12" once a query's been submitted with results, "No matches"
    /// once a query's been submitted with none, empty before any
    /// submission. The disambiguator is whether the query is non-empty
    /// AND results have been reported; pre-submit the label hides.
    private var searchCountLabel: String {
        guard !store.searchQuery.isEmpty,
              store.currentMatchIndex > 0 || store.searchResultCount == 0
        else { return "" }
        if store.searchResultCount == 0 {
            return AppStrings.Library.searchNoMatches
        }
        return AppStrings.Library.searchMatchCount(
            current: store.currentMatchIndex,
            total: store.searchResultCount
        )
    }

    /// "<current> / <total> PAGES" mono-label shown under the title.
    private var pageLabel: String {
        let oneIndexed = store.currentPage + 1
        return "\(oneIndexed) / \(store.pageCount) \(AppStrings.Home.pdfPagesLabel)"
    }

    // MARK: - Body

    @ViewBuilder
    private var content: some View {
        switch store.loadState {
        case .loading:
            VStack(spacing: ds.spacing.base) {
                Spacer()
                ProgressView()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded(let data):
            PDFContent(
                data: data,
                annotations: store.annotations,
                currentPage: Binding(
                    get: { store.currentPage },
                    set: { store.send(.pageChanged($0)) }
                ),
                onHighlightExtracted: { lines in
                    store.send(.createHighlightFromSelection(lines))
                },
                onAnnotationDeleteRequested: { id in
                    store.send(.deleteAnnotation(id))
                },
                searchTrigger: store.searchTrigger,
                gotoMatchTrigger: store.gotoMatchTrigger,
                onSearchResults: { count, currentIndex in
                    store.send(.searchResultsLoaded(count: count, currentIndex: currentIndex))
                },
                onCurrentMatchChanged: { index in
                    store.send(.currentMatchChanged(index))
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            VStack(spacing: ds.spacing.base) {
                Spacer()
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(ds.colors.flagRed)
                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(ds.colors.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, ds.spacing.lg)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
