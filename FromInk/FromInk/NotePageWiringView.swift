import ComposableArchitecture
import SwiftUI

/// Wiring view for a note page's block stack (hybrid_page_edd.md
/// §5.2). Phase 1: hosts the textNote variant — one text block inside
/// the stack, scoped under `NotePageFeature`.
///
/// Succeeds `TextNoteWiringView`: same slash-palette rows,
/// `EditorCommand` mapping, dismiss chrome, and flush lifecycle —
/// re-pointed at the page feature and re-hosted inside
/// `PageBlockStackView`, which owns the page's single vertical scroll.
///
/// **Slash popover anchoring.** The trigger fires with a caret rect
/// in STACK-viewport space (`TextKitEditorView.stackViewportRect`).
/// The popover modifier is applied to the stack container — the
/// stationary anchor view — so the rect needs no further translation,
/// and the editor's stack-scroll KVO republishes it while the palette
/// is open.
///
/// **Height plumbing.** The editor reports its content height; we
/// store it here and resolve the row's frame in the `TextBlockView`
/// model, floored at the stack viewport height so short notes fill
/// the page and taps below the last line land in the editor.
struct NotePageWiringView: View {
    @Bindable var store: StoreOf<NotePageFeature>
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var slashPopoverAnchorRect: CGRect = .zero
    @State private var editorContentHeight: CGFloat? = nil

    private let ds = DesignSystem.standard

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ds.colors.paper.ignoresSafeArea()

                PageBlockStackView(model: .init(
                    textBlock: textBlockModel(
                        minHeight: max(0, geo.size.height - ds.spacing.xl * 2)
                    )
                ))
                .modifier(SlashPopoverModifier(popover: slashPopover()))

                dismissChrome
            }
        }
        .onDisappear {
            store.send(.textEditing(.flush))
        }
        // Backgrounding flush (readiness audit A3). The editor's
        // Coordinator has already pushed its debounced tail through the
        // binding on willResignActive (which UIKit posts BEFORE
        // scenePhase leaves .active), so this flush persists the
        // current document — closing the window where a swipe-to-
        // background inside the debounce lost the last ~1s of typing.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                store.send(.textEditing(.flush))
            }
        }
    }

    // MARK: - Row model

    private func textBlockModel(minHeight: CGFloat) -> TextBlockView.Model {
        TextBlockView.Model(
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
                // Tap on the empty-state placeholder re-runs the
                // page-blocks load, which seeds an empty text block if
                // none exists. Defense against a failed auto-seed
                // leaving the user stranded on the placeholder.
                store.send(.reloadRequested)
            },
            onRetryRequested: {
                // Decode-failed / orphan placeholder retry — same
                // path as the empty-state tap: re-run the load.
                store.send(.reloadRequested)
            },
            slashPopover: slashPopover(),
            onContentHeightChanged: { height in
                editorContentHeight = height
            },
            editorMinHeight: minHeight,
            editorContentHeight: editorContentHeight
        )
    }

    // MARK: - Slash palette surface

    private func slashPopover() -> TextBlockView.SlashPopover {
        TextBlockView.SlashPopover(
            isOpen: store.textEditing.slashPalette.isOpen,
            anchorRect: slashPopoverAnchorRect,
            rows: paletteRows(),
            filterText: store.textEditing.slashPalette.filterText,
            onAnchorMoved: { rect in
                // Republished by the editor's stack-scroll KVO while
                // the palette is open — keeps the popover anchored to
                // the slash glyph as the stack scrolls.
                slashPopoverAnchorRect = rect
            },
            onFilterChanged: { filter in
                // Storage-side live filter (the reducer's
                // document-based refresh converges to the same
                // value on each debounced documentEdited). nil
                // means the trigger `/` was deleted.
                if let filter {
                    store.send(.textEditing(.slashPalette(.filterChanged(filter))))
                } else {
                    store.send(.textEditing(.slashPalette(.dismissed)))
                }
            },
            onDismissed: {
                store.send(.textEditing(.slashPalette(.dismissed)))
            }
        )
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
                        .foregroundStyle(ds.colors.ink2)
                        .frame(width: ds.layout.dismissHitTarget,
                               height: ds.layout.dismissHitTarget)
                        .background(ds.colors.surface.opacity(0.85))
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
        case .insertParagraph:
            store.send(.textEditing(.insertParagraph))
        case .openSlashPalette(let caretRectInStack):
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
            slashPopoverAnchorRect = caretRectInStack
            store.send(.textEditing(.slashTyped(blockPath: path, offsetUTF16: offset)))
        }
    }
}
