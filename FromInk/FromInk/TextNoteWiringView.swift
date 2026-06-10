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
///
/// **Slash popover anchoring.** The slash trigger fires with a
/// caret rect from the editor's `UITextView` (in editor-local
/// coordinates). We stash it in `@State` so the popover modifier on
/// `TextBlockView` has a stable anchor while the palette stays
/// open — the caret moves forward as the user types filter
/// characters, but the popover stays pinned to the slash glyph.
struct TextNoteWiringView: View {
    @Bindable var store: StoreOf<NotebookFeature>
    @Environment(\.dismiss) private var dismiss

    @State private var slashPopoverAnchorRect: CGRect = .zero

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
            onSlashTyped: { path, offset, rect in
                slashPopoverAnchorRect = rect
                store.send(.textEditing(.slashTyped(blockPath: path, offsetUTF16: offset)))
            },
            onEditorCommand: { command in
                handle(command: command)
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
            },
            slashPopover: TextBlockView.SlashPopover(
                isOpen: store.textEditing.slashPalette.isOpen,
                anchorRect: slashPopoverAnchorRect,
                rows: paletteRows(),
                filterText: store.textEditing.slashPalette.filterText,
                onAnchorMoved: { rect in
                    // Republished by the editor's scroll observer
                    // while the palette is open — keeps the
                    // popover anchored to the slash glyph as the
                    // textView scrolls.
                    slashPopoverAnchorRect = rect
                },
                onDismissed: {
                    store.send(.textEditing(.slashPalette(.dismissed)))
                }
            )
        ))
    }

    /// Build the row list the slash popover renders from the current
    /// palette state. Indexed match against `selectedIndex` so
    /// keyboard navigation highlights the right row; `availability`
    /// drives the coming-soon badge.
    private func paletteRows() -> [SlashMenuPopoverView.Row] {
        store
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
    private func handle(command: EditorCommand) {
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
        case .exitList:
            store.send(.textEditing(.exitList))
        case .openSlashPalette(let caretRectInEditor):
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
            slashPopoverAnchorRect = caretRectInEditor
            store.send(.textEditing(.slashTyped(blockPath: path, offsetUTF16: offset)))
        }
    }
}
