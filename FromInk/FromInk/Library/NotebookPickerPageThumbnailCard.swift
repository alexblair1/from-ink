import SwiftUI

/// Single page thumbnail rendered inside the picker's expanded "Specific
/// page" grid. Snapshot-based — accepts an optional `Data` blob (rendered
/// thumbnail JPEG) and falls back to a paper-colored placeholder when
/// no thumbnail exists yet.
///
/// Layout: thumbnail rectangle (hairline border, sharp corners) with the
/// page number ("Page 3") in mono caption underneath.
///
struct NotebookPickerPageThumbnailCard: View {
    let model: Model

    var body: some View {
        Button(action: model.onTap) {
            VStack(alignment: .leading, spacing: model.spacing) {
                thumbnail
                Text(model.caption)
                    .font(model.captionFont)
                    .foregroundStyle(model.captionColor)
                    .lineLimit(1)
            }
            .frame(width: model.cardWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            model.placeholderColor

            if let image = model.thumbnail {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: model.thumbnailWidth, height: model.thumbnailHeight)
        .clipped()
        .overlay(
            Rectangle().strokeBorder(model.borderColor, lineWidth: model.borderWidth)
        )
    }
}

// MARK: - Model

extension NotebookPickerPageThumbnailCard {
    struct Model: Equatable {
        let id: UUID
        let caption: String
        let accessibilityLabel: String
        /// Pre-decoded `Image` so the view stays cheap on every render.
        /// The adapter decodes once from `Data?` at Model construction.
        let thumbnail: Image?
        let onTap: () -> Void

        let cardWidth: CGFloat
        let thumbnailWidth: CGFloat
        let thumbnailHeight: CGFloat
        let placeholderColor: Color
        let borderColor: Color
        let borderWidth: CGFloat
        let spacing: CGFloat

        let captionFont: Font
        let captionColor: Color

        static func == (lhs: Model, rhs: Model) -> Bool {
            lhs.id == rhs.id
                && lhs.caption == rhs.caption
                && lhs.thumbnailWidth == rhs.thumbnailWidth
                && lhs.thumbnailHeight == rhs.thumbnailHeight
        }
    }
}

// MARK: - Model init

extension NotebookPickerPageThumbnailCard.Model {
    init(
        snapshot: NotePageSnapshot,
        caption: String,
        accessibilityLabel: String,
        onTap: @escaping () -> Void,
        ds: DesignSystem = .standard
    ) {
        self.id = snapshot.id
        self.caption = caption
        self.accessibilityLabel = accessibilityLabel
        // Decode once at Model construction; the view receives a ready
        // `Image`. UIImage decode-on-demand from `Data` inside a view
        // body would re-decode on every SwiftUI diff.
        if let data = snapshot.thumbnailData, let uiImage = UIImage(data: data) {
            self.thumbnail = Image(uiImage: uiImage)
        } else {
            self.thumbnail = nil
        }
        self.onTap = onTap

        self.cardWidth = 96
        self.thumbnailWidth = 96
        // 4:5 portrait — matches the notebook page aspect ratio our
        // canvas defaults to. Tweak in DS later if needed.
        self.thumbnailHeight = 120
        self.placeholderColor = ds.colors.paper
        self.borderColor = ds.colors.rule
        self.borderWidth = ds.layout.borderWidth
        self.spacing = ds.spacing.xs

        self.captionFont = .system(size: 10, weight: .regular, design: .monospaced)
        self.captionColor = ds.colors.ink3
    }
}
