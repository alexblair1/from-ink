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

    /// Unavailable fallback — in-memory container for degraded boot or
    /// preview contexts.
    static let unavailable: LocalModelContextDependency = {
        let config = ModelConfiguration(
            schema: Schema([UserPreferencesRecord.self]),
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try! ModelContainer(
            for: Schema([UserPreferencesRecord.self]),
            configurations: config
        )
        return LocalModelContextDependency(
            context: { container.mainContext },
            warmup: { }
        )
    }()

    static let preview: LocalModelContextDependency = .unavailable
}

// MARK: - DependencyKey

extension LocalModelContextDependency: DependencyKey {
    static let liveValue: LocalModelContextDependency = .unavailable

    static let testValue: LocalModelContextDependency = .unavailable
}

// MARK: - DependencyValues

extension DependencyValues {
    var localModelContext: LocalModelContextDependency {
        get { self[LocalModelContextDependency.self] }
        set { self[LocalModelContextDependency.self] = newValue }
    }
}
