import Foundation

/// A vertical group of items in the toolbar, separated by hairline rules.
///
/// `placement` tells the view layer how to arrange the zone vertically.
/// `pinnedTop` and `pinnedBottom` zones hug the top and bottom edges of
/// the rail; `flexible` zones are collected into a single scrollable
/// region in the middle. On tall screens nothing scrolls; on iPhone the
/// flexible region scrolls so every tool stays reachable.
struct ToolbarZoneConfig: Equatable, Sendable {
    let id: String
    let placement: Placement
    let items: [ToolbarZoneItem]

    enum Placement: Equatable, Sendable {
        case pinnedTop
        case flexible
        case pinnedBottom
    }
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
        let actionItems: [ToolbarZoneItem] = [
            .action(.undo, icon: "arrow.uturn.backward"),
            .action(.redo, icon: "arrow.uturn.forward"),
            .action(.template, icon: "square.grid.3x3"),
            .action(.settings, icon: "gearshape"),
            .action(.dispatch, icon: "tray"),
        ]

        return [
            ToolbarZoneConfig(id: "handle", placement: .pinnedTop, items: [.dragHandle]),
            ToolbarZoneConfig(id: "bolt", placement: .flexible, items: [.bolt]),
            ToolbarZoneConfig(id: "writing", placement: .flexible, items:
                ToolDescriptor.allWritingTools.map { .tool($0) }
            ),
            ToolbarZoneConfig(id: "actions", placement: .pinnedBottom, items: actionItems),
        ]
    }
}
