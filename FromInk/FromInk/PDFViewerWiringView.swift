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
        }
        .padding(.horizontal, ds.spacing.base)
        .frame(height: 56)
        .background(ds.colors.paper)
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
