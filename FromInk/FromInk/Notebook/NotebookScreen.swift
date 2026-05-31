import ComposableArchitecture
import SwiftUI

/// Hoisted state for the page brief overlay. Lives at NotebookScreen
/// level so the overlay can render above the toolbar and the close
/// button (siblings of the TabView), covering them visually and
/// blocking interaction while a brief is open.
///
/// The originating CanvasScreen captures its per-page routing path in
/// `onSendAll` so NotebookScreen can present without inheriting the
/// per-page `notebookClient` + `pageID` coupling. `generatedAt` is
/// resolved through `CalendarContext` at the call site — no bare
/// `Date()` reaches the overlay.
struct BriefRequest {
    var isLoading: Bool
    var summary: String
    var tasks: [InkTask]
    var openQuestion: String?
    var generatedAt: Date?
    var onSendAll: ([InkTask]) -> Void
}

/// Active dispatch flow. Holds the originating task (needed to build
/// the `NoteHistoryDraft` after a successful send) alongside the
/// TCA store that backs the universal Dispatch modal and the
/// per-page completion callback. The flow lives at NotebookScreen so
/// the modal renders above the toolbar + close button. The completion
/// callback is captured by the originating CanvasScreen, so per-page
/// state (notebookClient, pageID, dispatch panel sync) stays local
/// to the page even though the rendering is hoisted.
///
/// Per-page lifecycle by design — swiping pages dismisses an
/// in-progress edit.
///
/// **Sendable trap:** `onCompletion` captures the originating
/// CanvasScreen's MainActor-isolated methods. Do not add a
/// `Sendable` conformance to `DispatchFlow` without first reworking
/// the completion delivery (e.g. via a TCA action) — the closure
/// would then need to be `@Sendable`, which the capture isn't.
struct DispatchFlow {
    let task: InkTask
    let store: StoreOf<DispatchFeature>
    let onCompletion: (DispatchFeature.State.Completion) -> Void
}

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
    @State private var briefRequest: BriefRequest? = nil
    @State private var dispatchFlow: DispatchFlow? = nil
    @Environment(\.dismiss) private var dismiss

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
                        },
                        dispatchFlow: $dispatchFlow,
                        briefRequest: $briefRequest
                    )
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            pageNavigatorLayer

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
            // Dismiss button — top corner opposite the toolbar. Honors
            // the safe area so it never tucks under the status bar /
            // camera notch. The 44×44 outer frame wraps the 32×32
            // visual circle to meet the HIG minimum tap-target size
            // without enlarging the chrome.
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
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .padding(.horizontal, 12)
                    if !toolbarIsLeft { Spacer() }
                }
                Spacer()
            }

            // Toolbar — stretched edge-to-edge on the chosen side. Lives
            // at notebook level (sibling of the TabView) so it doesn't
            // translate horizontally with page swipes.
            ToolbarWiringView(
                store: toolbarStore,
                zones: ToolbarZoneConfig.standard()
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

            // Page Brief overlay — rendered LAST in the ZStack so it
            // covers the toolbar and close button visually and blocks
            // their interaction. Slides in from the edge opposite the
            // toolbar, matching the dispatch panel motion language.
            // Animation scoped to this Group so the brief / dispatch
            // overlays don't share one .animation modifier on the ZStack.
            Group {
                if briefRequest != nil {
                    briefOverlay
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.move(edge: toolbarIsLeft ? .trailing : .leading))
                        .ignoresSafeArea()
                }
            }
            .animation(DesignSystem.standard.animation.standard, value: briefRequest != nil)

            // Universal Dispatch modal — also at notebook level so its
            // dim backdrop covers the toolbar + close button. Hosting
            // CanvasScreen captures per-page completion logic in
            // `flow.onCompletion`; we own the lifecycle (clear on
            // completion + page swipe).
            Group {
                if let flow = dispatchFlow {
                    DispatchWiringView(store: flow.store)
                        .transition(.opacity)
                        .onChange(of: flow.store.completion) { _, completion in
                            guard let completion else { return }
                            flow.onCompletion(completion)
                            dispatchFlow = nil
                        }
                }
            }
            .animation(DesignSystem.standard.animation.slow, value: dispatchFlow == nil)
        }
        .task { store.send(.onAppear) }
        .onChange(of: store.currentIndex) { _, _ in
            showAddButton = false
            // Per-page overlays — dismiss on page swipe so a flow from
            // page N doesn't linger over page N+1 with the wrong data.
            briefRequest = nil
            dispatchFlow = nil
        }
    }

    /// Page navigator — opposite side from toolbar, only when more than
    /// one page. Spacer-on-toolbar-side pushes it clear of the 48pt
    /// rail so the prev/next button can't be cropped.
    @ViewBuilder
    private var pageNavigatorLayer: some View {
        if pages.count > 1 {
            VStack {
                Spacer()
                HStack {
                    if toolbarIsLeft { Spacer() }

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
                        },
                        onAddPage: {
                            // Discard explicitly so the closure type
                            // doesn't infer `StoreTask` and conflict
                            // with `withAnimation`'s `Void` expectation.
                            _ = withAnimation { store.send(.addPageTapped) }
                        }
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, showAddButton ? 100 : 24)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showAddButton)

                    if !toolbarIsLeft { Spacer() }
                }
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var briefOverlay: some View {
        BriefSheet(
            isLoading: briefRequest?.isLoading ?? false,
            summary: briefRequest?.summary ?? "",
            tasks: Binding(
                get: { briefRequest?.tasks ?? [] },
                set: { briefRequest?.tasks = $0 }
            ),
            openQuestion: briefRequest?.openQuestion,
            generatedAt: briefRequest?.generatedAt,
            onDismiss: { briefRequest = nil },
            onSendAll: {
                guard let request = briefRequest else { return }
                request.onSendAll(request.tasks)
                briefRequest = nil
            }
        )
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
