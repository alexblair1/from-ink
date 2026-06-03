import ComposableArchitecture
import UIKit
import XCTest
@testable import FromInk

/// TestStore coverage for `DocumentImportFeature` — the reusable
/// acquisition state machine. The "choice" surface that previously
/// lived in this feature was removed: callers now offer the
/// import-vs-scan choice via a SwiftUI `Menu` (HomeTopBar) and
/// create this feature directly in `.filePicker` or `.scanning`.
///
/// Tests cover:
/// - File picker completion → `.delegate(.acquired(.file))`
/// - File picker cancel → `.delegate(.dismissed)`
/// - File picker failure → error phase → ack → `.delegate(.dismissed)`
/// - Scan completion → processing → assembly → `.delegate(.acquired(.scan))`
/// - Scan cancel → `.delegate(.dismissed)`
/// - Scan failure → error phase → ack → `.delegate(.dismissed)`
/// - PDF assembly failure → error phase
/// - Error acknowledgment from any source → `.delegate(.dismissed)`
///
final class DocumentImportFeatureTests: XCTestCase {

    // MARK: - File picker outcomes

    @MainActor
    func test_filePickerCompleted_emitsDelegateAcquired() async {
        let url = URL(fileURLWithPath: "/tmp/test.pdf")
        let store = TestStore(
            initialState: DocumentImportFeature.State(initialPhase: .filePicker)
        ) {
            DocumentImportFeature()
        }

        await store.send(.filePickerCompleted(url: url))
        await store.receive(
            .delegate(.acquired(source: .file(url), fileURL: url, pdfData: nil))
        )
    }

    @MainActor
    func test_filePickerCancelled_emitsDelegateDismissed() async {
        let store = TestStore(
            initialState: DocumentImportFeature.State(initialPhase: .filePicker)
        ) {
            DocumentImportFeature()
        }

        await store.send(.filePickerCancelled)
        await store.receive(.delegate(.dismissed))
    }

    @MainActor
    func test_filePickerFailed_transitionsToError() async {
        let store = TestStore(
            initialState: DocumentImportFeature.State(initialPhase: .filePicker)
        ) {
            DocumentImportFeature()
        }

        let message = "Couldn't open that file."
        await store.send(.filePickerFailed(message: message)) {
            $0.phase = .error(message: message)
        }
    }

    // MARK: - Scanner outcomes

    @MainActor
    func test_scanCompleted_thenAssembly_emitsDelegateScanSource() async {
        let images = [makeTestImage(), makeTestImage()]
        let boxes = images.map(UIImageBox.init)
        let assembled = "fake-pdf-data".data(using: .utf8)!

        let store = TestStore(
            initialState: DocumentImportFeature.State(initialPhase: .scanning)
        ) {
            DocumentImportFeature()
        } withDependencies: {
            $0.pdfAssemblyService = PDFAssemblyService(
                assemble: { received in
                    XCTAssertEqual(received.count, 2)
                    return assembled
                }
            )
        }
        store.exhaustivity = .off

        await store.send(.scanCompleted(images: boxes)) {
            $0.phase = .processing
        }
        await store.receive(\.pdfAssembled)
        await store.receive(\.delegate)
    }

    @MainActor
    func test_scanCancelled_emitsDelegateDismissed() async {
        let store = TestStore(
            initialState: DocumentImportFeature.State(initialPhase: .scanning)
        ) {
            DocumentImportFeature()
        }

        await store.send(.scanCancelled)
        await store.receive(.delegate(.dismissed))
    }

    @MainActor
    func test_scanFailed_transitionsToError() async {
        let store = TestStore(
            initialState: DocumentImportFeature.State(initialPhase: .scanning)
        ) {
            DocumentImportFeature()
        }

        let message = "Scanner failed."
        await store.send(.scanFailed(message: message)) {
            $0.phase = .error(message: message)
        }
    }

    // MARK: - PDF assembly result

    @MainActor
    func test_pdfAssembled_emitsDelegateWithScanSource() async {
        let data = "pdf".data(using: .utf8)!
        let store = TestStore(
            initialState: DocumentImportFeature.State(initialPhase: .scanning)
        ) {
            DocumentImportFeature()
        }
        // Mid-flow: pretend assembly already started
        store.exhaustivity = .off

        await store.send(.pdfAssembled(data: data, pageCount: 3))
        await store.receive(
            .delegate(.acquired(source: .scan(pageCount: 3), fileURL: nil, pdfData: data))
        )
    }

    @MainActor
    func test_pdfAssemblyFailed_transitionsToError() async {
        let store = TestStore(
            initialState: DocumentImportFeature.State(initialPhase: .scanning)
        ) {
            DocumentImportFeature()
        }
        store.exhaustivity = .off

        let message = "Assembly failed."
        await store.send(.pdfAssemblyFailed(message: message)) {
            $0.phase = .error(message: message)
        }
    }

    // MARK: - Error acknowledgment

    @MainActor
    func test_errorAcknowledged_emitsDelegateDismissed() async {
        let store = TestStore(
            initialState: DocumentImportFeature.State(initialPhase: .filePicker)
        ) {
            DocumentImportFeature()
        }
        // Move to error state
        await store.send(.filePickerFailed(message: "oops")) {
            $0.phase = .error(message: "oops")
        }
        await store.send(.errorAcknowledged)
        await store.receive(.delegate(.dismissed))
    }

    // MARK: - Fixtures

    private func makeTestImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        return renderer.image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }
}
