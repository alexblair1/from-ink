import ComposableArchitecture
import SwiftUI

/// Wiring view for the textNote notebook variant.
///
/// Renders a single `TextBlockView` bound to the active text block of
/// the current page, scoped under `NotebookFeature.textEditing`. The
/// canvas toolbar + Pencil chrome are hidden — text notes have no ink
/// authoring path. The keyboard accessory + slash menu chrome land in
/// the next PR; this commit ships the bare editor.
///
/// **Lifecycle.** `NotebookFeature` owns the block load: on appear and
/// on page swipe it fetches blocks for the current page and seeds a
/// text block if none exists. The flushing of pending writes on
/// teardown is handled here via `.onDisappear` (sibling of the
/// existing `CanvasScreen` save-on-disappear pattern).
struct TextNoteWiringView: View {
    @Bindable var store: StoreOf<NotebookFeature>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.canvas.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: true) {
                editorRegion
                    .padding(.horizontal, 24)
                    .padding(.vertical, 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            // Dismiss button — matches the chrome the canvas notebook
            // uses (NotebookScreen renders the same X above the
            // TabView). Lives here directly because the text variant
            // doesn't share NotebookScreen's TabView layout.
            VStack {
                HStack {
                    Spacer()
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
                }
                Spacer()
            }
        }
        .task { store.send(.onAppear) }
        .onDisappear {
            store.send(.textEditing(.flush))
        }
    }

    private var editorRegion: some View {
        TextBlockView(model: .init(
            isPresented: store.textEditing.activeBlock != nil,
            failureState: store.textEditing.loadFailure,
            body: store.textEditing.body,
            onBodyEdited: { body in
                store.send(.textEditing(.bodyEdited(body)))
            },
            onCreateRequested: {
                // The reducer auto-seeds an empty block on appear when
                // none exists, so the empty-state tap is a no-op for
                // v1. Reserved for future "tap to add another block"
                // semantics when hybrid pages land.
            },
            onRetryRequested: {
                // Retry currently re-runs the page-blocks load by
                // sending the current index back through the reducer.
                store.send(.currentIndexChanged(store.currentIndex))
            }
        ))
    }
}
