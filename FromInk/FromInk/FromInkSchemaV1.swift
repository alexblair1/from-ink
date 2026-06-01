import Foundation
import SwiftData

/// The first published schema version for From Ink's synced data store.
///
/// `UserPreferencesRecord` is intentionally NOT in `models` — it lives in
/// a separate, local-only `ModelContainer` that never participates in
/// CloudKit sync (per `data_model_edd.md` §9). Local schemas can be
/// migrated freely without `VersionedSchema` ceremony.
///
/// **Phase 1**: container is constructed with `cloudKitDatabase: .none`.
/// Models follow CloudKit constraints today (defaults, optionals, no
/// `@Attribute(.unique)`, `@Attribute(.externalStorage)` on large blobs)
/// so the Phase 3 flip to `.private("iCloud.com.fromink.app")` is a
/// one-line change. See `data_model_edd.md` §9.3.
enum FromInkSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Notebook.self,
            NotePage.self,
            Folder.self,
            Tag.self,
            ImportedPDF.self,
            PDFAnnotation.self,
            NoteHeader.self,
            NoteLink.self,
            NoteHistoryEntry.self,
            DailyBriefRecord.self,
        ]
    }
}
