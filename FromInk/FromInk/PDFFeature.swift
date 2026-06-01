import ComposableArchitecture
import Foundation
import os

private let log = Logger(subsystem: "com.fromink.app", category: "PDFFeature")

/// Owns the open PDF viewer state. Presented as a fullScreenCover from
/// `HomeFeature` (and, later, from a notebook page's link tap). Loads
/// the PDF bytes once on `.onAppear` via `NotebookClient.fetchPDFData`
/// — the bytes don't ride through any snapshot, so this is the one
/// hop where `sourcePDFData` is materialized.
///
/// **Manual `Reducer` conformance** — the `@Reducer` macro is
/// incompatible with this project's `MainActor` isolation. See
/// `ToolbarFeature` for the canonical example.
struct PDFFeature: Reducer {

    @ObservableState
    struct State: Equatable {
        let pdfID: UUID
        /// Pre-loaded from the `ImportedPDFSnapshot` at presentation
        /// time so the title bar can render immediately while bytes
        /// load.
        let title: String
        let pageCount: Int
        var loadState: LoadState = .loading
        /// Currently-visible page index (0-based). Updated by the
        /// `PDFCanvas` coordinator on visible-page changes. Phase 4
        /// (annotations) uses this to scope rendering.
        var currentPage: Int = 0

        enum LoadState: Equatable {
            case loading
            /// Bytes are loaded and ready to hand to PDFKit. Stored as
            /// `Data` here; the `PDFCanvas` does the heavy
            /// `PDFKit.PDFDocument(data:)` parse off-actor.
            case loaded(Data)
            /// Load failed — `sourcePDFData` was nil (corrupted import)
            /// or the row was deleted between presentation and load.
            /// `message` is the localized alert body.
            case failed(message: String)
        }
    }

    @CasePathable
    enum Action: Equatable {
        case onAppear
        /// Result of `notebookClient.fetchPDFData(id:)`. `nil` means
        /// the row had no `sourcePDFData` (or the row vanished) — the
        /// reducer transitions to `.failed`.
        case dataLoaded(Data?)
        /// `notebookClient.fetchPDFData` threw. Logs and transitions to
        /// `.failed` with the localized message.
        case loadFailed(String)
        /// User tapped the dismiss chrome. Parent observes this via
        /// presentation action and clears its `@Presents` slot.
        case dismissTapped
        /// Coordinator reports a new visible page. State stores it for
        /// future annotation scoping; today nothing else reads it.
        case pageChanged(Int)
    }

    @Dependency(\.notebookClient) var notebookClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                let id = state.pdfID
                return .run { send in
                    // Touch lastOpenedAt first so the home Recent shelf
                    // re-sorts even if the bytes fail to load — opening
                    // counts as activity.
                    do { try await notebookClient.touchPDFOpened(id) }
                    catch { log.error("touchPDFOpened failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)") }

                    do {
                        let data = try await notebookClient.fetchPDFData(id)
                        await send(.dataLoaded(data))
                    } catch {
                        log.error("fetchPDFData failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        await send(.loadFailed(error.localizedDescription))
                    }
                }
                .cancellable(id: "pdfLoad-\(id)", cancelInFlight: true)

            case .dataLoaded(.some(let data)):
                state.loadState = .loaded(data)
                return .none

            case .dataLoaded(.none):
                // `sourcePDFData` was nil or the row vanished between
                // presentation and load. Log the id for diagnostics;
                // surface a viewer-specific message (the import-time
                // "couldn't read this file as a PDF" copy is misleading
                // here — the read succeeded, the bytes were missing).
                let id = state.pdfID
                log.error("PDF load failed: fetchPDFData returned nil for \(id, privacy: .public)")
                state.loadState = .failed(message: AppStrings.Library.pdfViewerLoadFailedMessage)
                return .none

            case .loadFailed(let message):
                // Bind the carried error description so it shows up in
                // diagnostics. The user-facing message is the
                // viewer-specific string — the raw error description
                // is rarely user-actionable.
                log.error("PDF load failed: \(message, privacy: .private)")
                state.loadState = .failed(message: AppStrings.Library.pdfViewerLoadFailedMessage)
                return .none

            case .pageChanged(let index):
                state.currentPage = index
                return .none

            case .dismissTapped:
                // Parent owns dismiss — clears the @Presents slot.
                return .none
            }
        }
    }
}
