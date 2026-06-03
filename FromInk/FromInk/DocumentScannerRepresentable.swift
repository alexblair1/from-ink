import SwiftUI
import UIKit
import VisionKit

/// SwiftUI bridge to `VNDocumentCameraViewController` — Apple's
/// multi-page document scanner with auto-capture, edge detection,
/// perspective correction, and B/W / colour filters.
///
/// Presented from `DocumentImportWiringView` via `.fullScreenCover`.
/// Result is reported back to the caller via a single `onOutcome`
/// closure carrying one of three terminal states: success with
/// captured page images, user-cancel, or VisionKit error.
///
/// Component view: zero state of its own. Owns the `UIKit`
/// controller's lifecycle via the Coordinator pattern; that's the
/// idiomatic Apple-blessed way to bridge UIKit modals into SwiftUI
/// state.
///
struct DocumentScannerRepresentable: UIViewControllerRepresentable {
    /// Single terminal callback. Wiring view dispatches the
    /// matching TCA action and dismisses the cover.
    let onOutcome: (DocumentScanOutcome) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {
        // Scanner controller has no observable knobs we'd want to
        // update mid-flight. Intentionally empty.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onOutcome: onOutcome)
    }
}

// MARK: - Coordinator

extension DocumentScannerRepresentable {
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onOutcome: (DocumentScanOutcome) -> Void

        init(onOutcome: @escaping (DocumentScanOutcome) -> Void) {
            self.onOutcome = onOutcome
        }

        // MARK: - VNDocumentCameraViewControllerDelegate

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            // VNDocumentCameraScan holds pages by index; pull them
            // out into a flat array so downstream code (PDFAssemblyService)
            // doesn't depend on VisionKit types.
            var images: [UIImage] = []
            images.reserveCapacity(scan.pageCount)
            for index in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: index))
            }
            onOutcome(.success(images: images))
        }

        func documentCameraViewControllerDidCancel(
            _ controller: VNDocumentCameraViewController
        ) {
            onOutcome(.cancelled)
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: any Error
        ) {
            onOutcome(.failed(error: error))
        }
    }
}
