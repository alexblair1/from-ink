import Foundation

/// A vertical group of items in the toolbar, separated by hairline rules.
///
struct ToolbarZoneConfig: Equatable, Sendable {
    let id: String
    let items: [ToolbarZoneItem]
}

/// A single item within a toolbar zone.
///
enum ToolbarZoneItem: Equatable, Sendable {
    case tool(ToolDescriptor)
    case action(ToolbarActionID, icon: String)
    case bolt
    case dragHandle
}

// MARK: - Default configuration

extension ToolbarZoneConfig {
    static func standard() -> [ToolbarZoneConfig] {
        [
            ToolbarZoneConfig(id: "handle", items: [.dragHandle]),
            ToolbarZoneConfig(id: "bolt", items: [.bolt]),
            ToolbarZoneConfig(id: "writing", items:
                ToolDescriptor.allWritingTools.map { .tool($0) }
            ),
            ToolbarZoneConfig(id: "actions", items: [
                .action(.undo, icon: "arrow.uturn.backward"),
                .action(.redo, icon: "arrow.uturn.forward"),
                .action(.template, icon: "square.grid.3x3"),
                .action(.settings, icon: "gearshape"),
            ]),
        ]
    }
}
