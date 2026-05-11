import SwiftUI
import ComposableArchitecture

/// Wiring view that converts StoreOf<ToolbarFeature> into a ToolbarView.Model.
/// Contains zero layout — exactly one expression in the body.
///
struct ToolbarWiringView: View {
    let store: StoreOf<ToolbarFeature>
    let zones: [ToolbarZoneConfig]

    init(
        store: StoreOf<ToolbarFeature>,
        zones: [ToolbarZoneConfig] = ToolbarZoneConfig.standard()
    ) {
        self.store = store
        self.zones = zones
    }

    var body: some View {
        ToolbarView(model: .init(store: store, zones: zones))
    }
}

// MARK: - Adapter

extension ToolbarView.Model {
    init(store: StoreOf<ToolbarFeature>, zones: [ToolbarZoneConfig]) {
        let viewZones = zones.map { zone in
            let items: [ToolbarView.Model.Item] = zone.items.compactMap { item in
                switch item {
                case .tool(let descriptor):
                    let isActive = store.activeToolID == descriptor.id
                    let icon = store.toolSettings[id: descriptor.id]?.settings.penType.icon ?? descriptor.icon
                    let ds = DesignSystem.standard

                    return .toolButton(
                        ToolButtonView.Model(
                            id: descriptor.id.rawValue,
                            icon: icon,
                            onTap: { store.send(.toolTapped(descriptor.id)) },
                            foreground: isActive ? ds.colors.paperOnInk : ds.colors.ink2,
                            background: isActive ? ds.colors.ink : .clear
                        )
                    )
                    
                case .action(let actionID, let icon):
                    return .actionButton(
                        ActionButtonView.Model(
                            id: actionID.rawValue,
                            icon: icon,
                            onTap: {
                                switch actionID {
                                case .undo: store.send(.undoTapped)
                                case .redo: store.send(.redoTapped)
                                case .template: store.send(.templatePickerToggled)
                                case .settings: store.send(.settingsToggled)
                                }
                            }
                        )
                    )
                    
                case .bolt:
                    guard store.isBoltVisible else { return nil }
                    
                    return .actionButton(
                        ActionButtonView.Model(
                            id: "bolt",
                            icon: "bolt.fill",
                            onTap: { store.send(.analyzeTapped) }
                        )
                    )
                    
                case .dragHandle:
                    return .dragHandle(
                        DragHandleView.Model(
                            onDragEnded: { side in
                                store.send(.sideChanged(side))
                            }
                        )
                    )
                }
            }
            
            return ToolbarView.Model.Zone(id: zone.id, items: items)
        }
        .filter { !$0.items.isEmpty }
        
        self.init(zones: viewZones, side: store.side)
    }
}
