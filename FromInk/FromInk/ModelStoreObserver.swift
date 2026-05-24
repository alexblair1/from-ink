import Foundation
import CoreData

/// Wraps `NSManagedObjectContextDidSave` notifications into a debounced
/// `AsyncStream<Void>`. Used by reducers (`LibraryFeature`, etc.) as the
/// reactive substitute for SwiftData's `@Query` auto-refresh.
///
/// **Why `.NSManagedObjectContextDidSave` and not `.NSPersistentStoreRemoteChange`:**
/// `.NSPersistentStoreRemoteChange` only fires when another process (or
/// CloudKit) writes to the store — useless in Phase 1 where the app is
/// the sole writer. When Phase 3 enables sync, add the remote-change
/// notification as a second source — wiring is identical.
///
/// **Stability caveat:** `.NSManagedObjectContextDidSave` is a Core Data
/// API. SwiftData is built on Core Data but Apple has not committed to
/// keeping this notification name stable through SwiftData's evolution.
/// Wrapping behind this single helper means a future SwiftData-native
/// `AsyncSequence` (if one ships) is a one-edit swap.
enum ModelStoreObserver {
    /// Emits a debounced tick whenever any `ModelContext` in the process
    /// saves. The 250ms debounce collapses bursts (e.g., ten history
    /// rows written in a single save sweep, or a batch insert) into a
    /// single refresh.
    static func observe(
        debounceMs: Int = 250
    ) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                let notifications = NotificationCenter.default
                    .notifications(named: .NSManagedObjectContextDidSave)
                var debounceTask: Task<Void, Never>?
                for await _ in notifications {
                    debounceTask?.cancel()
                    debounceTask = Task {
                        try? await Task.sleep(for: .milliseconds(debounceMs))
                        guard !Task.isCancelled else { return }
                        continuation.yield(())
                    }
                }
                debounceTask?.cancel()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
