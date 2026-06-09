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
/// text block if none exists. `.onDisappear` flushes any pending body
/// writes through the reducer (sibling of the existing `CanvasScreen`
/// save-on-disappear pattern).
///
/// **Layout.** The editor fills its frame natively — no outer
/// `ScrollView`. `TextEditor` already scrolls; nesting it inside a
/// ScrollView creates gesture-recognizer ambiguity that reads as
/// jank on iPad. Content width is capped at
/// `textEditorMaxContentWidth` and centered so long-form reading on
/// wide viewports stays comfortable.
struct TextNoteWiringView: View {
    @Bindable var store: StoreOf<NotebookFeature>
    @Environment(\.dismiss) private var dismiss

    private let ds = DesignSystem.standard

    var body: some View {
        ZStack {
            Color.canvas.ignoresSafeArea()

            editorRegion
                .frame(maxWidth: ds.layout.textEditorMaxContentWidth, alignment: .leading)
                .padding(.horizontal, ds.spacing.lg)
                .padding(.vertical, ds.spacing.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            dismissChrome

            slashPaletteOverlay
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
            body: store.textEditing.editingBody,
            persistFailureTitle: store.textEditing.lastPersistFailureReason
                .map { _ in AppStrings.TextEditing.persistFailedBannerTitle },
            onBodyEdited: { body in
                store.send(.textEditing(.bodyEdited(body)))
            },
            onCreateRequested: {
                // Tap on the empty-state placeholder asks the
                // notebook feature to re-run the page-blocks load,
                // which seeds an empty text block if none exists.
                // Defense against a failed auto-seed leaving the
                // user stranded on the placeholder.
                store.send(.textBlocksReloadRequested)
            },
            onRetryRequested: {
                // Decode-failed / orphan placeholder retry — same
                // path as the empty-state tap: re-run the load.
                store.send(.textBlocksReloadRequested)
            }
        ))
    }

    /// Slash command palette overlay. Renders as a floating popover
    /// near the editor's top-leading edge when `slashPalette.isOpen`
    /// is true. Caret-anchored positioning is a polish follow-up;
    /// for v1 the popover sits in a consistent corner of the
    /// content frame so the user always finds it in the same place.
    @ViewBuilder
    private var slashPaletteOverlay: some View {
        if store.textEditing.slashPalette.isOpen {
            slashPalettePopover
                .transition(.opacity)
                .accessibilityAddTraits(.isModal)
        }
    }

    private var slashPalettePopover: some View {
        let rows: [SlashMenuPopoverView.Row] = store
            .textEditing
            .slashPalette
            .matchedCommands
            .enumerated()
            .map { index, descriptor in
                SlashMenuPopoverView.Row(
                    id: descriptor.id,
                    icon: descriptor.icon,
                    title: descriptor.title,
                    shortcutHint: descriptor.shortcutHint,
                    isSelected: index == store.textEditing.slashPalette.selectedIndex,
                    isComingSoon: descriptor.availability == .comingSoon,
                    onTap: {
                        store.send(.textEditing(.slashPalette(.commandSelected(descriptor.id))))
                    }
                )
            }

        return VStack {
            HStack {
                SlashMenuPopoverView(model: .init(
                    rows: rows,
                    filterText: store.textEditing.slashPalette.filterText
                ))
                .padding(.top, ds.spacing.xxl)
                .padding(.leading, ds.spacing.lg + ds.spacing.md)
                Spacer()
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.send(.textEditing(.slashPalette(.dismissed)))
        }
    }

    /// Dismiss chrome — top-right X. The text variant has no canvas
    /// toolbar, so it owns the dismiss button directly rather than
    /// sharing the one `NotebookScreen` renders for the canvas path.
    private var dismissChrome: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: ds.layout.dismissIconSize, weight: .medium))
                        .foregroundStyle(Color.inkSecondary)
                        .frame(width: ds.layout.dismissHitTarget,
                               height: ds.layout.dismissHitTarget)
                        .background(Color.surface.opacity(0.85))
                        .clipShape(Circle())
                        .frame(width: ds.layout.hitTarget, height: ds.layout.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, ds.spacing.sm)
                .padding(.horizontal, ds.spacing.md)
            }
            Spacer()
        }
    }
}
