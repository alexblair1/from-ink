import Foundation
import SwiftData

/// Schema migration plan for the synced container. Empty stages today —
/// `FromInkSchemaV1` is the initial version. Future stages will go here.
///
/// CloudKit requires `.lightweight` migrations only; custom stages do
/// not work reliably once sync is enabled (see `data_model_edd.md` §9.2).
/// When the model graph changes after Phase 3 lock-in, never remove or
/// rename properties — deprecate (stop writing, ignore on read) and add
/// replacement properties.
enum FromInkMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [FromInkSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
