import SwiftUI

/// Breadcrumb trail for hierarchical navigation. Tappable path segments.
///
///     Breadcrumb(model: .init(
///         segments: [
///             .init(label: "Library", onTap: goToLibrary),
///             .init(label: "Work", onTap: goToFolder),
///             .init(label: "Sprint Notes"),
///         ]
///     ))
///
struct Breadcrumb: View {

    let model: Model

    var body: some View {
        HStack(spacing: SpacingScale.standard.xs) {
            ForEach(Array(model.segments.enumerated()), id: \.offset) { index, segment in
                if index > 0 {
                    MonoLabel("\u{203A}", size: 11, color: model.style.separatorColor)
                }

                if let onTap = segment.onTap {
                    Button(action: onTap) {
                        MonoLabel(segment.label)
                    }
                    .buttonStyle(.plain)
                } else {
                    MonoLabel(segment.label, color: model.style.activeColor)
                }
            }
        }
    }
}

extension Breadcrumb {
    struct Style {
        let separatorColor: Color
        let activeColor: Color

        static let standard = Style(
            separatorColor: ColorTokens.standard.ink3,
            activeColor: ColorTokens.standard.ink
        )
    }

    struct Model {
        let segments: [Segment]
        let style: Style

        init(segments: [Segment], style: Style = .standard) {
            self.segments = segments
            self.style = style
        }
    }

    struct Segment {
        let label: String
        let onTap: (() -> Void)?

        init(label: String, onTap: (() -> Void)? = nil) {
            self.label = label
            self.onTap = onTap
        }
    }
}
