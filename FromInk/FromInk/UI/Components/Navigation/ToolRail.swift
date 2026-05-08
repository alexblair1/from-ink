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
                        .font(.system(size: model.style.iconSize, weight: isSelected ? .medium : .regular))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(isSelected ? model.style.selectedForeground : model.style.unselectedForeground)
                        .frame(width: model.style.toolSize, height: model.style.toolSize)
                        .background(isSelected ? model.style.selectedBackground : .clear)
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
                        .padding(.horizontal, model.style.ruleSpacing)
                }
            }
        }
        .padding(.vertical, model.style.railPadding)
        .background(.thickMaterial)
        .overlay(
            HairlineRule(.vertical),
            alignment: model.edge == .leading ? .trailing : .leading
        )
    }
}

extension ToolRail {
    struct Style {
        let iconSize: CGFloat
        let selectedForeground: Color
        let unselectedForeground: Color
        let selectedBackground: Color
        let toolSize: CGFloat
        let railPadding: CGFloat
        let ruleSpacing: CGFloat

        static let standard = Style(
            iconSize: 22,
            selectedForeground: ColorTokens.standard.paperOnInk,
            unselectedForeground: ColorTokens.standard.ink,
            selectedBackground: ColorTokens.standard.ink,
            toolSize: LayoutTokens.standard.toolHitTarget,
            railPadding: SpacingScale.standard.xs,
            ruleSpacing: SpacingScale.standard.sm
        )
    }

    struct Model {
        let tools: [Tool]
        let selectedID: String
        let edge: HorizontalEdge
        let onSelect: (String) -> Void
        let onDoubleTap: ((String) -> Void)?
        let style: Style

        init(
            tools: [Tool],
            selectedID: String,
            edge: HorizontalEdge = .leading,
            onSelect: @escaping (String) -> Void,
            onDoubleTap: ((String) -> Void)? = nil,
            style: Style = .standard
        ) {
            self.tools = tools
            self.selectedID = selectedID
            self.edge = edge
            self.onSelect = onSelect
            self.onDoubleTap = onDoubleTap
            self.style = style
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
