import SnapshotTesting
import SwiftUI
import XCTest
@testable import FromInk

/// Snapshot coverage for `TextBlockView`'s four visual states + the
/// persist-failure banner overlay.
///
/// Each fixture pins a frame width so SwiftUI Text doesn't collapse
/// to zero width inside an HStack-less surface — same memory rule
/// the project's other snapshot tests honor for HStack-based
/// components.
///
/// States covered:
///   1. Editor with body content — happy path.
///   2. Editor with empty body — placeholder text visible.
///   3. Empty-note placeholder (`isPresented = false`) — taps wire
///      to the recovery action.
///   4. Decode-failed placeholder — taps trigger retry.
///   5. Persist-failed banner above the editor — editor remains usable.
final class TextBlockViewSnapshotTests: XCTestCase {

    private static let frameWidth: CGFloat = 600
    private static let frameHeight: CGFloat = 400

    // MARK: - Editor — populated body

    func test_editor_withPopulatedBody_rendersText() {
        assertSnapshot(
            of: makeView(model: editorModel(
                body: AttributedString("Meeting notes:\n\nFollow up with Sarah on Q3 budget by Friday.")
            )),
            as: .image(layout: .fixed(width: Self.frameWidth, height: Self.frameHeight)),
            record: false
        )
    }

    // MARK: - Editor — empty body shows placeholder

    func test_editor_withEmptyBody_showsPlaceholder() {
        assertSnapshot(
            of: makeView(model: editorModel(body: AttributedString())),
            as: .image(layout: .fixed(width: Self.frameWidth, height: Self.frameHeight)),
            record: false
        )
    }

    // MARK: - Empty-note placeholder

    func test_emptyNotePlaceholder_rendersHeadlineAndSubhead() {
        assertSnapshot(
            of: makeView(model: TextBlockView.Model(
                isPresented: false,
                failureState: nil,
                body: AttributedString(),
                onBodyEdited: { _ in },
                onCreateRequested: {},
                onRetryRequested: {}
            )),
            as: .image(layout: .fixed(width: Self.frameWidth, height: Self.frameHeight)),
            record: false
        )
    }

    // MARK: - Decode-failed placeholder

    func test_decodeFailedPlaceholder_rendersFailureCopy() {
        assertSnapshot(
            of: makeView(model: TextBlockView.Model(
                isPresented: true,
                failureState: .bodyDecodeFailed,
                body: AttributedString(),
                onBodyEdited: { _ in },
                onCreateRequested: {},
                onRetryRequested: {}
            )),
            as: .image(layout: .fixed(width: Self.frameWidth, height: Self.frameHeight)),
            record: false
        )
    }

    // MARK: - Orphan placeholder

    func test_orphanPlaceholder_rendersFailureCopy() {
        assertSnapshot(
            of: makeView(model: TextBlockView.Model(
                isPresented: true,
                failureState: .orphan,
                body: AttributedString(),
                onBodyEdited: { _ in },
                onCreateRequested: {},
                onRetryRequested: {}
            )),
            as: .image(layout: .fixed(width: Self.frameWidth, height: Self.frameHeight)),
            record: false
        )
    }

    // MARK: - Persist-failure banner above the editor

    func test_persistFailureBanner_rendersAboveEditor() {
        assertSnapshot(
            of: makeView(model: TextBlockView.Model(
                isPresented: true,
                failureState: nil,
                body: AttributedString("In-progress edit"),
                persistFailureTitle: AppStrings.TextEditing.persistFailedBannerTitle,
                onBodyEdited: { _ in },
                onCreateRequested: {},
                onRetryRequested: {}
            )),
            as: .image(layout: .fixed(width: Self.frameWidth, height: Self.frameHeight)),
            record: false
        )
    }

    // MARK: - Helpers

    private func editorModel(body: AttributedString) -> TextBlockView.Model {
        TextBlockView.Model(
            isPresented: true,
            failureState: nil,
            body: body,
            onBodyEdited: { _ in },
            onCreateRequested: {},
            onRetryRequested: {}
        )
    }

    private func makeView(model: TextBlockView.Model) -> some View {
        TextBlockView(model: model)
            .frame(width: Self.frameWidth, height: Self.frameHeight)
            .background(Color("ink/Paper"))
            .environment(\.locale, .init(identifier: "en_US"))
            .colorScheme(.light)
    }
}
