import ComposableArchitecture
import SwiftUI

/// Wiring view for `PDFFeature`. Owns the top-bar chrome (title +
/// dismiss) and switches the body across the three load states.
/// Imports TCA — this is the wiring tier per the view layer EDD.
struct PDFViewerWiringView: View {
    @Bindable var store: StoreOf<PDFFeature>

    private let ds = DesignSystem.standard

    /// Focuses the search field as soon as the search affordance
    /// opens. Without this, tapping the magnifying glass swaps the
    /// title for the field but leaves the keyboard down — user has
    /// to tap the field too. Bound to `store.search.isActive` so the
    /// reducer transition drives focus.
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Rectangle()
                .fill(ds.colors.rule)
                .frame(height: ds.layout.borderWidth)
            content
            if store.isDrawingActive {
                Rectangle()
                    .fill(ds.colors.rule)
                    .frame(height: ds.layout.borderWidth)
                drawingToolbar
            }
        }
        .background(ds.colors.paper)
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear { store.send(.onAppear) }
        .onChange(of: store.search.isActive) { _, isActive in
            searchFocused = isActive
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: ds.spacing.sm) {
            if store.isDrawingActive {
                drawingTopBar
            } else if store.search.isActive {
                Button { store.send(.dismissTapped) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(ds.colors.inkPure)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppStrings.Common.cancel)

                searchFieldGroup
            } else {
                Button { store.send(.dismissTapped) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(ds.colors.inkPure)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppStrings.Common.cancel)

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

                Button { store.send(.drawingModeEntered) } label: {
                    Image(systemName: "pencil.tip.crop.circle")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(ds.colors.inkPure)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppStrings.Library.drawingEnterButton)

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

    /// Top-bar chrome during drawing mode — Cancel on the left,
    /// Done on the right. The dismiss-the-viewer X is hidden so the
    /// user can't accidentally close the modal mid-draw.
    private var drawingTopBar: some View {
        HStack(spacing: ds.spacing.sm) {
            Button { store.send(.drawingCancelTapped) } label: {
                Text(AppStrings.Library.drawingCancelButton)
                    .font(ds.typography.cardTitle)
                    .foregroundStyle(ds.colors.ink2)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            MonoLabel(pageLabel, size: 10, color: ds.colors.ink2)

            Spacer()

            Button { store.send(.drawingDoneTapped) } label: {
                Text(AppStrings.Library.drawingDoneButton)
                    .font(ds.typography.cardTitle)
                    .foregroundStyle(ds.colors.inkPure)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Bottom toolbar shown while drawing mode is active. Pen + eraser
    /// only for Phase 5b; 5c adds pencil, highlighter, color, width.
    private var drawingToolbar: some View {
        HStack(spacing: ds.spacing.base) {
            Spacer()
            drawingToolButton(
                tool: .pen,
                systemName: "pencil.tip",
                label: AppStrings.Library.drawingToolPen
            )
            drawingToolButton(
                tool: .eraser,
                systemName: "eraser",
                label: AppStrings.Library.drawingToolEraser
            )
            Spacer()
        }
        .padding(.horizontal, ds.spacing.base)
        .frame(height: 56)
        .background(ds.colors.paper)
    }

    @ViewBuilder
    private func drawingToolButton(
        tool: PDFDrawingTool,
        systemName: String,
        label: String
    ) -> some View {
        let isActive = store.drawingTool == tool
        Button { store.send(.drawingToolChanged(tool)) } label: {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(isActive ? ds.colors.paperOnInk : ds.colors.ink)
                .frame(width: 44, height: 44)
                .background(isActive ? ds.colors.ink : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Search field + result counter + step chevrons + close button.
    /// Rendered in place of the title when `search.isActive`. Field
    /// focus is driven by `@FocusState` synced to `search.isActive`
    /// via the wiring view's `.onChange(of:)` modifier.
    private var searchFieldGroup: some View {
        HStack(spacing: ds.spacing.xs) {
            TextField(
                AppStrings.Library.searchFieldPlaceholder,
                text: Binding(
                    get: { store.search.query },
                    set: { store.send(.searchQueryChanged($0)) }
                )
            )
            .focused($searchFocused)
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .foregroundStyle(ds.colors.ink)
            .submitLabel(.search)
            .onSubmit { store.send(.searchSubmitted) }
            .autocorrectionDisabled(true)
            .textInputAutocapitalization(.never)

            if !searchCountLabel.isEmpty {
                MonoLabel(searchCountLabel, size: 10, color: ds.colors.ink2)
            }

            Button { store.send(.stepMatch(.previous)) } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(ds.colors.inkPure)
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.search.resultCount == 0)
            .accessibilityLabel(AppStrings.Library.searchPreviousMatchButton)

            Button { store.send(.stepMatch(.next)) } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(ds.colors.inkPure)
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(store.search.resultCount == 0)
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

    /// Counter label driven by the substate's `Status`. Empty while
    /// the user is still typing the first query (avoids a stale "0/0"
    /// flash); "No matches" or "3 / 12" once results have been
    /// reported.
    private var searchCountLabel: String {
        guard store.search.hasReportedResults else { return "" }
        if store.search.resultCount == 0 {
            return AppStrings.Library.searchNoMatches
        }
        return AppStrings.Library.searchMatchCount(
            current: store.search.currentMatchIndex,
            total: store.search.resultCount
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
                isSearchActive: store.search.isActive,
                searchTrigger: store.search.searchTrigger,
                gotoMatchTrigger: store.search.gotoMatchTrigger,
                onSearchResults: { count, currentIndex in
                    store.send(.searchResultsLoaded(count: count, currentIndex: currentIndex))
                },
                onCurrentMatchChanged: { index in
                    store.send(.currentMatchChanged(index))
                },
                isDrawingActive: store.isDrawingActive,
                drawingTool: store.drawingTool,
                drawingCommitTrigger: store.drawingCommitTrigger,
                onDrawingCommitted: { bytes, bounds, pageIndex in
                    store.send(.drawingCommitted(bytes: bytes, bounds: bounds, pageIndex: pageIndex))
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
