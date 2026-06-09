import SwiftUI

/// SwiftUI `TextEditor`-backed view for a single text block in a note.
///
/// Component view — no TCA imports. Reads a `Model` of flat resolved
/// fields, emits user edits via the `onBodyEdited` closure, and stays
/// pure: every visible state (editing, empty, decode-failed) is a
/// fully described case on the Model.
///
/// **Engine.** iOS 26's `TextEditor` accepts an
/// `AttributedString` binding and natively handles rich text — bold /
/// italic / underline / strikethrough, custom fonts, colors,
/// paragraph styling, and (the load-bearing bit for From Ink) custom
/// `AttributeScopes` like `FromInkAttributes`. The component view is
/// thin precisely because the framework does the heavy lifting.
///
/// **Load failures.** Three failure-state placeholders render in
/// place of the editor:
///   - `.bodyDecodeFailed` — corrupted bytes on disk. The user can
///     tap to retry.
///   - `.orphan` — block is missing its page back-pointer. Surfaces
///     the persistence inconsistency rather than masking it.
///   - `.none` (no model at all) — the empty-note placeholder.
struct TextBlockView: View {
    let model: Model

    var body: some View {
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
        TextEditor(
            text: Binding(
                get: { model.body },
                set: { model.onBodyEdited($0) }
            )
        )
        .font(model.bodyFont)
        .foregroundStyle(model.bodyColor)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .accessibilityHint(model.accessibilityHint)
        .frame(maxWidth: .infinity, alignment: .leading)
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
    }
}

// MARK: - Model

extension TextBlockView {
    struct Model {
        /// True when there's an active block to edit. False renders
        /// the empty-note placeholder regardless of `failureState`.
        let isPresented: Bool

        /// Failure state, or `.none` if the block loaded cleanly.
        let failureState: TextEditingFeature.State.LoadFailure?

        let body: AttributedString
        let onBodyEdited: (AttributedString) -> Void
        let onCreateRequested: () -> Void
        let onRetryRequested: () -> Void

        let bodyFont: Font
        let bodyColor: Color
        let headlineFont: Font
        let subheadFont: Font
        let secondaryColor: Color

        let emptyNoteHeadline: String
        let emptyNoteSubhead: String
        let decodeFailureHeadline: String
        let decodeFailureSubhead: String
        let accessibilityHint: String
    }
}

// MARK: - Model init (resolves design tokens + AppStrings)

extension TextBlockView.Model {
    init(
        isPresented: Bool,
        failureState: TextEditingFeature.State.LoadFailure?,
        body: AttributedString,
        onBodyEdited: @escaping (AttributedString) -> Void,
        onCreateRequested: @escaping () -> Void,
        onRetryRequested: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.isPresented = isPresented
        self.failureState = failureState
        self.body = body
        self.onBodyEdited = onBodyEdited
        self.onCreateRequested = onCreateRequested
        self.onRetryRequested = onRetryRequested
        // Body uses the serif notebook stack — content typography per
        // CLAUDE.md ("Notebook content: New York serif").
        self.bodyFont = .system(.body, design: .serif)
        self.bodyColor = ds.colors.ink
        self.headlineFont = .system(.title2, design: .serif)
        self.subheadFont = .system(.subheadline, design: .default)
        self.secondaryColor = ds.colors.ink2
        self.emptyNoteHeadline = AppStrings.TextEditing.emptyNoteHeadline
        self.emptyNoteSubhead = AppStrings.TextEditing.emptyNoteSubhead
        self.decodeFailureHeadline = AppStrings.TextEditing.bodyDecodeFailedHeadline
        self.decodeFailureSubhead = AppStrings.TextEditing.bodyDecodeFailedSubhead
        self.accessibilityHint = AppStrings.TextEditing.blockAccessibilityHint
    }
}
