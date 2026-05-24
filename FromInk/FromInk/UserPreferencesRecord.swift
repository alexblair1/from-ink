import Foundation
import SwiftData

/// Per-device user preferences that should NEVER sync across devices —
/// toolbar handedness, last-opened notebook, finger drawing toggle.
/// Lives in a separate local-only `ModelContainer` configured with
/// `cloudKitDatabase: .none` forever (per `data_model_edd.md` §9).
///
/// **Naming note:** the existing TCA `UserPreferences` dependency struct
/// at `App/UserPreferencesDependency.swift` keeps its name. This
/// `@Model` is `UserPreferencesRecord` to avoid the collision. Migrating
/// the TCA dep onto this record is a separate ticket — the schema lands
/// now so that future migration doesn't break the CloudKit-readiness
/// gate or require schema versioning of the local container.
@Model final class UserPreferencesRecord {
    var id: UUID = UUID()
    var handednessRaw: String = Handedness.right.rawValue
    var toolbarSideRaw: String = ToolbarSide.left.rawValue
    var fingerDrawingEnabled: Bool = false
    var lastOpenedNotebookID: UUID?

    init(id: UUID = UUID()) {
        self.id = id
    }

    var handedness: Handedness {
        get { Handedness(rawValue: handednessRaw) ?? .right }
        set { handednessRaw = newValue.rawValue }
    }

    var toolbarSide: ToolbarSide {
        get { ToolbarSide(rawValue: toolbarSideRaw) ?? .left }
        set { toolbarSideRaw = newValue.rawValue }
    }
}
