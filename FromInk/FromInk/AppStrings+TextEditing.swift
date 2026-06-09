import Foundation

extension AppStrings {
    /// Localized strings for the text editor surface (`TextBlockView`,
    /// `TextEditingFeature`, `TextNoteScreen`). Slash-command labels,
    /// accessory-bar mode names, and selection-menu items live in
    /// dedicated `AppStrings+Slash`, `AppStrings+AccessoryBar`,
    /// `AppStrings+SelectionMenu` files when they land.
    enum TextEditing {
        // MARK: - Editor placeholders

        /// Placeholder shown when a text block is empty AND focused.
        /// Disappears as soon as the user types anything.
        static let emptyBlockPlaceholder = NSLocalizedString(
            "textEditing.emptyBlockPlaceholder",
            value: "Start typing…",
            comment: "Placeholder text shown inside an empty, focused text block."
        )

        /// Placeholder shown when a whole text note is empty (no
        /// blocks at all, or one empty block on a brand-new page).
        static let emptyNoteHeadline = NSLocalizedString(
            "textEditing.emptyNoteHeadline",
            value: "A blank page.",
            comment: "Headline shown on an empty text note."
        )

        static let emptyNoteSubhead = NSLocalizedString(
            "textEditing.emptyNoteSubhead",
            value: "Tap to begin.",
            comment: "Subhead shown beneath the empty-note headline, inviting the user to start."
        )

        // MARK: - Load failure

        /// Shown in place of a text block whose archived body failed
        /// to decode (e.g. corrupted bytes on disk). The user can tap
        /// to retry or delete; surfacing this rather than silently
        /// rendering an empty block protects against data-loss bugs
        /// from masquerading as no-op edits.
        static let bodyDecodeFailedHeadline = NSLocalizedString(
            "textEditing.bodyDecodeFailed.headline",
            value: "This block didn't load.",
            comment: "Headline for a text block whose body failed to decode."
        )

        static let bodyDecodeFailedSubhead = NSLocalizedString(
            "textEditing.bodyDecodeFailed.subhead",
            value: "The text is preserved on disk. Tap to retry.",
            comment: "Subhead explaining the decode-failed state."
        )

        // MARK: - Accessibility

        /// VoiceOver label for the text editor surface. Distinct from
        /// the body text itself — names the editorial role of the
        /// surface so VoiceOver users know what they're focused on.
        static let editorAccessibilityLabel = NSLocalizedString(
            "textEditing.editor.accessibility.label",
            value: "Text editor",
            comment: "VoiceOver label for the rich-text editor surface."
        )

        /// VoiceOver hint announced when the focus first lands on a
        /// text block. Distinct from the body text itself — describes
        /// the block's editorial role.
        static let blockAccessibilityHint = NSLocalizedString(
            "textEditing.block.accessibility.hint",
            value: "Edits to this block save automatically.",
            comment: "VoiceOver hint for a text block."
        )

        // MARK: - Persist failure banner

        /// Title shown briefly when a body save fails (disk full,
        /// permissions, etc.). Lower-priority than the load-failed
        /// placeholder — the editor stays usable; this banner notes
        /// that the in-flight save didn't land.
        static let persistFailedBannerTitle = NSLocalizedString(
            "textEditing.persistFailed.banner.title",
            value: "Couldn't save changes",
            comment: "Banner shown when a text-block save fails. Editor stays usable; future edits retry."
        )

        static let persistFailedBannerSubtitle = NSLocalizedString(
            "textEditing.persistFailed.banner.subtitle",
            value: "Your next edit will retry.",
            comment: "Reassurance under the persistFailed banner so the user knows the failure is transient."
        )

        // MARK: - Inline format toggles (used by future chrome)

        static let formatBold = NSLocalizedString(
            "textEditing.format.bold",
            value: "Bold",
            comment: "Inline format toggle for bold weight."
        )

        static let formatItalic = NSLocalizedString(
            "textEditing.format.italic",
            value: "Italic",
            comment: "Inline format toggle for italic."
        )

        static let formatUnderline = NSLocalizedString(
            "textEditing.format.underline",
            value: "Underline",
            comment: "Inline format toggle for underline."
        )

        static let formatStrikethrough = NSLocalizedString(
            "textEditing.format.strikethrough",
            value: "Strikethrough",
            comment: "Inline format toggle for strikethrough."
        )
    }
}
