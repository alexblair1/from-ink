import SwiftUI

/// SwiftUI `TextEditor`-backed view for a single text block in a note.
///
/// Component view — no TCA imports. Reads a `Model` of flat resolved
/// fields, emits user edits via the `onBodyEdited` closure, and stays
/// pure: every visible state (editing, empty, decode-failed, orphan,
/// persist-failed) is a fully described field on the Model.
///
/// **Engine.** iOS 26's `TextEditor` accepts an `AttributedString`
/// binding and natively handles rich text — bold / italic / underline /
/// strikethrough, custom fonts, colors, paragraph styling, and (the
/// load-bearing bit for From Ink) custom `AttributeScopes` like
/// `FromInkAttributes`. The component view is thin precisely because
/// the framework does the heavy lifting.
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
            TextEditor(
                text: Binding(
                    get: { model.body },
                    set: { model.onBodyEdited($0) }
                ),
                selection: Binding(
                    get: { model.selection },
                    set: { model.onSelectionChanged($0) }
                )
            )
            .font(model.bodyFont)
            .foregroundStyle(model.bodyColor)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .accessibilityLabel(model.editorAccessibilityLabel)
            .accessibilityHint(model.accessibilityHint)

            // Inline placeholder — SwiftUI's TextEditor has no native
            // prompt, so we overlay one. Fades to clear as soon as
            // any character lands. `.allowsHitTesting(false)` keeps
            // taps reaching the editor underneath.
            if model.isBodyEmpty {
                Text(model.emptyBlockPlaceholder)
                    .font(model.bodyFont)
                    .foregroundStyle(model.placeholderColor)
                    .padding(.top, model.placeholderTopOffset)
                    .padding(.leading, model.placeholderLeadingOffset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

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
        // Same surface as decode failure, different copy. Orphan
        // blocks are a persistence inconsistency, not a per-block
        // corruption — but the user-visible outcome is the same:
        // tap to surface a recovery affordance.
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

        let body: AttributedString
        let isBodyEmpty: Bool

        /// Mirrors `TextEditingFeature.State.selection`. The editor
        /// binds the iOS 26 `selection:` parameter through this
        /// field so format actions (block / inline) target the
        /// user's caret / range instead of the whole body.
        let selection: AttributedTextSelection

        /// Non-nil when the most recent persist attempt failed; the
        /// banner renders above the editor. The editor itself remains
        /// usable; next edit triggers a fresh persist that clears
        /// this on success.
        let persistFailureTitle: String?
        let persistFailureSubtitle: String

        let onBodyEdited: (AttributedString) -> Void
        let onSelectionChanged: (AttributedTextSelection) -> Void
        let onCreateRequested: () -> Void
        let onRetryRequested: () -> Void

        let bodyFont: Font
        let bodyColor: Color
        let placeholderColor: Color
        let placeholderTopOffset: CGFloat
        let placeholderLeadingOffset: CGFloat
        let headlineFont: Font
        let subheadFont: Font
        let bannerTitleFont: Font
        let secondaryColor: Color
        let bannerBackground: Color
        let bannerBorderColor: Color
        let bannerHorizontalPadding: CGFloat
        let bannerVerticalPadding: CGFloat

        let emptyBlockPlaceholder: String
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
        body: AttributedString,
        selection: AttributedTextSelection = AttributedTextSelection(),
        persistFailureTitle: String? = nil,
        onBodyEdited: @escaping (AttributedString) -> Void,
        onSelectionChanged: @escaping (AttributedTextSelection) -> Void = { _ in },
        onCreateRequested: @escaping () -> Void,
        onRetryRequested: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.isPresented = isPresented
        self.failureState = failureState
        self.body = body
        self.selection = selection
        self.isBodyEmpty = body.characters.isEmpty
        self.persistFailureTitle = persistFailureTitle
        self.persistFailureSubtitle = AppStrings.TextEditing.persistFailedBannerSubtitle
        self.onBodyEdited = onBodyEdited
        self.onSelectionChanged = onSelectionChanged
        self.onCreateRequested = onCreateRequested
        self.onRetryRequested = onRetryRequested
        // Body uses the serif notebook stack — content typography per
        // CLAUDE.md ("Notebook content: New York serif").
        self.bodyFont = .system(.body, design: .serif)
        self.bodyColor = ds.colors.ink
        self.placeholderColor = ds.colors.ink3
        // Match SwiftUI's TextEditor default content insets so the
        // placeholder text aligns with the caret. iOS 26's TextEditor
        // insets the text content roughly 8pt top / 5pt leading from
        // the editor frame; ds.spacing.sm covers both.
        self.placeholderTopOffset = ds.spacing.sm
        self.placeholderLeadingOffset = ds.spacing.xs
        self.headlineFont = .system(.title2, design: .serif)
        self.subheadFont = .system(.subheadline, design: .default)
        self.bannerTitleFont = .system(.footnote, design: .default).weight(.medium)
        self.secondaryColor = ds.colors.ink2
        self.bannerBackground = ds.colors.surface
        self.bannerBorderColor = ds.colors.rule
        self.bannerHorizontalPadding = ds.spacing.md
        self.bannerVerticalPadding = ds.spacing.sm
        self.emptyBlockPlaceholder = AppStrings.TextEditing.emptyBlockPlaceholder
        self.emptyNoteHeadline = AppStrings.TextEditing.emptyNoteHeadline
        self.emptyNoteSubhead = AppStrings.TextEditing.emptyNoteSubhead
        self.decodeFailureHeadline = AppStrings.TextEditing.bodyDecodeFailedHeadline
        self.decodeFailureSubhead = AppStrings.TextEditing.bodyDecodeFailedSubhead
        self.editorAccessibilityLabel = AppStrings.TextEditing.editorAccessibilityLabel
        self.accessibilityHint = AppStrings.TextEditing.blockAccessibilityHint
    }
}
