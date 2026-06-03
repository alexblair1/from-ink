import ComposableArchitecture
import SwiftUI

/// Invisible mount surface for the document-import system UIs. Holds
/// three SwiftUI modifiers — `.fileImporter`, `.fullScreenCover` (for
/// the scanner), and `.alert` (for the error state) — each gated on
/// `store.phase`. Renders `Color.clear` for its body; no visible
/// chrome of its own. Anchoring is the caller's responsibility (the
/// caller's `Menu` anchors itself to the trigger button; the system
/// modifiers below present from the calling window).
///
/// **Mount pattern** (Home, Notebook, etc.):
/// ```swift
/// .background {
///     if let importStore = $store.scope(
///         state: \.documentImport, action: \.documentImport
///     ).wrappedValue {
///         DocumentImportWiringView(store: importStore)
///     }
/// }
/// ```
/// (Or via `IfLetStore` if you prefer the explicit primitive.)
///
struct DocumentImportWiringView: View {
    @Bindable var store: StoreOf<DocumentImportFeature>

    var body: some View {
        // Invisible host. The system modifiers below trigger native
        // UI when their bindings flip — no visible body needed.
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            // File picker — bound to `.filePicker` phase.
            .fileImporter(
                isPresented: Binding(
                    get: { store.phase == .filePicker },
                    set: { isOpen in
                        if !isOpen { store.send(.filePickerCancelled) }
                    }
                ),
                allowedContentTypes: store.allowedContentTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else {
                        store.send(.filePickerCancelled)
                        return
                    }
                    store.send(.filePickerCompleted(url: url))
                case .failure:
                    store.send(.filePickerFailed(
                        message: AppStrings.DocumentImport.filePickerFailedMessage
                    ))
                }
            }
            // Scanner cover — bound to `.scanning` phase. Apple's
            // VNDocumentCameraViewController takes over the camera
            // and expects an immersive presentation surface.
            .fullScreenCover(
                isPresented: Binding(
                    get: { store.phase == .scanning },
                    set: { isOpen in
                        if !isOpen && store.phase == .scanning {
                            // User dragged the cover down before the
                            // scanner delegate fired — treat as cancel.
                            store.send(.scanCancelled)
                        }
                    }
                )
            ) {
                DocumentScannerRepresentable { outcome in
                    switch outcome {
                    case .success(let images):
                        store.send(.scanCompleted(images: images.map(UIImageBox.init)))
                    case .cancelled:
                        store.send(.scanCancelled)
                    case .failed:
                        store.send(.scanFailed(
                            message: AppStrings.DocumentImport.scannerFailedMessage
                        ))
                    }
                }
                .ignoresSafeArea()
            }
            // Error alert — bound to `.error` phase. Native alert is
            // the right primitive: a short error message with a
            // single Okay button. Cross-platform, anchored to the
            // window, and dismiss is handled by SwiftUI.
            .alert(
                AppStrings.DocumentImport.title,
                isPresented: Binding(
                    get: {
                        if case .error = store.phase { return true }
                        return false
                    },
                    set: { isOpen in
                        if !isOpen { store.send(.errorAcknowledged) }
                    }
                ),
                presenting: errorMessage(from: store.phase)
            ) { _ in
                Button(AppStrings.DocumentImport.okay) {
                    store.send(.errorAcknowledged)
                }
            } message: { message in
                Text(message)
            }
    }

    /// Pulls the localized error message out of the `.error` phase so
    /// `.alert(presenting:)` can pass it into the message closure.
    /// Returns `nil` for any non-error phase (alert won't present).
    private func errorMessage(from phase: DocumentImportFeature.State.Phase) -> String? {
        if case .error(let message) = phase {
            return message
        }
        return nil
    }
}
