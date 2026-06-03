import ComposableArchitecture
import Foundation
import UIKit
import UniformTypeIdentifiers
import os

private let log = Logger(subsystem: "com.fromink.app", category: "DocumentImport")

/// Reusable acquisition feature for documents. Owns the state machine
/// behind the two system surfaces — `.fileImporter` and
/// `VNDocumentCameraViewController` — and emits a single source-
/// agnostic delegate action once a document is acquired.
///
/// **Entry point is the parent's choice.** The previous "choice
/// surface" inside this feature was removed: callers now offer the
/// import-vs-scan choice via a SwiftUI `Menu` (anchored to their own
/// button) and create this feature's state directly in `.filePicker`
/// or `.scanning`. The state machine here only runs the system
/// presentation and result handling — Menu owns the affordance,
/// Apple owns the chrome, and modularity is preserved because any
/// caller can mount the menu + `DocumentImportWiringView` in five
/// lines.
///
/// State machine:
/// ```
///   .filePicker → result → .delegate(.acquired) → parent clears state
///                cancel → .delegate(.dismissed) → parent clears state
///                failure → .error → ack → .delegate(.dismissed)
///
///   .scanning   → outcome
///                  → .processing → assembly → .delegate(.acquired)
///                  → .cancelled → .delegate(.dismissed)
///                  → .failed   → .error → ack → .delegate(.dismissed)
/// ```
///
/// Manual `Reducer` conformance per the project's
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` constraint.
///
struct DocumentImportFeature: Reducer {

    // MARK: - State

    @ObservableState
    struct State: Equatable {
        var phase: Phase
        /// File types accepted by the file picker branch. Stored as
        /// `UTType.Identifier`-backed strings so the State stays
        /// `Equatable` (UTType itself isn't Equatable).
        var allowedTypeIdentifiers: [String]

        enum Phase: Equatable {
            case filePicker
            case scanning
            case processing
            case error(message: String)
        }

        init(
            initialPhase: Phase,
            allowedTypes: [UTType] = [.pdf]
        ) {
            self.phase = initialPhase
            self.allowedTypeIdentifiers = allowedTypes.map(\.identifier)
        }

        /// Convenience for the view: convert identifiers back to UTType
        /// at render time. The reverse-lookup is cheap.
        var allowedContentTypes: [UTType] {
            allowedTypeIdentifiers.compactMap { UTType($0) }
        }
    }

    // MARK: - Action

    @CasePathable
    enum Action: Equatable {

        // File picker outcomes (driven by SwiftUI's `.fileImporter`)
        case filePickerCompleted(url: URL)
        case filePickerCancelled
        case filePickerFailed(message: String)

        // Scanner outcomes (driven by VNDocumentCameraViewController via
        // DocumentScannerRepresentable)
        case scanCompleted(images: [UIImageBox])
        case scanCancelled
        case scanFailed(message: String)

        // Internal: PDF assembly result
        case pdfAssembled(data: Data, pageCount: Int)
        case pdfAssemblyFailed(message: String)

        // Error state
        case errorAcknowledged

        // Delegate (parent intercepts; reducer returns .none)
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            /// Document successfully acquired. Caller routes to its
            /// destination (LibraryFeature import, etc.). Exactly one
            /// of `fileURL` (file source) or `pdfData` (scan source)
            /// is non-nil; the other is nil to avoid making either
            /// caller carry the wrong representation.
            case acquired(source: DocumentSource, fileURL: URL?, pdfData: Data?)
            /// User dismissed without completing acquisition (cancel
            /// from the file picker, scanner, or error alert). The
            /// parent clears its `@Presents` optional so the feature
            /// unmounts and the menu can be re-opened freshly.
            case dismissed
        }
    }

    // MARK: - Dependencies

    @Dependency(\.pdfAssemblyService) var pdfAssemblyService

    // MARK: - Body

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {

            // ── File picker ─────────────────────────────────────────

            case .filePickerCompleted(let url):
                return .send(.delegate(.acquired(
                    source: .file(url),
                    fileURL: url,
                    pdfData: nil
                )))

            case .filePickerCancelled:
                return .send(.delegate(.dismissed))

            case .filePickerFailed(let message):
                state.phase = .error(message: message)
                return .none

            // ── Scanner ─────────────────────────────────────────────

            case .scanCompleted(let boxes):
                state.phase = .processing
                let images = boxes.map(\.image)
                let pageCount = images.count
                return .run { send in
                    do {
                        let data = try await pdfAssemblyService.assemble(images)
                        await send(.pdfAssembled(data: data, pageCount: pageCount))
                    } catch {
                        log.error("PDF assembly failed: \(error.localizedDescription, privacy: .public)")
                        await send(.pdfAssemblyFailed(
                            message: AppStrings.DocumentImport.assemblyFailedMessage
                        ))
                    }
                }
                .cancellable(id: "documentImportPDFAssembly", cancelInFlight: true)

            case .scanCancelled:
                return .send(.delegate(.dismissed))

            case .scanFailed(let message):
                state.phase = .error(message: message)
                return .none

            // ── PDF assembly result ─────────────────────────────────

            case .pdfAssembled(let data, let pageCount):
                return .send(.delegate(.acquired(
                    source: .scan(pageCount: pageCount),
                    fileURL: nil,
                    pdfData: data
                )))

            case .pdfAssemblyFailed(let message):
                state.phase = .error(message: message)
                return .none

            // ── Error ack ───────────────────────────────────────────

            case .errorAcknowledged:
                return .send(.delegate(.dismissed))

            // ── Delegate (parent intercepts) ────────────────────────

            case .delegate:
                return .none
            }
        }
    }
}

// MARK: - UIImage Equatable box

/// `UIImage` is not `Equatable`. TCA actions must be `Equatable` (TCA
/// 1.10+ requirement for `@CasePathable`). Box the array in a thin
/// wrapper that reports equality by identity — two boxes are equal
/// iff they hold the same `UIImage` reference. Sufficient for action
/// equality because scan results don't get re-emitted; the array
/// flows once from scanner → reducer.
///
struct UIImageBox: Equatable, @unchecked Sendable {
    let image: UIImage

    init(_ image: UIImage) { self.image = image }

    static func == (lhs: UIImageBox, rhs: UIImageBox) -> Bool {
        lhs.image === rhs.image
    }
}
