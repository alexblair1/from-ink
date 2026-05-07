import SwiftUI
import SwiftData
import ComposableArchitecture

struct LibraryScreen: View {
    @Query(sort: \Notebook.lastOpenedAt, order: .reverse) private var notebooks: [Notebook]
    @Query(sort: \Folder.sortOrder) private var folders: [Folder]
    @Environment(\.modelContext) private var modelContext

    @State private var briefStore = Store(initialState: DailyBriefFeature.State()) {
        DailyBriefFeature()
    }
    @State private var searchText = ""
    @State private var activeNotebook: Notebook? = nil
    @State private var showNewNotebookSheet = false
    @State private var newNotebookTitle = ""

    private var filteredNotebooks: [Notebook] {
        guard !searchText.isEmpty else { return notebooks }
        return notebooks.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private var rootNotebooks: [Notebook] {
        filteredNotebooks.filter { $0.folderID == nil }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.canvas.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {

                        // Stats row
                        statsRow
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)

                        Rectangle().fill(Color.border).frame(height: 1)

                        // Daily brief compact strip
                        DailyBriefCard(store: briefStore)

                        // Search
                        searchBar
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)

                        Rectangle().fill(Color.border).frame(height: 1)

                        if folders.isEmpty && rootNotebooks.isEmpty {
                            emptyState
                        } else {
                            // Folders section
                            if !folders.isEmpty {
                                sectionHeader("Folders", count: folders.count)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 20)
                                    .padding(.bottom, 10)

                                Rectangle().fill(Color.border).frame(height: 1)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 1) {
                                        ForEach(folders) { folder in
                                            FolderCard(
                                                folder: folder,
                                                notebookCount: notebooks.filter { $0.folderID == folder.id }.count,
                                                onTap: {}
                                            )
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 16)
                                }

                                Rectangle().fill(Color.border).frame(height: 1)
                            }

                            // Notebooks section
                            if !rootNotebooks.isEmpty {
                                sectionHeader("Notebooks", count: rootNotebooks.count)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 20)
                                    .padding(.bottom, 10)

                                Rectangle().fill(Color.border).frame(height: 1)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(alignment: .top, spacing: 20) {
                                        ForEach(rootNotebooks) { notebook in
                                            NotebookCard(notebook: notebook) {
                                                notebook.lastOpenedAt = Date()
                                                try? modelContext.save()
                                                activeNotebook = notebook
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 16)
                                }
                            }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .fullScreenCover(item: $activeNotebook) { notebook in
                NotebookScreen(notebookID: notebook.id, notebookTitle: notebook.title)
            }
            .sheet(isPresented: $showNewNotebookSheet) {
                newNotebookSheet
            }
        }
        .onAppear {
            if notebooks.isEmpty {
                let notebook = Notebook(title: "My Notebook")
                modelContext.insert(notebook)
                try? modelContext.save()
            }
        }
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: 6) {
            if !folders.isEmpty {
                Text("\(folders.count) FOLDERS")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.inkSecondary)
                    .kerning(0.5)
                Text("·")
                    .foregroundStyle(Color.border)
            }
            Text("\(notebooks.count) NOTEBOOK\(notebooks.count == 1 ? "" : "S")")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.inkSecondary)
                .kerning(0.5)
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Color.inkSecondary)

            TextField("Search notebooks", text: $searchText)
                .font(.system(size: 14))
                .foregroundStyle(Color.ink)

            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.inkSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.surface)
        .overlay {
            Rectangle().strokeBorder(Color.border, lineWidth: 1)
        }
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.inkSecondary)
                .kerning(0.5)
            Text("·")
                .foregroundStyle(Color.border)
            Text("\(count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.inkSecondary)
            Spacer()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Text("From Ink")
                .font(.canvasTitle)
                .foregroundStyle(Color.ink)
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                newNotebookTitle = ""
                showNewNotebookSheet = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.ink)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - New notebook sheet

    private var newNotebookSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Notebook")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.ink)
                Spacer()
                Button("Cancel") {
                    showNewNotebookSheet = false
                }
                .font(.system(size: 14))
                .foregroundStyle(Color.inkSecondary)
                .buttonStyle(.plain)
            }
            .padding(20)

            Rectangle().fill(Color.border).frame(height: 1)

            TextField("Title", text: $newNotebookTitle)
                .font(.system(size: 14))
                .foregroundStyle(Color.ink)
                .padding(20)

            Rectangle().fill(Color.border).frame(height: 1)

            Button {
                let notebook = Notebook(title: newNotebookTitle.isEmpty ? "Untitled" : newNotebookTitle)
                modelContext.insert(notebook)
                try? modelContext.save()
                showNewNotebookSheet = false
                activeNotebook = notebook
            } label: {
                Text("Create & Open")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.inkOnDark)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.ink)
            }
            .buttonStyle(.plain)
            .padding(20)

            Spacer()
        }
        .background(Color.surface)
        .presentationDetents([.height(240)])
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.system(size: 32))
                .foregroundStyle(Color.inkSecondary.opacity(0.4))
            Text("No notebooks yet")
                .font(.system(size: 14))
                .foregroundStyle(Color.inkSecondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

#Preview {
    LibraryScreen()
        .modelContainer(for: [Notebook.self, Folder.self, RoutedItem.self])
}
