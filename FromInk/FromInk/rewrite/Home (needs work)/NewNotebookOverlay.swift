import SwiftUI

/// Branded new-notebook dialog — a centered card on a dimmed backdrop.
///
/// Sharp corners, hairline ink border, editorial typography.
/// Replaces the system sheet to keep the From Ink identity consistent.
///
/// **Type picker.** A second row below the title input lets the user
/// pick the notebook variant: `Notebook` (ink + handwriting, the
/// default) or `Text Note` (typed text only). The preview thumbnail
/// updates with the selection so the user sees what they're about to
/// create — the spine + page composition for ink notebooks, and a
/// typed-text mockup for text notes.
struct NewNotebookOverlay: View {
    @Binding var title: String
    @Binding var type: NotebookType
    let onCreate: () -> Void
    let onCancel: () -> Void

    private let ds = DesignSystem.standard
    @FocusState private var isFocused: Bool

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        ZStack {
            // Scrim
            ds.colors.ink.opacity(ds.layout.scrimOpacity)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            // Card
            VStack(alignment: .leading, spacing: 0) {
                header
                HairlineRule()
                notebookInput
                HairlineRule()
                typePicker
                HairlineRule()
                actions
            }
            .frame(width: ds.layout.dialogWidth)
            .background(ds.colors.paper)
            .overlay(
                Rectangle().strokeBorder(ds.colors.ink, lineWidth: ds.layout.borderWidth)
            )
        }
        .onAppear {
            title = ""
            type = .notebook
            isFocused = true
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            MonoLabel(AppStrings.Home.newNotebook, color: ds.colors.ink2)
            Spacer()
            IconButton("xmark", size: .footnote, color: ds.colors.ink2, action: onCancel)
        }
        .padding(.horizontal, ds.spacing.base)
        .frame(height: ds.spacing.xxl)
    }

    // MARK: - Notebook input

    private var notebookInput: some View {
        HStack(spacing: ds.spacing.base) {
            notebookPreview

            VStack(alignment: .leading, spacing: ds.spacing.xs) {
                MonoLabel(AppStrings.Home.titleLabel, size: 9, color: ds.colors.ink3)

                TextField(AppStrings.Common.untitled, text: $title)
                    .font(ds.typography.inputTitle)
                    .foregroundStyle(ds.colors.ink)
                    .focused($isFocused)
                    .onSubmit { onCreate() }
            }
        }
        .padding(ds.spacing.base)
    }

    // MARK: - Notebook preview

    @ViewBuilder
    private var notebookPreview: some View {
        switch type {
        case .notebook, .quickSheet:
            inkNotebookPreview
        case .textNote:
            textNotePreview
        }
    }

    private var inkNotebookPreview: some View {
        ZStack {
            ds.colors.paper

            HStack(spacing: 0) {
                Rectangle()
                    .fill(ds.colors.ink)
                    .frame(width: ds.layout.notebookSpineWidth)
                Rectangle()
                    .fill(ds.colors.paper)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(ds.colors.ink2)
                            .frame(width: ds.layout.borderWidth)
                            .padding(.leading, ds.spacing.sm)
                    }
            }
            .padding(ds.spacing.md)
        }
        .frame(width: ds.layout.thumbnailSize, height: 84)
        .overlay(
            Rectangle().strokeBorder(ds.colors.rule, lineWidth: ds.layout.borderWidth)
        )
    }

    /// Stylized preview for the textNote variant — a few typeset lines
    /// to communicate "typed text, not a paper-and-ink page."
    private var textNotePreview: some View {
        ZStack {
            ds.colors.paper

            VStack(alignment: .leading, spacing: ds.spacing.xs) {
                Rectangle()
                    .fill(ds.colors.ink)
                    .frame(height: 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, ds.spacing.xxl)
                Rectangle()
                    .fill(ds.colors.ink3)
                    .frame(height: 2)
                Rectangle()
                    .fill(ds.colors.ink3)
                    .frame(height: 2)
                Rectangle()
                    .fill(ds.colors.ink3)
                    .frame(height: 2)
                    .padding(.trailing, ds.spacing.lg)
            }
            .padding(ds.spacing.md)
        }
        .frame(width: ds.layout.thumbnailSize, height: 84)
        .overlay(
            Rectangle().strokeBorder(ds.colors.rule, lineWidth: ds.layout.borderWidth)
        )
    }

    // MARK: - Type picker

    private var typePicker: some View {
        VStack(alignment: .leading, spacing: ds.spacing.xs) {
            MonoLabel(AppStrings.Home.typeLabel, size: 9, color: ds.colors.ink3)

            HStack(spacing: 0) {
                typeOption(.notebook, label: AppStrings.Home.notebookTypeNotebook)
                Rectangle()
                    .fill(ds.colors.rule)
                    .frame(width: ds.layout.borderWidth)
                typeOption(.textNote, label: AppStrings.Home.notebookTypeTextNote)
            }
            .overlay(
                Rectangle().strokeBorder(ds.colors.rule, lineWidth: ds.layout.borderWidth)
            )
        }
        .padding(ds.spacing.base)
    }

    private func typeOption(_ option: NotebookType, label: String) -> some View {
        let selected = type == option
        return Button {
            type = option
        } label: {
            Text(label)
                .font(ds.typography.subheadline)
                .foregroundStyle(selected ? ds.colors.paperOnInk : ds.colors.ink2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, ds.spacing.sm)
                .background(selected ? ds.colors.ink : ds.colors.paper)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 0) {
            Button(action: onCancel) {
                Text(AppStrings.Common.cancel)
                    .font(ds.typography.subheadline)
                    .foregroundStyle(ds.colors.ink2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ds.spacing.base)
            }
            .buttonStyle(.plain)

            HairlineRule(.vertical)

            Button(action: onCreate) {
                HStack(spacing: ds.spacing.sm) {
                    Text(AppStrings.Home.createAndOpen)
                        .font(ds.typography.buttonLabel)
                    Image(systemName: "arrow.right")
                        .font(ds.typography.caption)
                }
                .foregroundStyle(ds.colors.paperOnInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, ds.spacing.base)
                .background(ds.colors.ink)
            }
            .buttonStyle(.plain)
        }
        .frame(height: ds.layout.sheetHeaderHeight)
    }
}
