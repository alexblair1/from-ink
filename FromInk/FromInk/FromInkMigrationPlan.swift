import Foundation
import SwiftData

/// Schema migration plan for the synced container.
///
/// **IMPORTANT: this plan is NOT passed to `ModelContainer` today.** See
/// `AppDependencyContainer.modelContainer` — the container is constructed
/// without `migrationPlan:` so SwiftData's default lightweight migration
/// handles additive changes during Phase 1 development. Passing this
/// plan with empty stages would tell SwiftData "no migrations defined,
/// reject any schema mismatch" — blocking even lightweight migration
/// and producing "no such table" errors.
///
/// **When to wire this in:**
/// 1. Phase 2: model graph stable for 2+ weeks, CloudKit deploy pending.
/// 2. Add the first `MigrationStage` (must be `.lightweight` per
///    `data_model_edd.md` §9.2 — custom stages don't sync-migrate
///    reliably with CloudKit).
/// 3. Update `AppDependencyContainer.modelContainer` to pass
///    `migrationPlan: FromInkMigrationPlan.self`.
///
/// **Schema-change discipline (post-launch):** never remove or rename
/// properties — deprecate (stop writing, ignore on read) and add
/// replacement properties.
enum FromInkMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [FromInkSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
