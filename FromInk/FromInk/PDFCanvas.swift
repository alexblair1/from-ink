import PDFKit
import SwiftUI

// MARK: - Custom annotation key for identity round-trip

extension PDFAnnotationKey {
    /// Custom annotation key we stamp on every `PDFKit.PDFAnnotation` we
    /// create so the reconcile loop can identify "our" annotations by
    /// `PDFAnnotationSnapshot.id`. PDFKit preserves unknown keys in
    /// memory; whether they survive PDF export depends on the writer
    /// path (PDFView's `dataRepresentation()` keeps them). Embedded
    /// annotations imported from the source PDF do not carry this key,
    /// so the reconcile loop won't accidentally touch them.
    static let fromInkID = PDFAnnotationKey(rawValue: "FromInkID")
}

// MARK: - Reconcile

/// Diff-by-id reconcile of our `PDFAnnotationSnapshot` records against
/// PDFKit's `PDFView.annotations`. Adds, removes, and updates in-place
/// rather than tearing down + rebuilding the full set, so PDFView's
/// own scrolling/selection state doesn't reset on every state change.
///
/// Embedded annotations from the source PDF (those without the
/// `FromInkID` key) are left alone — only annotations we've authored
/// participate in the diff.
@MainActor
private func reconcileAnnotations(
    desired: [PDFAnnotationSnapshot],
    in pdfView: PDFView
) {
    guard let document = pdfView.document else { return }

    // Index desired snapshots by id.
    let desiredByID: [UUID: PDFAnnotationSnapshot] = Dictionary(
        uniqueKeysWithValues: desired.map { ($0.id, $0) }
    )

    // Walk every page and index "ours" by id.
    var existingByID: [UUID: PDFKit.PDFAnnotation] = [:]
    for pageIndex in 0..<document.pageCount {
        guard let page = document.page(at: pageIndex) else { continue }
        for annotation in page.annotations {
            guard let idString = annotation.value(forAnnotationKey: .fromInkID) as? String,
                  let id = UUID(uuidString: idString)
            else { continue }
            existingByID[id] = annotation
        }
    }

    // Remove vanished annotations.
    for (id, existing) in existingByID where desiredByID[id] == nil {
        existing.page?.removeAnnotation(existing)
    }

    // Add new annotations.
    for (id, snapshot) in desiredByID where existingByID[id] == nil {
        guard let page = document.page(at: snapshot.pageIndex) else { continue }
        if let pdfAnnotation = makePDFAnnotation(from: snapshot, page: page) {
            page.addAnnotation(pdfAnnotation)
        }
    }

    // Phase 4a is create-only — annotations are immutable for v1.
    // Phase 4b adds the update path here when edit-color / edit-bounds
    // ships.
}

/// Builds a `PDFKit.PDFAnnotation` from one of our snapshots. Returns
/// nil for kinds the v1 viewer doesn't render yet (ink, pencil,
/// freeText, shape) — those land in later phases. Highlights and
/// underlines render today.
@MainActor
private func makePDFAnnotation(
    from snapshot: PDFAnnotationSnapshot,
    page: PDFPage
) -> PDFKit.PDFAnnotation? {
    let bounds = denormalize(snapshot.bounds, in: page)
    let color = UIColor(
        red: snapshot.color.r,
        green: snapshot.color.g,
        blue: snapshot.color.b,
        alpha: snapshot.color.a
    )

    let pdfAnnotation: PDFKit.PDFAnnotation?
    switch snapshot.kind {
    case .highlight:
        pdfAnnotation = PDFKit.PDFAnnotation(
            bounds: bounds, forType: .highlight, withProperties: nil
        )
    case .underline:
        pdfAnnotation = PDFKit.PDFAnnotation(
            bounds: bounds, forType: .underline, withProperties: nil
        )
    case .freeText, .line, .square, .circle, .polygon, .ink, .pencil:
        // Render paths land in their own phases; for v1 skip silently
        // so a stray record doesn't crash the viewer.
        return nil
    }

    guard let pdfAnnotation else { return nil }
    pdfAnnotation.color = color
    pdfAnnotation.setValue(snapshot.id.uuidString, forAnnotationKey: .fromInkID)
    return pdfAnnotation
}

/// Denormalizes the 0..1 snapshot bounds back into PDF page user-space.
/// Page bounds depend on the page's `cropBox` since that's what PDFView
/// renders.
@MainActor
private func denormalize(_ normalized: CGRect, in page: PDFPage) -> CGRect {
    let pageBounds = page.bounds(for: .cropBox)
    return CGRect(
        x: pageBounds.origin.x + normalized.origin.x * pageBounds.size.width,
        y: pageBounds.origin.y + normalized.origin.y * pageBounds.size.height,
        width: normalized.size.width * pageBounds.size.width,
        height: normalized.size.height * pageBounds.size.height
    )
}

// MARK: - PDFCanvas

/// SwiftUI host for an already-parsed `PDFKit.PDFDocument`. Thin
/// `UIViewRepresentable` wrapper around `PDFKit.PDFView` — assumes the
/// document is ready and just mounts it.
///
/// Parsing happens upstream in `PDFContent` so the heavy
/// `PDFKit.PDFDocument(data:)` walk doesn't block the MainActor. See
/// the comment on `PDFContent` for the parse pipeline.
///
/// Phase 4a: read-only annotation rendering via the reconcile loop in
/// `updateUIView`. Phase 4b adds selection-based creation.
struct PDFCanvas: UIViewRepresentable {
    let document: PDFKit.PDFDocument
    let annotations: [PDFAnnotationSnapshot]
    @Binding var currentPage: Int

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor(Color.canvas)
        view.document = document

        // First-time annotation install — updateUIView also runs the
        // reconcile, but on initial render the annotations array may
        // already be populated from state.
        reconcileAnnotations(desired: annotations, in: view)

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
        // Reconcile annotations on every SwiftUI re-render driven by
        // state changes (typically: annotations were loaded, or a new
        // highlight was created in Phase 4b). Diff-by-id keeps the
        // common case (annotations array unchanged) cheap — the
        // reconcile loop is O(N + M) where N is desired and M is
        // existing-with-our-id.
        reconcileAnnotations(desired: annotations, in: uiView)
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

// MARK: - PDFContent

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
    let annotations: [PDFAnnotationSnapshot]
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
                PDFCanvas(
                    document: document,
                    annotations: annotations,
                    currentPage: $currentPage
                )

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
