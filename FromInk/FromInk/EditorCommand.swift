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
    /// Open the slash palette at the cursor's current location.
    /// `caretRect` is in SCREEN coordinates (via `UIView.convert(_:to:nil)`);
    /// the wiring view uses a `GeometryReader` to translate to its own
    /// local space for popover positioning.
    case openSlashPalette(caretRect: CGRect)
}
