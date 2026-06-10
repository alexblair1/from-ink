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
        let paletteOpen = store.textEditing.slashPalette.isOpen
        let matchedCount = store.textEditing.slashPalette.matchedCommands.count
        let triggerOffset = store.textEditing.slashPalette.triggerOffset ?? -1
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

            // TEMPORARY DEBUG — pinned to top-leading so we can see
            // palette state regardless of where the popover renders.
            // Remove once the slash menu is verified working.
            VStack(alignment: .leading, spacing: 2) {
                Text("DEBUG  isOpen=\(paletteOpen.description)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(paletteOpen ? Color.green : Color.red)
                Text("matched=\(matchedCount)  trigger=\(triggerOffset)")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.white)
            }
            .padding(6)
            .background(Color.black.opacity(0.7))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, 40)
            .padding(.leading, 8)
            .allowsHitTesting(false)
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
            onSlashTyped: { path, offset in
                store.send(.textEditing(.slashTyped(blockPath: path, offsetUTF16: offset)))
            },
            onEditorCommand: { command in
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
