import ComposableArchitecture
import SwiftUI

/// Wiring view for a single open notebook. Reads page snapshots from
/// `NotebookFeature`, binds the TabView page index to the reducer, and
/// renders the toolbar plus its panel overlays at this level so they
/// stay pinned during page swipes. Per-page overlays (lasso menu,
/// header/link indicators, dispatch side panel) stay inside `CanvasScreen`.
///
/// The X (close) button uses `@Environment(\.dismiss)` — when SwiftUI
/// tears down the `.fullScreenCover`, the `@Presents` wrapper in
/// `HomeFeature` clears `state.notebook` automatically.
struct NotebookScreen: View {
    @Bindable var store: StoreOf<NotebookFeature>

    @State private var showAddButton = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var toolbarStore: StoreOf<ToolbarFeature> {
        store.scope(state: \.toolbar, action: \.toolbar)
    }

    private var toolbarSide: ToolbarSide { store.toolbar.side }
    private var toolbarIsLeft: Bool { toolbarSide == .left }

    private var pages: [NotePageSnapshot] { store.pages }

    private var currentIndexBinding: Binding<Int> {
        Binding(
            get: { store.currentIndex },
            set: { store.send(.currentIndexChanged($0)) }
        )
    }

    var body: some View {
        ZStack {
            TabView(selection: currentIndexBinding) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { (i, page) in
                    CanvasScreen(
                        notebookID: store.notebookID,
                        pageID: page.id,
                        pageIndex: i,
                        toolbarStore: toolbarStore,
                        activeTemplate: store.activeTemplate,
                        isCurrentPage: i == store.currentIndex,
                        onNearBottom: {
                            if store.currentIndex == i { showAddButton = true }
                        },
                        onAwayFromBottom: {
                            if store.currentIndex == i { showAddButton = false }
                        }
                    )
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            // Page navigator — opposite side from toolbar, only when more than one page
            if pages.count > 1 {
                VStack {
                    Spacer()
                    HStack {
                        if !toolbarIsLeft { Spacer() }

                        PageNavigator(
                            current: store.currentIndex + 1,
                            total: pages.count,
                            onPrevious: {
                                let new = max(0, store.currentIndex - 1)
                                withAnimation { store.send(.currentIndexChanged(new)) }
                            },
                            onNext: {
                                let new = min(pages.count - 1, store.currentIndex + 1)
                                withAnimation { store.send(.currentIndexChanged(new)) }
                            }
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, showAddButton ? 100 : 24)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showAddButton)

                        if toolbarIsLeft { Spacer() }
                    }
                }
                .ignoresSafeArea()
            }

            // Add page button — appears when scrolled near bottom
            if showAddButton {
                VStack {
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            store.send(.addPageTapped)
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
            // Dismiss button — top-right corner, opposite side from toolbar
            VStack {
                HStack {
                    if toolbarIsLeft { Spacer() }
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.inkSecondary)
                            .frame(width: 32, height: 32)
                            .background(Color.surface.opacity(0.85))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)
                    .padding(.horizontal, 16)
                    if !toolbarIsLeft { Spacer() }
                }
                Spacer()
            }
            .ignoresSafeArea()

            // Toolbar — stretched edge-to-edge on the chosen side. Lives
            // at notebook level (sibling of the TabView) so it doesn't
            // translate horizontally with page swipes.
            ToolbarWiringView(
                store: toolbarStore,
                zones: ToolbarZoneConfig.standard(isCompact: sizeClass == .compact)
            )
            .frame(maxHeight: .infinity)
            .frame(
                maxWidth: .infinity,
                alignment: toolbarIsLeft ? .leading : .trailing
            )

            // Toolbar panel overlay — also at notebook level so it stays
            // pinned across page swipes. Tap outside to dismiss.
            if store.toolbar.openPanel != nil {
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toolbarStore.send(.panelDismissed)
                    }
            }

            if let panel = store.toolbar.openPanel {
                toolbarPanel(panel)
            }
        }
        .task { store.send(.onAppear) }
        .onChange(of: store.currentIndex) { _, _ in
            showAddButton = false
        }
    }

    /// Toolbar customization / template / settings panel. Vertically
    /// centered, horizontally offset opposite the toolbar. v1 doesn't
    /// track the active tool button's frame — see toolbar EDD.
    @ViewBuilder
    private func toolbarPanel(_ panel: PanelKind) -> some View {
        let tw = LayoutTokens.standard.toolbarWidth
        let panelGap = LayoutTokens.standard.toolbarPanelGap

        Group {
            switch panel {
            case .toolCustomization(let toolID):
                let tool: CanvasTool = CanvasTool(rawValue: toolID.rawValue) ?? .pen
                PenCustomizationPanel(
                    tool: tool,
                    settings: Binding(
                        get: { store.toolbar.customizingSettings },
                        set: { toolbarStore.send(.toolSettingsChanged(toolID, $0)) }
                    ),
                    onDismiss: { toolbarStore.send(.panelDismissed) }
                )

            case .templatePicker:
                TemplatePickerPanel(
                    template: Binding(
                        get: { store.activeTemplate },
                        set: { store.send(.templateSelected($0)) }
                    ),
                    onDismiss: { toolbarStore.send(.panelDismissed) }
                )

            case .canvasSettings:
                CanvasSettingsPanel(
                    onDismiss: { toolbarStore.send(.panelDismissed) }
                )
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .padding(.leading, toolbarIsLeft ? tw + panelGap : 0)
        .padding(.trailing, toolbarIsLeft ? 0 : tw + panelGap)
        .frame(maxWidth: .infinity, alignment: toolbarIsLeft ? .leading : .trailing)
    }
}
