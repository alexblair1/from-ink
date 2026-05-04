import ComposableArchitecture
import Foundation

// MARK: - Client interface

struct MLCacheClient {
    /// Read the cached ML output for a note. Returns nil on cache miss.
    var read: @Sendable (String) async throws -> NoteMLCache?
    /// Write (or overwrite) the ML output for a note.
    var write: @Sendable (String, NoteMLCache) async throws -> Void
    /// Remove the cache entry for a note (e.g. when the note is deleted).
    var invalidate: @Sendable (String) async throws -> Void
}

// MARK: - TCA dependency

extension MLCacheClient: DependencyKey {
    static let liveValue = MLCacheClient.live
    static let testValue = MLCacheClient.test
}

extension DependencyValues {
    var mlCacheClient: MLCacheClient {
        get { self[MLCacheClient.self] }
        set { self[MLCacheClient.self] = newValue }
    }
}

// MARK: - Live implementation

private extension MLCacheClient {
    static let live = MLCacheClient(
        read: { noteID in
            let url = try cacheURL(for: noteID)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(NoteMLCache.self, from: data)
        },
        write: { noteID, cache in
            let url = try cacheURL(for: noteID)
            let data = try JSONEncoder().encode(cache)
            try data.write(to: url, options: .atomic)
        },
        invalidate: { noteID in
            let url = try cacheURL(for: noteID)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    )

    static func cacheURL(for noteID: String) throws -> URL {
        let dir = try FileManager.default
            .url(for: .applicationSupportDirectory,
                 in: .userDomainMask,
                 appropriateFor: nil,
                 create: true)
            .appendingPathComponent("MLCache", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(noteID).json")
    }
}

// MARK: - Test implementation

private extension MLCacheClient {
    static let test = MLCacheClient(
        read: { _ in nil },
        write: { _, _ in },
        invalidate: { _ in }
    )
}
