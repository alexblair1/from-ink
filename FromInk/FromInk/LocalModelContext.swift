import ComposableArchitecture
import SwiftData
import Foundation

/// TCA dependency providing the LOCAL ModelContext — the container for
/// per-device data that must NEVER sync (toolbar handedness, last-opened
/// notebook ID, finger drawing toggle). See `data_model_edd.md` §9.
///
/// Parallel to `SyncedModelContextDependency` rather than two methods on
/// one struct: a reducer that touches user preferences never touches
/// synced data and vice versa, so a misuse (e.g., inserting a `Notebook`
/// into the local context) becomes a compile error rather than a silent
/// CloudKit failure when sync flips on in Phase 3.
struct LocalModelContextDependency: Sendable {
    var context: @Sendable @MainActor () -> ModelContext
    var warmup: @Sendable @MainActor () throws -> Void
}

// MARK: - Factories

extension LocalModelContextDependency {
    static func live(container: ModelContainer) -> LocalModelContextDependency {
        LocalModelContextDependency(
            context: { container.mainContext },
            warmup: { _ = container.mainContext }
        )
    }

    /// Unavailable fallback — in-memory container for degraded boot.
    /// Used by `AppDependencyContainer` when the on-disk local store
    /// fails to open. Must NOT be the `liveValue` — see notes there.
    static let unavailable: LocalModelContextDependency = inMemory()

    static let preview: LocalModelContextDependency = inMemory()

    static func inMemory() -> LocalModelContextDependency {
        let schema = Schema([UserPreferencesRecord.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try! ModelContainer(for: schema, configurations: config)
        return LocalModelContextDependency(
            context: { container.mainContext },
            warmup: { }
        )
    }
}

// MARK: - DependencyKey

extension LocalModelContextDependency: DependencyKey {
    /// CRITICAL: same rule as `SyncedModelContextDependency.liveValue` —
    /// no silent in-memory fallback. Crash loudly if accessed before
    /// `AppDependencyContainer.install(into:)` runs.
    static let liveValue: LocalModelContextDependency = LocalModelContextDependency(
        context: {
            fatalError("localModelContext.liveValue accessed before install. Call AppDependencyContainer.install(into:) at app launch.")
        },
        warmup: {
            fatalError("localModelContext.liveValue accessed before install. Call AppDependencyContainer.install(into:) at app launch.")
        }
    )

    static var testValue: LocalModelContextDependency { .inMemory() }
}

// MARK: - DependencyValues

extension DependencyValues {
    var localModelContext: LocalModelContextDependency {
        get { self[LocalModelContextDependency.self] }
        set { self[LocalModelContextDependency.self] = newValue }
    }
}
