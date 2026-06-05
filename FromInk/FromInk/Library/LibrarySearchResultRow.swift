import SwiftUI

/// Single tappable row inside the library search / browse list. One
/// component handles all three kinds; the icon + kind chip + meta line
/// resolve at adapter time from the underlying snapshot.
///
/// Component view: zero TCA imports, no `@Environment(\.ds)`. Reads
/// flat fields off the Model.
///
struct LibrarySearchResultRow: View {
    let model: Model

    var body: some View {
        Button(action: model.onTap) {
            HStack(alignment: .top, spacing: model.spacing) {
                icon
                VStack(alignment: .leading, spacing: model.titleSpacing) {
                    HStack(spacing: model.titleSpacing) {
                        Text(model.title)
                            .font(model.titleFont)
                            .foregroundStyle(model.titleColor)
                            .lineLimit(1)
                        kindChip
                    }
                    Text(model.metaText)
                        .font(model.metaFont)
                        .foregroundStyle(model.metaColor)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, model.horizontalPadding)
            .padding(.vertical, model.verticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var icon: some View {
        Image(systemName: model.iconSystemName)
            .font(.system(size: model.iconSize, weight: .regular))
            .foregroundStyle(model.iconColor)
            .frame(width: model.iconFrame, height: model.iconFrame)
    }

    private var kindChip: some View {
        // `kindLabel` is already uppercase from AppStrings (matches the
        // existing `library.folderCount` / `library.notebookCount`
        // convention) — no need for `.textCase(.uppercase)` here.
        Text(model.kindLabel)
            .font(model.kindFont)
            .foregroundStyle(model.kindColor)
            .tracking(model.kindTracking)
            .padding(.horizontal, model.kindHorizontalPadding)
            .padding(.vertical, model.kindVerticalPadding)
            .overlay(
                Rectangle().strokeBorder(model.kindBorderColor, lineWidth: model.kindBorderWidth)
            )
    }
}

// MARK: - Model

extension LibrarySearchResultRow {
    struct Model: Equatable, Identifiable {
        let id: UUID
        let title: String
        let metaText: String
        let kindLabel: String
        let iconSystemName: String
        let onTap: () -> Void

        let iconSize: CGFloat
        let iconFrame: CGFloat
        let iconColor: Color

        let titleFont: Font
        let titleColor: Color
        let titleSpacing: CGFloat

        let metaFont: Font
        let metaColor: Color

        let kindFont: Font
        let kindColor: Color
        let kindBorderColor: Color
        let kindBorderWidth: CGFloat
        let kindTracking: CGFloat
        let kindHorizontalPadding: CGFloat
        let kindVerticalPadding: CGFloat

        let spacing: CGFloat
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat

        static func == (lhs: Model, rhs: Model) -> Bool {
            lhs.id == rhs.id
                && lhs.title == rhs.title
                && lhs.metaText == rhs.metaText
                && lhs.kindLabel == rhs.kindLabel
                && lhs.iconSystemName == rhs.iconSystemName
        }
    }
}

// MARK: - Model init from a search result

extension LibrarySearchResultRow.Model {
    /// Builds the row Model from a `LibrarySearchResult`. The adapter
    /// supplies the tap handler; everything else is resolved here so
    /// the wiring view stays a single map line.
    init(
        result: LibrarySearchResult,
        onTap: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.id = result.id
        self.title = result.title
        self.onTap = onTap

        switch result {
        case .notebook(let snap):
            self.iconSystemName = "book.closed"
            self.kindLabel = AppStrings.LibrarySearch.kindNotebook
            self.metaText = AppStrings.LibrarySearch.pageCount(snap.pageCount)
        case .folder(let snap):
            self.iconSystemName = "folder"
            self.kindLabel = AppStrings.LibrarySearch.kindFolder
            self.metaText = AppStrings.LibrarySearch.notebookCount(snap.notebookCount)
        case .pdf(let snap):
            self.iconSystemName = "doc"
            self.kindLabel = AppStrings.LibrarySearch.kindPDF
            self.metaText = AppStrings.LibrarySearch.pageCount(snap.pageCount)
        }

        self.iconSize = 20
        self.iconFrame = ds.layout.iconFrame
        self.iconColor = ds.colors.ink

        self.titleFont = .system(.body, design: .serif)
        self.titleColor = ds.colors.ink
        self.titleSpacing = ds.spacing.xs

        self.metaFont = .system(size: 11, weight: .regular, design: .monospaced)
        self.metaColor = ds.colors.ink3

        self.kindFont = .system(size: 9, weight: .medium, design: .monospaced)
        self.kindColor = ds.colors.ink3
        self.kindBorderColor = ds.colors.rule
        self.kindBorderWidth = ds.layout.borderWidth
        self.kindTracking = 0.8
        self.kindHorizontalPadding = ds.spacing.sm
        self.kindVerticalPadding = 2

        self.spacing = ds.spacing.md
        self.horizontalPadding = ds.spacing.lg
        self.verticalPadding = ds.spacing.md
    }
}
