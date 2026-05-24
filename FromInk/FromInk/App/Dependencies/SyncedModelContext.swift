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

    /// Unavailable fallback — returns an in-memory context.
    /// Used when storage init failed; the app boots in degraded mode.
    static let unavailable: SyncedModelContextDependency = {
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
    }()

    /// In-memory container for previews.
    static let preview: SyncedModelContextDependency = .unavailable
}

// MARK: - DependencyKey

extension SyncedModelContextDependency: DependencyKey {
    static let liveValue: SyncedModelContextDependency = .unavailable

    static let testValue: SyncedModelContextDependency = {
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
    }()
}

// MARK: - DependencyValues

extension DependencyValues {
    var syncedModelContext: SyncedModelContextDependency {
        get { self[SyncedModelContextDependency.self] }
        set { self[SyncedModelContextDependency.self] = newValue }
    }
}
