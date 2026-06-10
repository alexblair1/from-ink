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
                onSlashTyped: { path, offset in
                    model.onSlashTyped(path, offset)
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

            if model.isDocumentEmpty {
                Text(model.emptyBlockPlaceholder)
                    .font(model.bodyFont)
                    .foregroundStyle(model.placeholderColor)
                    .padding(.top, 8)
                    .padding(.leading, 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

// MARK: - Model

extension TextBlockView {
    struct Model {
        let isPresented: Bool
        let failureState: TextEditingFeature.State.LoadFailure?

        let document: RichTextDocument
        let plainText: String
        let isDocumentEmpty: Bool

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
        let onSlashTyped: (_ blockPath: [UUID], _ offsetUTF16: Int) -> Void
        let onCreateRequested: () -> Void
        let onRetryRequested: () -> Void

        let bodyFont: Font
        let bodyColor: Color
        let placeholderColor: Color
        let headlineFont: Font
        let subheadFont: Font
        let bannerTitleFont: Font
        let secondaryColor: Color
        let bannerBackground: Color
        let bannerBorderColor: Color
        let bannerHorizontalPadding: CGFloat
        let bannerVerticalPadding: CGFloat

        let emptyBlockPlaceholder: String
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
        onSlashTyped: @escaping (_ blockPath: [UUID], _ offsetUTF16: Int) -> Void = { _, _ in },
        onCreateRequested: @escaping () -> Void,
        onRetryRequested: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.isPresented = isPresented
        self.failureState = failureState
        self.document = document
        self.plainText = document.plainText
        // Avoid walking the entire document via `plainText` on every
        // SwiftUI render (S4). Short-circuit on the first block that
        // has any visible content; divider counts as content.
        self.isDocumentEmpty = document.blocks.isEmpty
            || !document.blocks.contains(where: { Self.hasVisibleContent($0) })
        self.selection = selection
        self.persistFailureTitle = persistFailureTitle
        self.persistFailureSubtitle = AppStrings.TextEditing.persistFailedBannerSubtitle
        self.onDocumentEdited = onDocumentEdited
        self.onSelectionChanged = onSelectionChanged
        self.onSlashTyped = onSlashTyped
        self.onCreateRequested = onCreateRequested
        self.onRetryRequested = onRetryRequested
        self.bodyFont = .system(.body, design: .serif)
        self.bodyColor = ds.colors.ink
        self.placeholderColor = ds.colors.ink3
        self.headlineFont = .system(.title2, design: .serif)
        self.subheadFont = .system(.subheadline, design: .default)
        self.bannerTitleFont = .system(.footnote, design: .default).weight(.medium)
        self.secondaryColor = ds.colors.ink2
        self.bannerBackground = ds.colors.surface
        self.bannerBorderColor = ds.colors.rule
        self.bannerHorizontalPadding = ds.spacing.md
        self.bannerVerticalPadding = ds.spacing.sm
        self.emptyBlockPlaceholder = AppStrings.TextEditing.emptyBlockPlaceholder
        self.editorPlaceholderHeadline = ""
        self.emptyNoteHeadline = AppStrings.TextEditing.emptyNoteHeadline
        self.emptyNoteSubhead = AppStrings.TextEditing.emptyNoteSubhead
        self.decodeFailureHeadline = AppStrings.TextEditing.bodyDecodeFailedHeadline
        self.decodeFailureSubhead = AppStrings.TextEditing.bodyDecodeFailedSubhead
        self.editorAccessibilityLabel = AppStrings.TextEditing.editorAccessibilityLabel
        self.accessibilityHint = AppStrings.TextEditing.blockAccessibilityHint
    }

    /// Short-circuit visible-content check that walks only as far as
    /// the first non-empty leaf. Used in place of `document.plainText`
    /// (which walks the entire document) for the `isDocumentEmpty`
    /// flag that the placeholder overlay reads on every render.
    private static func hasVisibleContent(_ block: Block) -> Bool {
        switch block.kind {
        case .paragraph(let inline), .heading(_, let inline):
            return inline.contains { !$0.text.isEmpty }
        case .codeBlock(let text, _):
            return !text.isEmpty
        case .bulletList(let items), .orderedList(let items):
            return items.contains { item in item.content.contains(where: hasVisibleContent) }
        case .blockquote(let children):
            return children.contains(where: hasVisibleContent)
        case .divider:
            return true
        }
    }
}
