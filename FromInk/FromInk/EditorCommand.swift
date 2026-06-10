import CoreGraphics
import Foundation

/// Keyboard-invocable editor commands. Maps to `TextEditingFeature`
/// actions via the wiring view's `handle(command:store:)`. Lives at
/// the cross-platform layer (NOT inside the iOS-only
/// `TextKitEditorView`) because `TextBlockView.Model` references it
/// regardless of platform — macOS will eventually have its own
/// `NSTextView`-based editor that emits the same command vocabulary.
///
/// **Keyboard shortcuts (EDD §17).** The iOS editor's
/// `BlockTreeTextView` subclass exposes these via `keyCommands`:
///
///   - ⌘B / ⌘I / ⌘U / ⌘⇧X / ⌘E — inline formats
///   - ⌘⌥1 / ⌘⌥2 / ⌘⌥3 — Heading 1/2/3
///   - ⌘⌥0 — Body (revert to paragraph)
///   - ⌘⇧7 — Numbered list
///   - ⌘⇧8 — Bulleted list
///   - ⌘⇧/ — Open slash palette
///
/// Future shortcuts (link ⌘K, dispatch ⌘⇧D, checklist ⌘⇧9) land with
/// the subsystems they depend on. The enum stays expansion-friendly
/// — adding a case is one enum line + one routing branch in the
/// wiring view + one selector method on `BlockTreeTextView`.
enum EditorCommand: Equatable, Sendable {
    case toggleBold
    case toggleItalic
    case toggleUnderline
    case toggleStrikethrough
    case toggleCode
    case applyHeading(level: Int)   // 1, 2, 3
    case applyBody
    case applyBulletedList
    case applyNumberedList
    /// Open the slash command palette. `caretRectInEditor` is the
    /// caret rect at the moment the shortcut fires, expressed in the
    /// editor `UITextView`'s local coordinate space (matches the
    /// SwiftUI `TextKitEditorView` representable's bounds). The
    /// wiring view stores this in `@State` and uses it as the
    /// `.popover()` attachment anchor so the palette appears beside
    /// the cursor instead of pinned to a corner. `.zero` is a valid
    /// fallback when no caret is available (text view not first
    /// responder) — the popover degrades to the attached view's
    /// top-leading.
    case openSlashPalette(caretRectInEditor: CGRect)

    /// Pressing Enter on an empty list item exits the list — the
    /// item becomes a body paragraph in place. Matches the standard
    /// Notion / Bear / Apple Notes behavior; without this the user
    /// has no way to exit a list except via the slash palette or
    /// keyboard shortcut.
    ///
    /// Detected by `TextKitEditorView` in `shouldChangeTextIn` so
    /// the newline insertion can be suppressed (no flicker of an
    /// extra empty item before the exit lands). The reducer's
    /// `.exitList` handler does the document surgery.
    case exitList

    /// User pressed Enter on a non-empty leaf (or any non-list
    /// leaf, empty or not). The editor suppresses UIKit's `\n`
    /// insertion and asks the reducer to split the current leaf
    /// at the cursor: first half stays in the original leaf, second
    /// half becomes a new leaf below. Selection lands at the start
    /// of the new leaf.
    ///
    /// **Why explicit rather than letting UIKit handle it.** UIKit
    /// inserts `\n` into `attributedText` directly, which leaves
    /// the document model out of sync until parse-back runs. The
    /// parse-back can't tell "user pressed Enter at end of text"
    /// from a trailing `\n` that's structurally part of the last
    /// paragraph — so the new paragraph silently vanishes, the
    /// next typed character has stale chrome, and bullets stop
    /// rendering on subsequent lines. Routing through the reducer
    /// keeps the document authoritative for paragraph structure.
    case insertParagraph
}
