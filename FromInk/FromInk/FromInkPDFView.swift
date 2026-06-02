import PDFKit
import UIKit

/// `PDFView` subclass that participates in the system text-selection
/// edit menu via the legacy `UIMenuController.menuItems` bridge.
/// When the user selects text and the menu appears, a custom
/// **Highlight** item shows alongside Copy / Look Up / Translate /
/// Share. Tapping it routes through the responder chain to
/// `highlightSelection(_:)` here, which forwards to the wrapping
/// `PDFCanvas.Coordinator` to extract per-line highlights and
/// dispatch the existing `onHighlightExtracted` pipeline.
///
/// **API status.** `UIMenuController` and its `menuItems` property
/// are deprecated as of iOS 16, replaced by `UIEditMenuInteraction`
/// for *presenting* edit menus. PDFView, however, manages its own
/// internal `UIEditMenuInteraction` and doesn't expose a clean
/// responder-chain hook for injecting items into it. The
/// `menuItems`-via-deprecated-`UIMenuController` path is the only
/// supported route we have that actually lands the item in PDFView's
/// menu. If a future iOS release removes this bridge entirely, the
/// fallback is a selection-aware floating button observing
/// `PDFViewSelectionChanged` — also fine UX, just not the Books /
/// iBooks pattern the user explicitly chose.
final class FromInkPDFView: PDFView {

    /// Weak back-reference to the `PDFCanvas.Coordinator` that
    /// installed this view. The coordinator outlives the value-type
    /// `PDFCanvas` struct, so this reference is stable for the
    /// lifetime of the view.
    weak var fromInkCoordinator: PDFCanvas.Coordinator?

    /// Registers the **Highlight** item on the shared menu controller.
    /// Idempotent and process-global — calling twice does not produce
    /// duplicate entries. Invoked from `PDFCanvas.Coordinator.attach`
    /// on first mount.
    static func registerMenuItemIfNeeded() {
        guard !menuItemsRegistered else { return }
        let existing = UIMenuController.shared.menuItems ?? []
        let highlight = UIMenuItem(
            title: AppStrings.Library.highlightSelectionMenuItem,
            action: #selector(highlightSelection(_:))
        )
        // De-dupe by action in case a host app also registered the
        // same selector elsewhere — unlikely but cheap to guard.
        if !existing.contains(where: { $0.action == highlight.action }) {
            UIMenuController.shared.menuItems = existing + [highlight]
        }
        menuItemsRegistered = true
    }

    private static var menuItemsRegistered = false

    /// Reports whether this view can perform a given action. PDFView
    /// already returns true for Copy / Look Up / Translate when a
    /// selection exists; we add **Highlight** behind the same gate
    /// (non-empty selection with text content) so the item only
    /// shows when there's something to highlight.
    override func canPerformAction(
        _ action: Selector,
        withSender sender: Any?
    ) -> Bool {
        if action == #selector(highlightSelection(_:)) {
            guard let selection = currentSelection,
                  let text = selection.string,
                  !text.isEmpty
            else { return false }
            return true
        }
        return super.canPerformAction(action, withSender: sender)
    }

    /// Menu-item action. Forwarded to the coordinator which owns the
    /// extraction pipeline (`extractHighlightLines` + the callback
    /// the wiring view supplies).
    @objc func highlightSelection(_ sender: Any?) {
        fromInkCoordinator?.handleHighlightMenuItem(in: self)
    }
}
