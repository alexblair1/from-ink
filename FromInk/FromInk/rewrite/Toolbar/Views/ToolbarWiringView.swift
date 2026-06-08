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
        // Resolve each configured zone item into a concrete view item.
        // Items that the current store state hides (e.g. bolt when
        // `isBoltVisible == false`) drop out via the compactMap; the
        // drag handle is hoisted out of the items stream and pinned to
        // the top of the top capsule.
        var dragHandle: DragHandleView.Model?
        var topItems: [ToolbarView.Model.Item] = []
        var bottomItems: [ToolbarView.Model.Item] = []

        for zone in zones {
            for item in zone.items {
                switch item {
                case .dragHandle:
                    dragHandle = DragHandleView.Model(
                        onDragEnded: { side in store.send(.sideChanged(side)) }
                    )

                case .tool(let descriptor):
                    let isActive = store.activeToolID == descriptor.id
                    let icon = store.toolSettings[id: descriptor.id]?.settings.penType.icon
                        ?? descriptor.icon
                    let toolItem: ToolbarView.Model.Item = .toolButton(
                        ToolButtonView.Model(
                            id: descriptor.id.rawValue,
                            icon: icon,
                            onTap: { store.send(.toolTapped(descriptor.id)) },
                            isActive: isActive
                        )
                    )
                    Self.appendItem(toolItem, to: zone.placement,
                                    top: &topItems, bottom: &bottomItems)

                case .action(let actionID, let icon):
                    let actionItem: ToolbarView.Model.Item = .actionButton(
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
                    Self.appendItem(actionItem, to: zone.placement,
                                    top: &topItems, bottom: &bottomItems)

                case .bolt:
                    guard store.isBoltVisible else { continue }
                    let boltItem: ToolbarView.Model.Item = .actionButton(
                        ActionButtonView.Model(
                            id: "bolt",
                            icon: "sparkles.rectangle.stack",
                            onTap: { store.send(.analyzeTapped) }
                        )
                    )
                    Self.appendItem(boltItem, to: zone.placement,
                                    top: &topItems, bottom: &bottomItems)
                }
            }
        }

        // Ink readout reads from the active settings. Hidden until the
        // user-preferences-load Effect resolves (`activeSettings` is still
        // `.default`, which doesn't carry meaningful "active" semantics
        // until tools are loaded). Showing it always is fine — the
        // default settings render as a HB graphite chip at the smallest
        // pip size, which is a reasonable rest state.
        let readout = InkReadoutView.Model(
            settings: store.activeSettings,
            accessibilityLabel: ""  // TODO: localized "Active ink: …" via AppStrings
        )

        self.init(
            dragHandle: dragHandle,
            topItems: topItems,
            inkReadout: readout,
            bottomItems: bottomItems,
            side: store.side
        )
    }

    /// Routes a resolved item into the top or bottom capsule based on
    /// its zone placement. `.pinnedTop` and `.flexible` zones live in
    /// the top capsule (the top capsule scrolls when squeezed);
    /// `.pinnedBottom` lives in the bottom capsule (priority — always
    /// fully visible).
    private static func appendItem(
        _ item: ToolbarView.Model.Item,
        to placement: ToolbarZoneConfig.Placement,
        top: inout [ToolbarView.Model.Item],
        bottom: inout [ToolbarView.Model.Item]
    ) {
        switch placement {
        case .pinnedTop, .flexible:
            top.append(item)
        case .pinnedBottom:
            bottom.append(item)
        }
    }
}
