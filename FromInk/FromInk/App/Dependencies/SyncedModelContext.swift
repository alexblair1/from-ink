import ComposableArchitecture
import SwiftData
import Foundation

/// TCA dependency providing the synced ModelContext.
/// Used by reducers and clients that need SwiftData persistence.
///
/// Constructed by AppDependencyContainer and installed into
/// DependencyValues at app launch. Never configured via a global.
///
struct SyncedModelContextDependency: Sendable {
    var context: @Sendable @MainActor () -> ModelContext
    var warmup: @Sendable @MainActor () throws -> Void
}

// MARK: - Factories

extension SyncedModelContextDependency {
    /// Live value backed by a real ModelContainer.
    static func live(container: ModelContainer) -> SyncedModelContextDependency {
        SyncedModelContextDependency(
            context: { container.mainContext },
            warmup: {
                // Force-touch the context to surface any schema issues early.
                _ = container.mainContext
            }
        )
    }

    /// Unavailable fallback — returns an in-memory context. Used by
    /// `AppDependencyContainer` when the on-disk store fails to open
    /// (the bootstrap stage surfaces a `.failed` phase; views behind the
    /// failure UI never observe this context). Must NOT be used as the
    /// `liveValue` — see notes there.
    static let unavailable: SyncedModelContextDependency = inMemory()

    /// In-memory container for previews — same shape as `unavailable`
    /// but semantically distinct (preview-only, not a degraded-boot
    /// signal). Both back onto the same factory.
    static let preview: SyncedModelContextDependency = inMemory()

    /// Factory for an isolated in-memory container. Each call returns a
    /// fresh store, so test cases can't leak data into one another via
    /// shared static instances.
    static func inMemory() -> SyncedModelContextDependency {
        let schema = Schema(FromInkSchemaV1.models)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try! ModelContainer(for: schema, configurations: config)
        return SyncedModelContextDependency(
            context: { container.mainContext },
            warmup: { }
        )
    }
}

// MARK: - DependencyKey

extension SyncedModelContextDependency: DependencyKey {
    /// CRITICAL: `liveValue` must NOT silently fall back to an in-memory
    /// store. A missed `container.install(into:)` would cause writes to
    /// succeed against an orphan container and evaporate at process exit.
    /// We crash loudly instead — the same safety pattern `NotebookClient`
    /// uses (throwing stub). The real implementation is wired by
    /// `AppDependencyContainer` at app launch via `prepareDependencies`.
    static let liveValue: SyncedModelContextDependency = SyncedModelContextDependency(
        context: {
            fatalError("syncedModelContext.liveValue accessed before install. Call AppDependencyContainer.install(into:) at app launch (via prepareDependencies or Store withDependencies).")
        },
        warmup: {
            fatalError("syncedModelContext.liveValue accessed before install. Call AppDependencyContainer.install(into:) at app launch.")
        }
    )

    /// `testValue` returns an in-memory container so TestStore-based
    /// reducer tests can read/write without explicit dependency setup.
    /// Each test gets a fresh store via `.inMemory()`.
    static var testValue: SyncedModelContextDependency { .inMemory() }
}

// MARK: - DependencyValues

extension DependencyValues {
    var syncedModelContext: SyncedModelContextDependency {
        get { self[SyncedModelContextDependency.self] }
        set { self[SyncedModelContextDependency.self] = newValue }
    }
}
