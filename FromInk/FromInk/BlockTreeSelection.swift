import Foundation

/// The reducer-side selection model for the block-tree editor.
///
/// SwiftUI's `AttributedTextSelection` is the prior selection shape
/// (lived inside `AttributedString.Index` space). It's superseded by
/// `BlockTreeSelection` along with the block-tree content pivot — the
/// new selection addresses positions inside the `RichTextDocument`
/// tree, not inside a flat string.
///
/// **Shape.**
///   - `path: [UUID]` — chain of block IDs from the document root to
///     the leaf block the selection sits in. Empty path is the
///     "unset" sentinel; block-format actions resolve unset to the
///     last leaf, mirroring the prior `AttributedTextSelection()`
///     default-end-of-document contract.
///   - `startUTF16` / `endUTF16` — offsets in UTF-16 code units inside
///     the leaf's `joinedInlineText`. UTF-16 chosen so the editor's
///     UITextView selectedRange maps directly without per-edit
///     code-point arithmetic (the editor's `NSRange` is over UTF-16).
///   - `isInsertion` — a single caret position. The reducer treats
///     insertion-only selections as "no range" for inline-format
///     actions (mirrors the prior behavior — toggling bold with no
///     range was a no-op).
///
/// **Equality** is synthesized; cheap because IDs and Ints compare
/// trivially. Selection changes fire on every keystroke and don't
/// trigger persist effects, so the cost stays bounded regardless of
/// document size.
struct BlockTreeSelection: Equatable, Sendable {
    var path: [UUID]
    var startUTF16: Int
    var endUTF16: Int

    init(path: [UUID] = [], startUTF16: Int = 0, endUTF16: Int = 0) {
        self.path = path
        self.startUTF16 = startUTF16
        self.endUTF16 = endUTF16
    }

    /// Insertion-point selection at the given path + offset.
    static func insertion(at path: [UUID], offset: Int) -> BlockTreeSelection {
        BlockTreeSelection(path: path, startUTF16: offset, endUTF16: offset)
    }

    /// A range selection at the given path + offsets. `start` and
    /// `end` are normalised on assignment so `start <= end` holds.
    static func range(at path: [UUID], start: Int, end: Int) -> BlockTreeSelection {
        BlockTreeSelection(
            path: path,
            startUTF16: min(start, end),
            endUTF16: max(start, end)
        )
    }

    /// True when start and end coincide. Inline-format actions treat
    /// this as a no-range no-op; block-format actions still resolve
    /// the host leaf via `path` and target the whole leaf.
    var isInsertion: Bool { startUTF16 == endUTF16 }

    /// True when `path` is empty — the editor hasn't reported a real
    /// caret yet (new block, just opened). Block-format actions
    /// resolve unset selections to the last leaf in the document; see
    /// `RichTextDocument` extension helper.
    var isUnset: Bool { path.isEmpty }
}

// MARK: - Document <-> selection helpers

extension RichTextDocument {

    /// Find the last leaf block in reading order (depth-first
    /// in-order traversal). Used by block-format actions when the
    /// selection is unset — applies the format to the document's
    /// last paragraph, matching the prior end-of-document fallback.
    var lastLeafBlock: Block? {
        // Walk depth-first, last-first.
        for block in blocks.reversed() {
            if let leaf = block.lastLeafDescendant {
                return leaf
            }
        }
        return nil
    }

    /// Resolve the leaf block that `selection` addresses. Returns nil
    /// if the path no longer exists (block was deleted) — callers
    /// either fall back to the last leaf or no-op.
    func leafBlock(for selection: BlockTreeSelection) -> Block? {
        if selection.isUnset {
            return lastLeafBlock
        }
        return block(at: selection.path)
    }
}

extension Block {

    /// True when this block is a leaf — paragraph / heading /
    /// codeBlock / divider. Containers (lists, blockquote) are not
    /// addressable by `joinedInlineText`.
    var isLeaf: Bool {
        switch kind {
        case .paragraph, .heading, .codeBlock, .divider:
            return true
        case .bulletList, .orderedList, .blockquote:
            return false
        }
    }

    /// Last leaf reachable from this block, depth-first reversed.
    /// Returns self for leaf blocks; descends through containers.
    var lastLeafDescendant: Block? {
        if isLeaf { return self }
        for descendant in descendants.reversed() {
            if let leaf = descendant.lastLeafDescendant {
                return leaf
            }
        }
        return nil
    }
}
