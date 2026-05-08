import SwiftUI

/// The landing screen — an editorial home built on the Native Kit design system.
///
/// Structure (top → bottom):
///   1. Top bar — wordmark centered, new-notebook trailing
///   2. Editorial masthead — large serif date, weather, AI brief, counts
///   3. Folders — horizontal scroll of folder cards
///   4. Notebooks — horizontal scroll of notebook spines
///   5. Footer rule
///
/// This view is stateless. Feed it a `HomeScreen.Model` from a feature view
/// that owns the TCA store. All interactions flow out through closures.
///
struct HomeScreen: View {
    let model: Model

    private let ds = DesignSystem.standard
    @State private var isBriefExpanded = false
    @State private var stickyHeaderHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            ds.colors.paper.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Spacer to push content below the sticky header
                    Color.clear.frame(height: stickyHeaderHeight)

                    // ── Editorial Masthead ──────────────────
                    HomeMasthead(model: model.masthead, isExpanded: $isBriefExpanded)

                    // ── Folders ─────────────────────────────
                    if !model.folders.isEmpty {
                        HomeFoldersSection(
                            folders: model.folders,
                            onFolder: model.onFolder
                        )
                    }

                    // ── Notebooks ───────────────────────────
                    if !model.notebooks.isEmpty {
                        HomeNotebooksSection(
                            notebooks: model.notebooks,
                            onNotebook: model.onNotebook
                        )
                    }

                    // ── Empty state ─────────────────────────
                    if model.folders.isEmpty && model.notebooks.isEmpty {
                        HomeEmptyState(onCreateNotebook: model.onNewNotebook)
                    }

                    Spacer().frame(height: ds.spacing.xxl)
                }
            }

            // ── Sticky header ─────────────────────────
            VStack(spacing: 0) {
                homeTopBar
                    .padding(.horizontal, ds.spacing.lg)

                HomeSearchRow(
                    text: model.searchText,
                    onTextChanged: { query in
                        if !query.isEmpty {
                            isBriefExpanded = false
                        }
                        model.onSearchChanged(query)
                    },
                    placeholder: AppStrings.Home.searchPlaceholder
                )
            }
            .background(ds.colors.paper)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                stickyHeaderHeight = height
            }
        }
    }

    // MARK: - Top bar

    private var homeTopBar: some View {
        HStack {
            Button(action: model.onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(ds.colors.ink)
                    .frame(width: ds.layout.hitTarget, height: ds.layout.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(AppStrings.Home.title)
                .font(.system(size: 18, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(ds.colors.ink)
                .tracking(0.4)

            Spacer()

            Button(action: model.onNewNotebook) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(ds.colors.ink)
                    .frame(width: ds.layout.hitTarget, height: ds.layout.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, ds.spacing.sm)
        .padding(.bottom, ds.spacing.xs)
    }
}

// MARK: - Model

extension HomeScreen {
    struct Model {
        let masthead: HomeMasthead.Model
        let searchText: Binding<String>
        let onSearchChanged: (String) -> Void
        let folders: [FolderItem]
        let notebooks: [NotebookItem]
        let onFolder: (UUID) -> Void
        let onNotebook: (UUID) -> Void
        let onNewNotebook: () -> Void
        let onSettings: () -> Void

        struct FolderItem: Identifiable {
            let id: UUID
            let name: String
            let notebookCount: Int
            let icon: String
        }

        struct NotebookItem: Identifiable {
            let id: UUID
            let title: String
            let subtitle: String
            let coverColor: Color
        }
    }
}

// MARK: - Search Row

private struct HomeSearchRow: View {
    let text: Binding<String>
    let onTextChanged: (String) -> Void
    let placeholder: String

    private let ds = DesignSystem.standard

    var body: some View {
        HStack(spacing: ds.spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(ds.colors.ink2)

            TextField(placeholder, text: text)
                .font(ds.typography.subheadline)
                .foregroundStyle(ds.colors.ink)
                .onChange(of: text.wrappedValue) { _, newValue in
                    onTextChanged(newValue)
                }

            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                    onTextChanged("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .regular))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(ds.colors.ink3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, ds.spacing.md)
        .padding(.vertical, ds.spacing.sm)
        .background(ds.colors.surface)
        .overlay(
            Rectangle().strokeBorder(ds.colors.rule, lineWidth: 0.5)
        )
        .padding(.horizontal, ds.spacing.lg)
        .padding(.vertical, ds.spacing.base)
    }
}
