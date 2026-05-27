import SwiftUI

/// Feature view for the toolbar. No TCA imports.
///
/// The rail stretches edge-to-edge vertically. Zones tagged `pinnedTop`
/// hug the top, `pinnedBottom` zones hug the bottom, and `flexible`
/// zones live in a scrollable middle so the writing tools stay reachable
/// even on a short iPhone screen. On tall iPads where everything fits,
/// `.scrollBounceBehavior(.basedOnSize)` suppresses rubber-banding.
struct ToolbarView: View {
    let model: Model

    var body: some View {
        VStack(spacing: 0) {
            zonesGroup(model.pinnedTopZones)

            if model.showsTopBoundaryRule {
                HairlineRule()
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    zonesGroup(model.flexibleZones)
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            if model.showsBottomBoundaryRule {
                HairlineRule()
            }

            zonesGroup(model.pinnedBottomZones)
        }
        .frame(width: model.width)
        .frame(maxHeight: .infinity)
        .background(model.background)
        .overlay(alignment: model.borderAlignment) {
            Rectangle()
                .fill(model.borderColor)
                .frame(width: model.borderWidth)
        }
    }

    @ViewBuilder
    private func zonesGroup(_ zones: [Model.Zone]) -> some View {
        ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
            if index > 0 && !zone.items.isEmpty {
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
}

// MARK: - Model

extension ToolbarView {
    struct Model {
        let pinnedTopZones: [Zone]
        let flexibleZones: [Zone]
        let pinnedBottomZones: [Zone]
        let showsTopBoundaryRule: Bool
        let showsBottomBoundaryRule: Bool
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
        pinnedTopZones: [Zone],
        flexibleZones: [Zone],
        pinnedBottomZones: [Zone],
        side: ToolbarSide,
        ds: DesignSystem = .standard
    ) {
        self.pinnedTopZones = pinnedTopZones
        self.flexibleZones = flexibleZones
        self.pinnedBottomZones = pinnedBottomZones
        self.showsTopBoundaryRule = !pinnedTopZones.isEmpty && !flexibleZones.isEmpty
        self.showsBottomBoundaryRule = !flexibleZones.isEmpty && !pinnedBottomZones.isEmpty
        self.borderAlignment = side == .left ? .trailing : .leading
        self.width = ds.layout.toolbarWidth
        self.background = ds.colors.paper
        self.borderColor = ds.colors.rule
        self.borderWidth = ds.layout.borderWidth
    }
}
