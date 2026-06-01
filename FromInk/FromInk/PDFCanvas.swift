import PDFKit
import SwiftUI

/// SwiftUI wrapper around `PDFKit.PDFView` — the imperative rendering
/// surface for an `ImportedPDF`. Mirrors the role `CanvasView` plays
/// for handwriting: the heavy PDFKit object lives in UIKit; SwiftUI
/// passes data + bindings through the boundary.
///
/// Phase 3 scope: read-only rendering + page tracking. Phase 4 layers
/// annotation rendering / selection on top via a coordinator delegate
/// path that the upcoming `AnnotationStore` will own.
///
/// **Why not the modern API:** `PDFKit.PDFView` is UIKit-bridged and
/// has no SwiftUI-native equivalent in iOS 26. The wrapper is the
/// canonical pattern (see `Canvas/CanvasView.swift` for the analogous
/// PencilKit case).
struct PDFCanvas: UIViewRepresentable {
    let data: Data
    @Binding var currentPage: Int

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .systemBackground
        view.delegate = context.coordinator

        // Heavy parse — Apple's docs are clear that the
        // PDFKit.PDFDocument(data:) initializer is synchronous and
        // walks the entire document tree. For very large PDFs this can
        // stall the main thread for a noticeable fraction of a second.
        // We accept that cost here (SwiftUI updates this view on the
        // MainActor anyway); the import path already runs its parse on
        // a detached task, so each PDF is parsed at most twice across
        // its lifetime.
        view.document = PDFKit.PDFDocument(data: data)

        // PDFView posts `PDFViewPageChanged` on visible-page changes;
        // the coordinator forwards them via the binding so the parent
        // reducer can scope annotation rendering by page.
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageDidChange(_:)),
            name: .PDFViewPageChanged,
            object: view
        )

        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        // No-op for now. Phase 4 will reconcile annotations here via
        // a diff-by-id pass against `PDFAnnotation` snapshots passed
        // through the model. The `data` blob is immutable per the
        // architecture rules, so we never re-set `view.document` from
        // updateUIView.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(currentPage: $currentPage)
    }

    @MainActor
    final class Coordinator: NSObject, PDFViewDelegate {
        let currentPage: Binding<Int>

        init(currentPage: Binding<Int>) {
            self.currentPage = currentPage
        }

        @objc func pageDidChange(_ notification: Notification) {
            guard let view = notification.object as? PDFView,
                  let page = view.currentPage,
                  let index = view.document?.index(for: page)
            else { return }
            currentPage.wrappedValue = index
        }
    }
}
