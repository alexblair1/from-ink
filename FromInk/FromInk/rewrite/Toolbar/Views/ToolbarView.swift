import SwiftUI

/// Feature view for the toolbar. No TCA imports.
/// Renders zones from a Model built by the wiring layer.
///
struct ToolbarView: View {
    let model: Model

    var body: some View {
        VStack(spacing: 0) {
            ForEach(model.zones) { zone in
                if zone.id != model.zones.first?.id && !zone.items.isEmpty {
                    HairlineRule()
                }

                ForEach(zone.items) { item in
                    switch item {
                    case .toolButton(let buttonModel):
                        ToolButtonView(model: buttonModel)
                    case .actionButton(let buttonModel):
                        ActionButtonView(model: buttonModel)
                    case .dragHandle(let handleModel):
                        DragHandleView(model: handleModel)
                    }
                }
            }
        }
        .frame(width: model.width)
        .background(model.background)
        .overlay(alignment: model.borderAlignment) {
            Rectangle()
                .fill(model.borderColor)
                .frame(width: model.borderWidth)
        }
    }
}

// MARK: - Model

extension ToolbarView {
    struct Model {
        let zones: [Zone]
        let borderAlignment: Alignment
        let width: CGFloat
        let background: Color
        let borderColor: Color
        let borderWidth: CGFloat

        struct Zone: Identifiable {
            let id: String
            let items: [Item]
        }

        enum Item: Identifiable {
            case toolButton(ToolButtonView.Model)
            case actionButton(ActionButtonView.Model)
            case dragHandle(DragHandleView.Model)

            var id: String {
                switch self {
                case .toolButton(let m): 
                    "tool-\(m.id)"
                case .actionButton(let m): 
                    "action-\(m.id)"
                case .dragHandle: 
                    "handle"
                }
            }
        }
    }
}

// MARK: - Model init

extension ToolbarView.Model {
    init(
        zones: [Zone],
        side: ToolbarSide,
        ds: DesignSystem = .standard
    ) {
        self.zones = zones
        self.borderAlignment = side == .left ? .trailing : .leading
        self.width = ds.layout.toolbarWidth
        self.background = ds.colors.paper
        self.borderColor = ds.colors.rule
        self.borderWidth = ds.layout.borderWidth
    }
}
