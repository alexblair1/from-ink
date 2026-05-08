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

    var body: some View {
        ZStack(alignment: .top) {
            Color("ink/Paper").ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // ── Editorial Masthead ──────────────────
                    HomeMasthead(model: model.masthead)

                    // ── Search ──────────────────────────────
                    HomeSearchRow(
                        text: model.searchText,
                        onTextChanged: model.onSearchChanged,
                        placeholder: "Search folders, notebooks and pages"
                    )

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

                    Spacer().frame(height: 48)
                }
            }
        }
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

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color("ink/Ink2"))

            TextField(placeholder, text: text)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color("ink/Ink"))
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
                        .foregroundStyle(Color("ink/Ink3"))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color("ink/Surface"))
        .overlay(
            Rectangle().strokeBorder(Color("ink/Rule"), lineWidth: 0.5)
        )
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}
