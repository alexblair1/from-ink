import SwiftUI

/// Branded new-notebook dialog — a centered card on a dimmed backdrop.
///
/// Sharp corners, hairline ink border, editorial typography.
/// Replaces the system sheet to keep the From Ink identity consistent.
///
struct NewNotebookOverlay: View {
    @Binding var title: String
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
            ds.colors.ink.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            // Card
            VStack(alignment: .leading, spacing: 0) {
                // Header
                header

                HairlineRule()

                // Notebook preview + title field
                notebookInput

                HairlineRule()

                // Actions
                actions
            }
            .frame(width: 380)
            .background(ds.colors.paper)
            .overlay(
                Rectangle().strokeBorder(ds.colors.ink, lineWidth: 1)
            )
        }
        .onAppear {
            title = ""
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
            // Mini notebook illustration
            notebookPreview

            // Title field
            VStack(alignment: .leading, spacing: 6) {
                MonoLabel(AppStrings.Home.titleLabel, size: 9, color: ds.colors.ink3)

                TextField(AppStrings.Common.untitled, text: $title)
                    .font(.system(size: 20, weight: .regular, design: .serif))
                    .foregroundStyle(ds.colors.ink)
                    .focused($isFocused)
                    .onSubmit { onCreate() }
            }
        }
        .padding(ds.spacing.base)
    }

    // MARK: - Notebook preview

    private var notebookPreview: some View {
        ZStack {
            ds.colors.paper

            HStack(spacing: 0) {
                Rectangle()
                    .fill(ds.colors.ink)
                    .frame(width: 6)
                Rectangle()
                    .fill(ds.colors.paper)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(ds.colors.ink.opacity(0.85))
                            .frame(width: 1)
                            .padding(.leading, ds.spacing.sm)
                    }
            }
            .padding(ds.spacing.md)
        }
        .frame(width: ds.layout.thumbnailSize, height: 84)
        .overlay(
            Rectangle().strokeBorder(ds.colors.rule, lineWidth: 0.5)
        )
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 0) {
            // Cancel
            Button(action: onCancel) {
                Text(AppStrings.Common.cancel)
                    .font(ds.typography.subheadline)
                    .foregroundStyle(ds.colors.ink2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, ds.spacing.base)
            }
            .buttonStyle(.plain)

            HairlineRule(.vertical)

            // Create & Open
            Button(action: onCreate) {
                HStack(spacing: ds.spacing.sm) {
                    Text(AppStrings.Home.createAndOpen)
                        .font(.system(size: 15, weight: .medium))
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
        .frame(height: 52)
    }
}
