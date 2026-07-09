import SwiftUI

/// Text block view for a single text block in a note.
///
/// Component view — no TCA imports. Reads a `Model` of flat resolved
/// fields, emits user edits via the closure callbacks on the Model,
/// and stays pure: every visible state (editing, empty, decode-failed,
/// orphan, persist-failed) is a fully described field on the Model.
///
/// **2026-06-09 — Editor refactor in progress.** This view's editor
/// region currently renders a READ-ONLY view of the document's
/// `plainText`. The previous SwiftUI `TextEditor` / TextKit 2
/// UITextView paths are deleted; the production editor — a TextKit 1
/// `UITextView` with a `BlockDecoratingLayoutManager` per
/// `text_experience_edd.md` §22.4 commit 4 — lands in the next commit.
/// Until then, the user can view but not edit text notes.
///
/// **Failure states.**
///   - `.bodyDecodeFailed` — corrupted bytes on disk. Tap to retry
///     (re-runs the page-blocks load).
///   - `.orphan` — block is missing its page back-pointer. Surfaces
///     the persistence inconsistency rather than masking it.
///   - `.none` with no model — empty-note placeholder. Tap to ask the
///     wiring view to re-seed (defense against failed auto-seed).
///   - `lastPersistFailureTitle != nil` — banner above the editor;
///     the editor itself remains usable. Next edit retries the save.
struct TextBlockView: View {
    let model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title = model.persistFailureTitle {
                persistFailureBanner(title: title)
            }
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.failureState {
        case .none where model.isPresented:
            editor

        case .none:
            emptyNote

        case .bodyDecodeFailed:
            decodeFailure

        case .orphan:
            orphan
        }
    }

    // MARK: - Editor

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            #if os(iOS) || os(visionOS)
            TextKitEditorView(
                document: Binding(
                    get: { model.document },
                    set: { model.onDocumentEdited($0) }
                ),
                selection: Binding(
                    get: { model.selection },
                    set: { model.onSelectionChanged($0) }
                ),
                onSlashTyped: { path, offset, rect in
                    model.onSlashTyped(path, offset, rect)
                },
                onCommand: { command in
                    model.onEditorCommand(command)
                },
                onCaretAnchorMoved: { rect in
                    model.slashPopover.onAnchorMoved(rect)
                },
                onSlashFilterChanged: { filter in
                    model.slashPopover.onFilterChanged(filter)
                },
                isSlashPaletteOpen: model.slashPopover.isOpen,
                onContentHeightChanged: { height in
                    model.onContentHeightChanged(height)
                },
                bodyFont: Self.serifBodyFont(),
                bodyColor: UIColor(model.bodyColor)
            )
            #else
            // macOS placeholder until the NSTextView wrapper lands.
            Text(model.plainText)
                .font(model.bodyFont)
                .foregroundStyle(model.bodyColor)
            #endif

        }
        // The block stack owns scrolling (hybrid_page_edd.md §3.1) —
        // this row is a non-scrolling, self-sized cell: height is the
        // editor's reported content height, floored at
        // `editorMinHeight` (the wiring passes the stack viewport so a
        // short note still fills the page and taps below the last
        // line land IN the editor, preserving tap-to-focus). Before
        // the first height report, only the floor applies. The slash
        // popover modifier moved UP to the stack container — the
        // stationary anchor view.
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: model.editorFrameHeight, alignment: .topLeading)
        .frame(minHeight: model.editorMinHeight, alignment: .topLeading)
        .accessibilityLabel(model.editorAccessibilityLabel)
        .accessibilityHint(model.accessibilityHint)
    }

    #if os(iOS) || os(visionOS)
    /// Serif body font for the TextKit 1 editor — matches the
    /// `.system(.body, design: .serif)` token used elsewhere.
    private static func serifBodyFont() -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: .body)
        let descriptor = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
        return UIFont(descriptor: descriptor, size: 0)
    }
    #endif

    // MARK: - Empty / failure placeholders

    private var emptyNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.emptyNoteHeadline)
                .font(model.headlineFont)
                .foregroundStyle(model.bodyColor)
            Text(model.emptyNoteSubhead)
                .font(model.subheadFont)
                .foregroundStyle(model.secondaryColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { model.onCreateRequested() }
    }

    private var decodeFailure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.decodeFailureHeadline)
                .font(model.headlineFont)
                .foregroundStyle(model.bodyColor)
            Text(model.decodeFailureSubhead)
                .font(model.subheadFont)
                .foregroundStyle(model.secondaryColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { model.onRetryRequested() }
    }

    private var orphan: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.decodeFailureHeadline)
                .font(model.headlineFont)
                .foregroundStyle(model.bodyColor)
            Text(model.decodeFailureSubhead)
                .font(model.subheadFont)
                .foregroundStyle(model.secondaryColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { model.onRetryRequested() }
    }

    // MARK: - Persist-failure banner

    private func persistFailureBanner(title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(model.bannerTitleFont)
                .foregroundStyle(model.bodyColor)
            Text(model.persistFailureSubtitle)
                .font(model.subheadFont)
                .foregroundStyle(model.secondaryColor)
        }
        .padding(.horizontal, model.bannerHorizontalPadding)
        .padding(.vertical, model.bannerVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(model.bannerBackground)
        .overlay(
            Rectangle()
                .fill(model.bannerBorderColor)
                .frame(height: 1),
            alignment: .bottom
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - SlashPopover state

extension TextBlockView {
    /// Slash command palette popover surface. Clusters the five
    /// fields the popover modifier reads so the Model stays flat
    /// for view-level rendering but doesn't spray slash-specific
    /// names across its top level. When a second popover type
    /// lands (highlight color picker, selection menu), generalize
    /// to an `EditorPopover` enum — `n=1` doesn't justify the
    /// abstraction yet.
    struct SlashPopover {
        let isOpen: Bool
        /// Caret rect in the editor `UITextView`'s viewport space
        /// (post `contentOffset` subtraction). Matches SwiftUI's
        /// `.popover(attachmentAnchor: .rect(...))` coordinate
        /// convention so no translation happens at the modifier.
        let anchorRect: CGRect
        let rows: [SlashMenuPopoverView.Row]
        let filterText: String
        /// Republished by the editor's scroll observer while the
        /// palette is open. The wiring view stores the rect in
        /// `@State` so the popover follows the slash glyph through
        /// scroll without us observing scroll from SwiftUI.
        let onAnchorMoved: (CGRect) -> Void
        /// Live filter text computed storage-side per keystroke while
        /// the palette is open (the document mirror is debounced —
        /// EDD §22.4.1). `nil` means the trigger `/` was deleted; the
        /// wiring dismisses.
        let onFilterChanged: (String?) -> Void
        let onDismissed: () -> Void

        static let closed = SlashPopover(
            isOpen: false,
            anchorRect: .zero,
            rows: [],
            filterText: "",
            onAnchorMoved: { _ in },
            onFilterChanged: { _ in },
            onDismissed: {}
        )
    }
}

// MARK: - Slash popover modifier

/// Attaches a caret-anchored `.popover()` to the editor when the
/// slash palette is open. SwiftUI's `.popover` wraps
/// `UIPopoverPresentationController` natively — we get the system
/// arrow, tap-outside dismissal, VoiceOver focus management, and
/// safe-area-aware repositioning for free.
///
/// **Coordinate space.** `popover.anchorRect` is in the block
/// STACK's viewport space (hybrid_page_edd.md §3.1) — the modifier
/// is applied to the stationary scroll container in
/// `NotePageWiringView`, not to the (scrolling) editor row.
/// `TextKitEditorView.stackViewportRect` converts caret rects into
/// this space at capture time, and the editor's stack-scroll KVO
/// republishes the rect on every scroll tick, so the modifier uses
/// the rect directly without further translation.
///
/// **`arrowEdge: .top`** — popover appears BELOW the caret (arrow
/// points up at it). Follows the autocomplete convention (Notion,
/// Slack, Xcode quick help): the user is typing forward and looks
/// downward for suggestions. `UIPopoverPresentationController`
/// auto-flips to above when there isn't enough room below, so the
/// system handles the keyboard-overlap edge case for us.
///
/// **`presentationCompactAdaptation(.popover)`** — load-bearing.
/// Without it, iOS renders this as a full-height sheet in compact
/// horizontal size class (iPhone, iPad split view). A contextual
/// command palette as a sheet is the wrong UX — it covers the
/// document you're filtering against. Forcing `.popover` keeps the
/// caret-anchored behavior consistent across iPhone, iPad, and Mac
/// Catalyst.
///
/// **`presentationBackground(Color.clear)`** — drops the system
/// popover's translucent material so `SlashMenuPopoverView`'s own
/// paper background shows through. Without this the chrome
/// double-stacks (system material under the palette's opaque
/// paper) and the iPhone variant in particular reads as
/// Liquid-Glass-adjacent — a direct violation of the paper-and-ink
/// aesthetic the design system locks in. The system arrow still
/// renders because `.presentationBackground` only affects the
/// content container.
struct SlashPopoverModifier: ViewModifier {
    let popover: TextBlockView.SlashPopover

    func body(content: Content) -> some View {
        content
            .popover(
                isPresented: Binding(
                    get: { popover.isOpen },
                    set: { newValue in
                        if !newValue { popover.onDismissed() }
                    }
                ),
                attachmentAnchor: .rect(.rect(popover.anchorRect)),
                arrowEdge: .top
            ) {
                SlashMenuPopoverView(model: .init(
                    rows: popover.rows,
                    filterText: popover.filterText
                ))
                .presentationCompactAdaptation(.popover)
                .presentationBackground(Color.clear)
                // Lets the user scroll / interact with the editor
                // while the palette is open — without this, every
                // outside touch (including the first frame of a
                // scroll gesture) dismisses the popover. The
                // wiring view's scroll observer keeps the anchor
                // tracking the slash glyph through the scroll.
                .presentationBackgroundInteraction(.enabled)
            }
    }
}

// MARK: - Model

extension TextBlockView {
    struct Model {
        let isPresented: Bool
        let failureState: TextEditingFeature.State.LoadFailure?

        let document: RichTextDocument
        let plainText: String

        /// Mirrors `TextEditingFeature.State.selection`. The editor
        /// will bind through this once it lands in commit 4; the
        /// transitional placeholder ignores it.
        let selection: BlockTreeSelection

        /// Non-nil when the most recent persist attempt failed; the
        /// banner renders above the editor. The editor itself remains
        /// usable; next edit triggers a fresh persist that clears
        /// this on success.
        let persistFailureTitle: String?
        let persistFailureSubtitle: String

        /// Callbacks the real editor (commit 4) will invoke. The
        /// transitional placeholder doesn't call any of them.
        let onDocumentEdited: (RichTextDocument) -> Void
        let onSelectionChanged: (BlockTreeSelection) -> Void
        let onSlashTyped: (_ blockPath: [UUID], _ offsetUTF16: Int, _ caretRectInEditor: CGRect) -> Void
        let onEditorCommand: (EditorCommand) -> Void
        let onCreateRequested: () -> Void
        let onRetryRequested: () -> Void

        /// Slash command palette popover state. The wiring view
        /// captures the caret rect when the slash trigger fires and
        /// builds the row list from store state; the editor's
        /// scroll observer republishes the rect via
        /// `slashPopover.onAnchorMoved`.
        let slashPopover: SlashPopover

        /// Editor content-height report (hybrid stack Phase 1) — the
        /// wiring view stores it and the stack sizes this row from it.
        let onContentHeightChanged: (CGFloat) -> Void

        /// Minimum editor-row height, resolved by the stack (its
        /// viewport height) so a short note still fills the page and
        /// tap-to-focus works below the last line.
        let editorMinHeight: CGFloat

        /// Exact editor-row height once a content-height report has
        /// landed — `max(reported, editorMinHeight)`, resolved in the
        /// Model init. Nil before the first report (the min-height
        /// floor alone applies).
        let editorFrameHeight: CGFloat?

        let bodyFont: Font
        let bodyColor: Color
        let headlineFont: Font
        let subheadFont: Font
        let bannerTitleFont: Font
        let secondaryColor: Color
        let bannerBackground: Color
        let bannerBorderColor: Color
        let bannerHorizontalPadding: CGFloat
        let bannerVerticalPadding: CGFloat

        let editorPlaceholderHeadline: String
        let emptyNoteHeadline: String
        let emptyNoteSubhead: String
        let decodeFailureHeadline: String
        let decodeFailureSubhead: String
        let editorAccessibilityLabel: String
        let accessibilityHint: String
    }
}

// MARK: - Model init (resolves design tokens + AppStrings)

extension TextBlockView.Model {
    init(
        isPresented: Bool,
        failureState: TextEditingFeature.State.LoadFailure?,
        document: RichTextDocument,
        selection: BlockTreeSelection = BlockTreeSelection(),
        persistFailureTitle: String? = nil,
        onDocumentEdited: @escaping (RichTextDocument) -> Void = { _ in },
        onSelectionChanged: @escaping (BlockTreeSelection) -> Void = { _ in },
        onSlashTyped: @escaping (_ blockPath: [UUID], _ offsetUTF16: Int, _ caretRectInEditor: CGRect) -> Void = { _, _, _ in },
        onEditorCommand: @escaping (EditorCommand) -> Void = { _ in },
        onCreateRequested: @escaping () -> Void,
        onRetryRequested: @escaping () -> Void,
        slashPopover: TextBlockView.SlashPopover = .closed,
        onContentHeightChanged: @escaping (CGFloat) -> Void = { _ in },
        editorMinHeight: CGFloat = 0,
        editorContentHeight: CGFloat? = nil,
        ds: DesignSystem = .standard
    ) {
        self.isPresented = isPresented
        self.failureState = failureState
        self.document = document
        // `plainText` feeds only the macOS read-only placeholder.
        // Resolving it on iOS would walk the entire document on every
        // SwiftUI render — every keystroke AND every caret move (the
        // selection mirror re-renders the wiring view) — render-cost
        // rule S4.
        #if os(macOS)
        self.plainText = document.plainText
        #else
        self.plainText = ""
        #endif
        self.selection = selection
        self.persistFailureTitle = persistFailureTitle
        self.persistFailureSubtitle = AppStrings.TextEditing.persistFailedBannerSubtitle
        self.onDocumentEdited = onDocumentEdited
        self.onSelectionChanged = onSelectionChanged
        self.onSlashTyped = onSlashTyped
        self.onEditorCommand = onEditorCommand
        self.onCreateRequested = onCreateRequested
        self.onRetryRequested = onRetryRequested
        self.slashPopover = slashPopover
        self.onContentHeightChanged = onContentHeightChanged
        self.editorMinHeight = editorMinHeight
        self.editorFrameHeight = editorContentHeight.map { max($0, editorMinHeight) }
        self.bodyFont = .system(.body, design: .serif)
        self.bodyColor = ds.colors.ink
        self.headlineFont = .system(.title2, design: .serif)
        self.subheadFont = .system(.subheadline, design: .default)
        self.bannerTitleFont = .system(.footnote, design: .default).weight(.medium)
        self.secondaryColor = ds.colors.ink2
        self.bannerBackground = ds.colors.surface
        self.bannerBorderColor = ds.colors.rule
        self.bannerHorizontalPadding = ds.spacing.md
        self.bannerVerticalPadding = ds.spacing.sm
        self.editorPlaceholderHeadline = ""
        self.emptyNoteHeadline = AppStrings.TextEditing.emptyNoteHeadline
        self.emptyNoteSubhead = AppStrings.TextEditing.emptyNoteSubhead
        self.decodeFailureHeadline = AppStrings.TextEditing.bodyDecodeFailedHeadline
        self.decodeFailureSubhead = AppStrings.TextEditing.bodyDecodeFailedSubhead
        self.editorAccessibilityLabel = AppStrings.TextEditing.editorAccessibilityLabel
        self.accessibilityHint = AppStrings.TextEditing.blockAccessibilityHint
    }
}
