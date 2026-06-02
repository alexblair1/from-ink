# From Ink — Manual Testing Plan

Catalogue of manual test cases that aren't covered by automated `XCTest`
or `TestStore` suites. Each entry describes the scenario, what to do,
what to look for, and what blocks a green pass. Add entries before
shipping new surface area that interacts with the OS, the file system,
iCloud, or hardware (Pencil, mic, etc.) where unit coverage is
impractical.

---

## Reference: PDF storage architecture

Load-bearing facts the test cases below assume. Confirm any change to
these stops the relevant tests passing — the tests are designed to
catch regressions in this architecture, not to verify a specific
implementation choice.

- **Two SwiftData containers.** The synced container holds Notebook,
  NotePage, ImportedPDF, PDFAnnotation, Folder, Tag, etc.; the
  local-only container holds `UserPreferencesRecord`. Configured in
  `AppDependencyContainer.modelContainer` /
  `localContainer` with distinct store URLs (default store +
  `fromink-local.store`) to avoid SQLite table collisions.
- **CloudKit is OFF in dev.** Synced container uses
  `cloudKitDatabase: .none` today. Phase 6 flips to `.private(...)`
  without touching the schema or models.
- **PDF bytes use `@Attribute(.externalStorage)`.**
  `ImportedPDF.sourcePDFData` and `ImportedPDF.thumbnailData` are
  marked external. SwiftData writes the row to `default.store` and
  the blob to a sibling file at
  `Application Support/.default_SUPPORT/_EXTERNAL_DATA/<UUID>`. The
  SQLite row holds only a reference to the blob file.
- **Import path** (`ImportPDFService.liveValue`):
  `Data(contentsOf: url)` materializes the whole PDF into RAM,
  parallel-parses + SHA-256-hashes off the main actor, returns a
  draft. `NotebookClient.importPDF` then does a single SwiftData
  insert + save. The Data buffer is the riskiest memory allocation
  on RAM-constrained devices — drives the 500 MB cap.
- **500 MB import cap** (`ImportPDFService.maxAssetBytes`). Our
  choice, not iCloud's. Three reasons: iPhone RAM ceiling for the
  in-memory parse, upload time on flaky connections (no resumable
  uploads from CloudKit), user iCloud quota courtesy. Above this
  the precheck rejects with the localized "too large" alert before
  reading bytes.
- **CloudKit at Phase 6 flip.** Schema stays. External blob files
  auto-promote to `CKAsset` on first sync; metadata (title,
  contentHash, byteSize, etc.) rides in the CKRecord, well under
  the 1 MB record cap. We don't need multipart / chunked transfer —
  CloudKit manages the asset upload opaquely. We DO need
  `CKError` handling at save boundaries (no resumable uploads).
- **The 1 MB number is the per-record cap, not a transfer limit.**
  Only bites if you cram a blob into a structured field — we don't.
  `@Attribute(.externalStorage)` sidesteps it entirely.
- **Sync batch limits worth knowing but not currently reachable.**
  200 asset-upload tokens per request, 400 records per operation,
  40 fetches/sec. We write single-record-per-operation, so none
  of these are in range today. If we ever add bulk import, chunk
  at ~100.

---

## PDF imports — large file handling (pre-CloudKit verification)

**Why this matters before Phase 6.** PDFs persist via SwiftData's
`@Attribute(.externalStorage)` to a `_EXTERNAL_DATA/` directory next to
the SQLite store. When CloudKit (`cloudKitDatabase: .private(...)`)
flips on, those external blobs auto-promote to `CKAsset` on first sync.
We need to know — before that flip — that the current import / persist
path handles large files without OOMing on iPhone, that blobs land
where we expect, that failures are clean, and that the 500 MB cap in
`ImportPDFService.maxAssetBytes` is honored end-to-end. The
`Data(contentsOf: url)` call in `ImportPDFService.liveValue` reads the
entire file into RAM as one allocation — that's the riskiest piece on
RAM-constrained devices, and unit tests can't surface it.

**Fixtures.** Source a single real PDF at each tier rather than
generating ones — synthetic PDFs don't exercise the page-parse cost.
- ~50 MB: a heavily-illustrated reference (e.g. a textbook chapter PDF)
- ~250 MB: a scanned multi-volume reference
- ~500 MB: a high-res scanned archive at the cap
- ~600 MB: any PDF over the cap (over-limit rejection)

Store fixtures in iCloud Drive so the file picker can reach them
without bundling them in the app.

**Devices.** Run the full matrix on at least one RAM-constrained
device (8 GB iPhone — iPhone 15 / 15 Plus class). iPad Pro M-series
won't surface the OOM ceiling.

### TC-PDF-IMPORT-01: Mid-size PDF, happy path

1. Open From Ink on an 8 GB iPhone, fresh launch.
2. Tap Import PDF in the home screen, pick the ~50 MB fixture.
3. Wait for the import alert / navigate-to-viewer.
4. Open the imported PDF, scroll through several pages.
5. Background the app for 30 seconds, foreground it.
6. Force-quit and relaunch.

**Pass criteria:**
- Import completes without alert, viewer opens automatically.
- Scrolling stays responsive (no perceptible frame drops).
- The PDF row appears in the Recent shelf with the correct title.
- After relaunch, the PDF is still present and openable.
- Settings → General → iPhone Storage → From Ink shows app storage
  grown by approximately the file's byte count.

### TC-PDF-IMPORT-02: Large PDF (~250 MB), memory headroom

1. Attach the device to Xcode with Debug → Memory Graph available.
2. Repeat the import flow with the ~250 MB fixture.
3. While the import is in-flight, capture a memory graph (
   Debug Navigator → Memory).
4. After the import completes, capture again.

**Pass criteria:**
- Import completes without crash or `jetsam` termination
  (no "Terminated due to memory issue" in Console).
- Peak memory during import does not exceed ~3× the file size
  (current `Data(contentsOf:)` strategy can hold the bytes + a hashing
  copy + the parsed PDFDocument). Note observed peak in the test
  notes — if it exceeds 4×, file an issue.
- Post-import idle memory drops back near baseline (no leaked
  retention of the byte buffer).
- Viewer renders the first page within 2 seconds of tap.

### TC-PDF-IMPORT-03: At-cap PDF (~500 MB), boundary behavior

1. Same flow with the ~500 MB fixture.
2. Capture memory and time from picker dismissal to viewer-ready.

**Pass criteria:**
- Either: import completes cleanly and viewer opens, OR
- The size-precheck rejects with the "too large" alert (if the file
  is over `maxAssetBytes` by even one byte — check the exact value
  with `ls -l`).
- No mid-import crash. If it crashes, the cap needs to come down —
  the size precheck protects against OOM only if the cap is below the
  device's actual capacity.
- If accepted: file the observed import duration in the test notes.
  Anything over 30 seconds on iPhone is a UX problem we should know
  about before App Store submission.

### TC-PDF-IMPORT-04: Over-cap rejection

1. Import the ~600 MB fixture.

**Pass criteria:**
- The "Couldn't Import PDF" alert appears with the localized
  too-large message naming both the file size and the cap.
- No partial row appears in the library.
- No leaked file under `_EXTERNAL_DATA/` after the rejection. Verify
  via the Files app routing into the From Ink container, or via
  `xcrun simctl get_app_container booted com.fromink.app data` and
  walking `Library/Application Support/.default_SUPPORT/_EXTERNAL_DATA/`.

### TC-PDF-IMPORT-05: Backgrounding mid-import

1. Start importing the ~250 MB fixture.
2. Immediately background the app (home gesture) before the import
   completes.
3. Wait 60 seconds, foreground the app.

**Pass criteria:**
- One of two acceptable outcomes: (a) the import completed in the
  background and the PDF is present, or (b) the import was suspended
  and the user sees no half-finished row in the library — no orphan
  state.
- No crash on foreground.
- Console doesn't show CoreData / SwiftData "context not saved"
  warnings on foregrounding.

### TC-PDF-IMPORT-06: External-storage blob verification

This is the "are we wired the way we think we are" test — confirms
the `@Attribute(.externalStorage)` promotion is actually happening
before we trust CloudKit to do the right thing with it later.

1. Import any sized fixture (50 MB is fine).
2. With the device or simulator attached, run:
   ```
   xcrun simctl get_app_container booted com.fromink.app data
   ```
   (replace `booted` with the simulator UUID, or use Devices window
   for a real device).
3. Navigate to
   `Library/Application Support/.default_SUPPORT/_EXTERNAL_DATA/`.
4. Confirm a file is present whose size matches the imported PDF's
   byte count (± a small overhead).

**Pass criteria:**
- The blob file exists at that path.
- Its size matches the source PDF within a few KB.
- The SQLite store at `default.store` does NOT contain the blob inline
  (a quick `ls -l` shows `default.store` only grew by the metadata
  row, ~few KB, not by the PDF's full size).

**If this fails:** the `.externalStorage` attribute isn't taking
effect, and CloudKit would try to ship the bytes in the CKRecord (1 MB
record cap → silent sync failure on any non-trivial PDF). Block the
Phase 6 flip until resolved.

### TC-PDF-IMPORT-07: Delete reclaims external storage

1. Note the current app storage size (Settings → iPhone Storage →
   From Ink).
2. Import a 250 MB fixture; note the new app storage size (should be
   ~250 MB higher).
3. Delete the PDF from the library (long-press → Delete, or however
   the delete affordance lands).
4. Note the app storage size again.

**Pass criteria:**
- Post-delete storage drops back to approximately the pre-import
  baseline. SwiftData should cascade-delete the external blob along
  with the row.
- If storage stays inflated: the external blob isn't being cleaned
  up. Block Phase 6 — leaked CKAssets in iCloud would eat the user's
  quota silently.

### TC-PDF-IMPORT-08: Multiple consecutive large imports

1. Import three different 100 MB fixtures back-to-back, with no
   intervening relaunch.

**Pass criteria:**
- All three complete successfully.
- App storage grows by approximately 300 MB total.
- No memory pressure crash (the three byte buffers should not be
  retained simultaneously — `ImportPDFService` should be releasing
  each `Data` before the next import starts).
- All three PDFs appear in Recent.

### Reporting

For each TC above, capture in the run notes:
- Device + iOS version
- Observed import duration (TC-02 / TC-03 / TC-08)
- Observed memory peak in MB (TC-02 / TC-03)
- Pass / fail / blocked
- Console excerpts for any unexpected output

Findings that block the CloudKit flip:
- TC-06 fails (externalStorage not actually external)
- TC-07 fails (deleted PDFs leak external blobs)
- TC-03 crashes at the cap (OOM ceiling lower than 500 MB on
  target devices)
- Any TC produces unrecoverable on-disk state (corrupted SQLite,
  orphan blobs, etc.)
