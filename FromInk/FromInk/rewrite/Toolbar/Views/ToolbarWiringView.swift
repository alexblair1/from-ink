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
        // Build the rendered Zone for each config, then bucket by
        // placement so the view layer can lay out pinned-top /
        // flexible-middle / pinned-bottom regions independently.
        let viewZones: [(ToolbarZoneConfig.Placement, ToolbarView.Model.Zone)] = zones.compactMap { zone in
            let items: [ToolbarView.Model.Item] = zone.items.compactMap { item in
                Self.resolveItem(item, store: store)
            }
            guard !items.isEmpty else { return nil }
            return (zone.placement, ToolbarView.Model.Zone(id: zone.id, items: items))
        }

        let pinnedTop = viewZones.filter { $0.0 == .pinnedTop }.map { $0.1 }
        let flexible = viewZones.filter { $0.0 == .flexible }.map { $0.1 }
        let pinnedBottom = viewZones.filter { $0.0 == .pinnedBottom }.map { $0.1 }

        self.init(
            pinnedTopZones: pinnedTop,
            flexibleZones: flexible,
            pinnedBottomZones: pinnedBottom,
            side: store.side
        )
    }

    private static func resolveItem(
        _ item: ToolbarZoneItem,
        store: StoreOf<ToolbarFeature>
    ) -> ToolbarView.Model.Item? {
        switch item {
        case .tool(let descriptor):
            let isActive = store.activeToolID == descriptor.id
            let icon = store.toolSettings[id: descriptor.id]?.settings.penType.icon
                ?? descriptor.icon
            let ds = DesignSystem.standard

            return .toolButton(
                ToolButtonView.Model(
                    id: descriptor.id.rawValue,
                    icon: icon,
                    onTap: { store.send(.toolTapped(descriptor.id)) },
                    foreground: isActive ? ds.colors.paperPure : ds.colors.inkPure,
                    background: isActive ? ds.colors.inkPure : .clear
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
                        case .dispatch: store.send(.dispatchTapped)
                        }
                    }
                )
            )

        case .bolt:
            guard store.isBoltVisible else { return nil }
            return .actionButton(
                ActionButtonView.Model(
                    id: "bolt",
                    icon: "sparkles.rectangle.stack",
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
}
