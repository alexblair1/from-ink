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
                    VStack(spacing: 0) {
                        // Daily Brief
                        DailyBriefCard(store: briefStore)

                        // Search bar
                        searchBar
                            .padding(.top, 16)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)

                        if folders.isEmpty && rootNotebooks.isEmpty {
                            emptyState
                        } else {
                            // Folders section
                            if !folders.isEmpty {
                                sectionHeader("Folders")
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 8)

                                VStack(spacing: 1) {
                                    ForEach(folders) { folder in
                                        FolderCard(
                                            folder: folder,
                                            notebookCount: notebooks.filter { $0.folderID == folder.id }.count,
                                            onTap: {}
                                        )
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.bottom, 24)
                            }

                            // Notebooks section
                            if !rootNotebooks.isEmpty {
                                sectionHeader("Notebooks")
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 8)

                                LazyVGrid(
                                    columns: [
                                        GridItem(.flexible(), spacing: 32),
                                        GridItem(.flexible(), spacing: 32)
                                    ],
                                    spacing: 32
                                ) {
                                    ForEach(rootNotebooks) { notebook in
                                        NotebookCard(notebook: notebook) {
                                            notebook.lastOpenedAt = Date()
                                            try? modelContext.save()
                                            activeNotebook = notebook
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.bottom, 32)
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
            // Create a default notebook on first launch
            if notebooks.isEmpty {
                let notebook = Notebook(title: "My Notebook")
                modelContext.insert(notebook)
                try? modelContext.save()
            }
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

    // MARK: - Section header

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.inkSecondary)
                .textCase(.uppercase)
                .kerning(0.5)
            Spacer()
        }
    }
}

#Preview {
    LibraryScreen()
        .modelContainer(for: [Notebook.self, Folder.self, RoutedItem.self])
}
