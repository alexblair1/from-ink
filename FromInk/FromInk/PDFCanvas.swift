import PDFKit
import SwiftUI

/// SwiftUI host for an already-parsed `PDFKit.PDFDocument`. Thin
/// `UIViewRepresentable` wrapper around `PDFKit.PDFView` — assumes the
/// document is ready and just mounts it.
///
/// Parsing happens upstream in `PDFContent` so the heavy
/// `PDFKit.PDFDocument(data:)` walk doesn't block the MainActor. See
/// the comment on `PDFContent` for the parse pipeline.
///
/// Phase 3 scope: read-only rendering + page tracking. Phase 4 layers
/// annotation rendering / selection on top via a coordinator delegate
/// path that the upcoming `AnnotationStore` will own.
struct PDFCanvas: UIViewRepresentable {
    let document: PDFKit.PDFDocument
    @Binding var currentPage: Int

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor(Color.canvas)
        view.document = document

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
        // No-op for now. Phase 4 will reconcile our `PDFAnnotation`
        // records against PDFView.annotations here via a diff-by-id
        // pass. Embedded PDF annotations from the source file already
        // render via PDFKit's defaults; only our overlay annotations
        // need this hook.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(currentPage: $currentPage)
    }

    @MainActor
    final class Coordinator: NSObject {
        let currentPage: Binding<Int>

        init(currentPage: Binding<Int>) {
            self.currentPage = currentPage
        }

        deinit {
            // Defensive — selector-style observers are auto-removed on
            // dealloc since iOS 9, but the explicit cleanup makes the
            // intent obvious to readers.
            NotificationCenter.default.removeObserver(self)
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

/// SwiftUI wrapper that turns raw PDF bytes into a rendered viewer.
/// Owns the off-actor parse pipeline:
///
/// 1. `.task(id: data)` fires on first appearance.
/// 2. `Task.detached(priority: .userInitiated)` runs
///    `PDFKit.PDFDocument(data:)` — the heavy parse that walks the
///    whole document tree. Synchronous in PDFKit but isolated off
///    MainActor here, so the viewer stays responsive (spinner +
///    dismiss chrome remain interactive).
/// 3. On completion, the parsed document lands in `@State` and the
///    view swaps to `PDFCanvas`. Failures surface as the standard
///    viewer-load-failed message.
///
/// `PDFKit.PDFDocument` is a class reference, non-Sendable, and can't
/// be carried through TCA `Action` types or `State`. This local
/// SwiftUI ownership is the right boundary: the imperative UIKit
/// object lives entirely on the MainActor in the view layer; the
/// reducer hands raw `Data` and forgets.
struct PDFContent: View {
    let data: Data
    @Binding var currentPage: Int

    @State private var parseResult: ParseResult = .parsing

    private enum ParseResult {
        case parsing
        case parsed(PDFKit.PDFDocument)
        case failed
    }

    var body: some View {
        Group {
            switch parseResult {
            case .parsing:
                VStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .parsed(let document):
                PDFCanvas(document: document, currentPage: $currentPage)

            case .failed:
                VStack(spacing: DesignSystem.standard.spacing.base) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(DesignSystem.standard.colors.flagRed)
                    Text(AppStrings.Library.pdfViewerLoadFailedMessage)
                        .font(.system(size: 15))
                        .foregroundStyle(DesignSystem.standard.colors.ink2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DesignSystem.standard.spacing.lg)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: data) {
            // Off-MainActor parse. `Task.detached` ensures the parse
            // runs on a global cooperative queue, not our captured
            // MainActor. `Data` is Sendable so capture is clean.
            let captured = data
            let document = await Task.detached(priority: .userInitiated) {
                PDFKit.PDFDocument(data: captured)
            }.value

            // Back on MainActor after the await — safe to mutate
            // @State directly.
            if let document {
                parseResult = .parsed(document)
            } else {
                parseResult = .failed
            }
        }
    }
}
