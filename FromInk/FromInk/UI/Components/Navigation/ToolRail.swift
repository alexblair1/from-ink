import SwiftUI

/// Vertical toolbar rail for canvas tools. Fixed to leading or trailing edge.
/// Thick material background with hairline border.
///
///     ToolRail(model: .init(
///         tools: [
///             .init(icon: "pencil.tip", id: "pen"),
///             .init(icon: "highlighter", id: "highlighter"),
///             .init(icon: "eraser", id: "eraser"),
///             .init(icon: "lasso", id: "lasso"),
///         ],
///         selectedID: "pen",
///         onSelect: { id in selectTool(id) },
///         onDoubleTap: { id in showOptions(id) }
///     ))
///
struct ToolRail: View {
    let model: Model

    var body: some View {
        VStack(spacing: 0) {
            ForEach(model.tools, id: \.id) { tool in
                let isSelected = model.selectedID == tool.id

                Button {
                    model.onSelect(tool.id)
                } label: {
                    Image(systemName: tool.icon)
                        .font(.system(size: 22, weight: isSelected ? .medium : .regular))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(isSelected ? Color("ink/Paper") : Color("ink/Ink"))
                        .frame(width: 48, height: 48)
                        .background(isSelected ? Color("ink/Ink") : .clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        model.onDoubleTap?(tool.id)
                    }
                )

                if tool.id != model.tools.last?.id {
                    HairlineRule()
                        .padding(.horizontal, 8)
                }
            }
        }
        .padding(.vertical, 4)
        .background(.thickMaterial)
        .overlay(
            HairlineRule(.vertical),
            alignment: model.edge == .leading ? .trailing : .leading
        )
    }
}

extension ToolRail {
    struct Model {
        let tools: [Tool]
        let selectedID: String
        let edge: HorizontalEdge
        let onSelect: (String) -> Void
        let onDoubleTap: ((String) -> Void)?

        init(
            tools: [Tool],
            selectedID: String,
            edge: HorizontalEdge = .leading,
            onSelect: @escaping (String) -> Void,
            onDoubleTap: ((String) -> Void)? = nil
        ) {
            self.tools = tools
            self.selectedID = selectedID
            self.edge = edge
            self.onSelect = onSelect
            self.onDoubleTap = onDoubleTap
        }
    }

    struct Tool: Equatable {
        let icon: String
        let id: String

        init(icon: String, id: String) {
            self.icon = icon
            self.id = id
        }
    }
}
