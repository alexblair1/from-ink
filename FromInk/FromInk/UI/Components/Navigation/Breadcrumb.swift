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
        HStack(spacing: 4) {
            ForEach(Array(model.segments.enumerated()), id: \.offset) { index, segment in
                if index > 0 {
                    MonoLabel("›", size: 11, color: Color("ink/Ink3"))
                }

                if let onTap = segment.onTap {
                    Button(action: onTap) {
                        MonoLabel(segment.label, color: Color("ink/Ink2"))
                    }
                    .buttonStyle(.plain)
                } else {
                    MonoLabel(segment.label, color: Color("ink/Ink"))
                }
            }
        }
    }
}

extension Breadcrumb {
    struct Model {
        let segments: [Segment]

        init(segments: [Segment]) {
            self.segments = segments
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
