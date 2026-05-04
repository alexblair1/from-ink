import SwiftUI

struct NotebookScreen: View {
    @State private var pages: [NotebookPage] = [NotebookPage()]
    @State private var currentIndex = 0
    @State private var showAddButton = false

    var body: some View {
        ZStack {
            TabView(selection: $currentIndex) {
                ForEach(pages.indices, id: \.self) { i in
                    CanvasScreen(
                        onNearBottom: {
                            if currentIndex == i { showAddButton = true }
                        },
                        onAwayFromBottom: {
                            if currentIndex == i { showAddButton = false }
                        }
                    )
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            // Page indicator — only when more than one page exists
            if pages.count > 1 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("\(currentIndex + 1) / \(pages.count)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.trailing, 20)
                            .padding(.bottom, showAddButton ? 100 : 24)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showAddButton)
                    }
                }
                .ignoresSafeArea()
            }

            // Add page button — appears when scrolled near bottom
            if showAddButton {
                VStack {
                    Spacer()
                    Button {
                        let newPage = NotebookPage()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            pages.append(newPage)
                            currentIndex = pages.count - 1
                            showAddButton = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                            Text("New Page")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
                    }
                    .padding(.bottom, 36)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
                .ignoresSafeArea()
            }
        }
        .onChange(of: currentIndex) { _, _ in
            showAddButton = false
        }
    }
}

#Preview {
    NotebookScreen()
}
