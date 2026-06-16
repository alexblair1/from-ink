import Foundation

extension AppStrings {
    /// Localized copy for the iPhone / iPad-compact keyboard accessory
    /// bar and its "Aa" formatting popover (EDD §14.4). Distinct from
    /// `SlashMenu` because the bar uses Apple-Notes-style labels
    /// (Title / Heading / Subheading) rather than the slash menu's
    /// "Heading 1/2/3".
    enum AccessoryBar {
        // MARK: - Aa popover — block type

        static let title = NSLocalizedString(
            "accessoryBar.blockType.title",
            value: "Title",
            comment: "Aa popover block type — level-1 heading (largest)."
        )
        static let heading = NSLocalizedString(
            "accessoryBar.blockType.heading",
            value: "Heading",
            comment: "Aa popover block type — level-2 heading."
        )
        static let subheading = NSLocalizedString(
            "accessoryBar.blockType.subheading",
            value: "Subheading",
            comment: "Aa popover block type — level-3 heading."
        )
        static let body = NSLocalizedString(
            "accessoryBar.blockType.body",
            value: "Body",
            comment: "Aa popover block type — plain body paragraph."
        )
        static let code = NSLocalizedString(
            "accessoryBar.blockType.code",
            value: "Code",
            comment: "Aa popover block type — monospaced code block."
        )
        static let blockQuote = NSLocalizedString(
            "accessoryBar.blockType.blockQuote",
            value: "Block Quote",
            comment: "Aa popover block type — indented block quotation."
        )

        // MARK: - Aa popover — list style

        static let bulletedList = NSLocalizedString(
            "accessoryBar.list.bulleted",
            value: "Bulleted",
            comment: "Aa popover list style — bulleted list."
        )
        static let numberedList = NSLocalizedString(
            "accessoryBar.list.numbered",
            value: "Numbered",
            comment: "Aa popover list style — numbered list."
        )
        static let checklist = NSLocalizedString(
            "accessoryBar.list.checklist",
            value: "Checklist",
            comment: "Aa popover list style — checklist (not yet available)."
        )

        // MARK: - Aa popover — inline toggles (accessibility labels)

        static let bold = NSLocalizedString(
            "accessoryBar.inline.bold",
            value: "Bold",
            comment: "Aa popover inline toggle — bold."
        )
        static let italic = NSLocalizedString(
            "accessoryBar.inline.italic",
            value: "Italic",
            comment: "Aa popover inline toggle — italic."
        )
        static let underline = NSLocalizedString(
            "accessoryBar.inline.underline",
            value: "Underline",
            comment: "Aa popover inline toggle — underline."
        )
        static let strikethrough = NSLocalizedString(
            "accessoryBar.inline.strikethrough",
            value: "Strikethrough",
            comment: "Aa popover inline toggle — strikethrough."
        )

        // MARK: - Bar buttons (accessibility labels)

        static let formatStyle = NSLocalizedString(
            "accessoryBar.button.formatStyle",
            value: "Text style",
            comment: "Accessory bar button that opens the Aa formatting popover."
        )
        static let undo = NSLocalizedString(
            "accessoryBar.button.undo",
            value: "Undo",
            comment: "Accessory bar undo button."
        )
        static let dismissKeyboard = NSLocalizedString(
            "accessoryBar.button.dismissKeyboard",
            value: "Hide keyboard",
            comment: "Accessory bar button that dismisses the keyboard."
        )

        // MARK: - Chrome

        static let comingSoonBadge = NSLocalizedString(
            "accessoryBar.comingSoon",
            value: "Soon",
            comment: "Badge on a not-yet-available formatting option."
        )
        static let aaPopoverAccessibilityLabel = NSLocalizedString(
            "accessoryBar.aaPopover.accessibilityLabel",
            value: "Text formatting",
            comment: "Accessibility label for the Aa formatting popover."
        )
    }
}
