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

    /// Latest caret rect reported by the editor — in **screen
    /// coordinates** so the popover positioning is robust to wherever
    /// the editor sits in the SwiftUI hierarchy. Updated on every
    /// `onSlashTyped` (`/` typed at a word boundary) and on every
    /// `.openSlashPalette` keyboard-shortcut command. The popover
    /// translates back to its local space via a `GeometryReader`
    /// reading its own `.frame(in: .global)`.
    @State private var slashCaretRectScreen: CGRect = .zero

    private let ds = DesignSystem.standard

    var body: some View {
        let paletteOpen = store.textEditing.slashPalette.isOpen
        return ZStack {
            Color.canvas.ignoresSafeArea()

            editorRegion
                .frame(maxWidth: ds.layout.textEditorMaxContentWidth, alignment: .leading)
                .padding(.horizontal, ds.spacing.lg)
                .padding(.vertical, ds.spacing.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // Hide editor from VoiceOver while the palette is
                // open so the modal popover is the only focus
                // target. allowsHitTesting alone doesn't block
                // VoiceOver — both modifiers are required per
                // `feedback_modal_accessibility.md`.
                .accessibilityHidden(paletteOpen)

            dismissChrome
                .accessibilityHidden(paletteOpen)

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
            document: store.textEditing.document,
            selection: store.textEditing.selection,
            persistFailureTitle: store.textEditing.lastPersistFailureReason
                .map { _ in AppStrings.TextEditing.persistFailedBannerTitle },
            onDocumentEdited: { document in
                store.send(.textEditing(.documentEdited(document)))
            },
            onSelectionChanged: { selection in
                store.send(.textEditing(.selectionChanged(selection)))
            },
            onSlashTyped: { path, offset, caretRect in
                slashCaretRectScreen = caretRect
                store.send(.textEditing(.slashTyped(blockPath: path, offsetUTF16: offset)))
            },
            onEditorCommand: { command in
                if case let .openSlashPalette(rect) = command {
                    slashCaretRectScreen = rect
                }
                Self.handle(command: command, store: store)
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

    /// Slash command palette overlay. Anchored to the caret rect
    /// captured at trigger time — see `slashCaretRectScreen`. A
    /// `GeometryReader` translates screen coords (UIView.convert
    /// result from the editor) into this overlay's local space, then
    /// the popover sits just below the caret at the caret's leading
    /// edge. If the caret rect is empty / off-screen (initial state,
    /// off-screen during programmatic edits), the popover falls back
    /// to a small inset from the overlay's top-leading corner so it
    /// remains visible.
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

        let popover = SlashMenuPopoverView(model: .init(
            rows: rows,
            filterText: store.textEditing.slashPalette.filterText
        ))
        let caretRect = slashCaretRectScreen

        return GeometryReader { proxy in
            let overlayOriginScreen = proxy.frame(in: .global).origin
            let translatedX = max(0, caretRect.minX - overlayOriginScreen.x)
            let translatedY = max(0, caretRect.maxY - overlayOriginScreen.y + 6)
            // Tap-outside dismiss surface (transparent, full-bounds).
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.send(.textEditing(.slashPalette(.dismissed)))
                    }
                popover
                    .offset(x: translatedX, y: translatedY)
            }
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

    /// Map an editor-side `EditorCommand` onto the corresponding
    /// reducer action. The editor stays feature-agnostic; this is
    /// where the keyboard-shortcut → TCA action coupling lives.
    ///
    /// **Selection sync invariant.** `.openSlashPalette` reads
    /// `store.textEditing.selection` to decide WHERE to open the
    /// palette. That state is kept fresh by
    /// `TextKitEditorView.Coordinator.textViewDidChangeSelection`,
    /// which fires on every cursor move BEFORE any key-command
    /// handler runs (UIKit dispatches selection-change delegates
    /// synchronously during typing). If you ever change the selection-
    /// sync pattern (batching, debouncing, etc.), audit this method
    /// — a stale selection would target the wrong leaf.
    ///
    /// **Empty-selection fallback (M2).** When `selection.path` is
    /// empty (no cursor placed yet, e.g. brand-new document), the
    /// palette would otherwise open with an empty path then dismiss
    /// on the first edit via the refresh effect. Fall back to the
    /// document's last leaf — same fallback `applyBlockFormat`
    /// already uses for unset selections.
    private static func handle(command: EditorCommand, store: StoreOf<NotebookFeature>) {
        switch command {
        case .toggleBold:
            store.send(.textEditing(.toggleInlineFormat(.bold)))
        case .toggleItalic:
            store.send(.textEditing(.toggleInlineFormat(.italic)))
        case .toggleUnderline:
            store.send(.textEditing(.toggleInlineFormat(.underline)))
        case .toggleStrikethrough:
            store.send(.textEditing(.toggleInlineFormat(.strikethrough)))
        case .toggleCode:
            store.send(.textEditing(.toggleInlineFormat(.code)))
        case .applyHeading(let level):
            store.send(.textEditing(.applyBlockFormat(.heading(level: level))))
        case .applyBody:
            store.send(.textEditing(.applyBlockFormat(.body)))
        case .applyBulletedList:
            store.send(.textEditing(.applyBlockFormat(.bulletedList)))
        case .applyNumberedList:
            store.send(.textEditing(.applyBlockFormat(.numberedList)))
        case .openSlashPalette:
            // The caret rect is read by the view-layer @State in the
            // body closure; here we only dispatch the reducer action.
            let selection = store.textEditing.selection
            // Empty selection — fall back to the document's last leaf
            // so the palette opens with a usable trigger location.
            let path: [UUID]
            let offset: Int
            if !selection.path.isEmpty {
                path = selection.path
                offset = selection.startUTF16
            } else if let lastLeaf = store.textEditing.document.lastLeafBlock {
                path = [lastLeaf.id]
                offset = lastLeaf.joinedInlineText?.utf16.count ?? 0
            } else {
                // Empty document — no leaf to anchor to; no-op.
                return
            }
            store.send(.textEditing(.slashTyped(blockPath: path, offsetUTF16: offset)))
        }
    }
}
