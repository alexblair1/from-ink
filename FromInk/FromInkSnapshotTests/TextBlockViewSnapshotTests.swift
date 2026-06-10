import SnapshotTesting
import SwiftUI
import XCTest
@testable import FromInk

/// Snapshot coverage for `TextBlockView`'s four visual states + the
/// persist-failure banner overlay.
///
/// 2026-06-09 — the view's editor region currently renders a read-only
/// preview of the document's `plainText` while the TextKit 1 editor is
/// rebuilt (text_experience_edd.md §22.4 commit 4). These snapshots
/// will be re-recorded against the real editor once commit 4 lands.
///
/// States covered:
///   1. Editor with body content — happy path.
///   2. Editor with empty body — placeholder text visible.
///   3. Empty-note placeholder (`isPresented = false`) — taps wire
///      to the recovery action.
///   4. Decode-failed placeholder — taps trigger retry.
///   5. Persist-failed banner above the editor.
final class TextBlockViewSnapshotTests: XCTestCase {

    private static let frameWidth: CGFloat = 600
    private static let frameHeight: CGFloat = 400

    // MARK: - Editor — populated document

    func test_editor_withPopulatedDocument_rendersText() {
        let document = RichTextDocument(blocks: [
            Block(kind: .heading(level: 2, inline: [Inline(text: "Meeting notes")])),
            Block(kind: .paragraph(inline: [
                Inline(text: "Follow up with Sarah on Q3 budget by Friday.")
            ]))
        ])
        assertSnapshot(
            of: makeView(model: editorModel(document: document)),
            as: .image(layout: .fixed(width: Self.frameWidth, height: Self.frameHeight)),
            record: true
        )
    }

    // MARK: - Editor — empty document shows placeholder

    func test_editor_withEmptyDocument_showsPlaceholder() {
        assertSnapshot(
            of: makeView(model: editorModel(document: .empty)),
            as: .image(layout: .fixed(width: Self.frameWidth, height: Self.frameHeight)),
            record: true
        )
    }

    // MARK: - Empty-note placeholder

    func test_emptyNotePlaceholder_rendersHeadlineAndSubhead() {
        assertSnapshot(
            of: makeView(model: TextBlockView.Model(
                isPresented: false,
                failureState: nil,
                document: .empty,
                onCreateRequested: {},
                onRetryRequested: {}
            )),
            as: .image(layout: .fixed(width: Self.frameWidth, height: Self.frameHeight)),
            record: true
        )
    }

    // MARK: - Decode-failed placeholder

    func test_decodeFailedPlaceholder_rendersFailureCopy() {
        assertSnapshot(
            of: makeView(model: TextBlockView.Model(
                isPresented: true,
                failureState: .bodyDecodeFailed,
                document: .empty,
                onCreateRequested: {},
                onRetryRequested: {}
            )),
            as: .image(layout: .fixed(width: Self.frameWidth, height: Self.frameHeight)),
            record: true
        )
    }

    // MARK: - Orphan placeholder

    func test_orphanPlaceholder_rendersFailureCopy() {
        assertSnapshot(
            of: makeView(model: TextBlockView.Model(
                isPresented: true,
                failureState: .orphan,
                document: .empty,
                onCreateRequested: {},
                onRetryRequested: {}
            )),
            as: .image(layout: .fixed(width: Self.frameWidth, height: Self.frameHeight)),
            record: true
        )
    }

    // MARK: - Persist-failure banner above the editor

    func test_persistFailureBanner_rendersAboveEditor() {
        let document = RichTextDocument(blocks: [
            Block(kind: .paragraph(inline: [Inline(text: "In-progress edit")]))
        ])
        assertSnapshot(
            of: makeView(model: TextBlockView.Model(
                isPresented: true,
                failureState: nil,
                document: document,
                persistFailureTitle: AppStrings.TextEditing.persistFailedBannerTitle,
                onCreateRequested: {},
                onRetryRequested: {}
            )),
            as: .image(layout: .fixed(width: Self.frameWidth, height: Self.frameHeight)),
            record: true
        )
    }

    // MARK: - Helpers

    private func editorModel(document: RichTextDocument) -> TextBlockView.Model {
        TextBlockView.Model(
            isPresented: true,
            failureState: nil,
            document: document,
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
