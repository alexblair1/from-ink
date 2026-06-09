import Foundation

extension AppStrings {
    /// Localized titles + UI copy for the slash command palette and
    /// (later) the accessory bar that shares the same vocabulary.
    enum SlashMenu {
        // MARK: - Block format

        static let heading1 = NSLocalizedString(
            "slashMenu.heading1",
            value: "Heading 1",
            comment: "Slash command — promotes the active paragraph to a level-1 heading."
        )

        static let heading2 = NSLocalizedString(
            "slashMenu.heading2",
            value: "Heading 2",
            comment: "Slash command — promotes the active paragraph to a level-2 heading."
        )

        static let heading3 = NSLocalizedString(
            "slashMenu.heading3",
            value: "Heading 3",
            comment: "Slash command — promotes the active paragraph to a level-3 heading."
        )

        static let body = NSLocalizedString(
            "slashMenu.body",
            value: "Body",
            comment: "Slash command — returns the active paragraph to plain body text."
        )

        static let blockQuote = NSLocalizedString(
            "slashMenu.blockQuote",
            value: "Block Quote",
            comment: "Slash command — wraps the active paragraph in a block quote."
        )

        static let code = NSLocalizedString(
            "slashMenu.code",
            value: "Code",
            comment: "Slash command — formats the active paragraph as a code block."
        )

        // MARK: - Lists

        static let bulletedList = NSLocalizedString(
            "slashMenu.bulletedList",
            value: "Bulleted List",
            comment: "Slash command — inserts a bulleted list."
        )

        static let numberedList = NSLocalizedString(
            "slashMenu.numberedList",
            value: "Numbered List",
            comment: "Slash command — inserts a numbered list."
        )

        static let checklist = NSLocalizedString(
            "slashMenu.checklist",
            value: "Checklist",
            comment: "Slash command — inserts a checklist (checkbox list)."
        )

        // MARK: - Inserts

        static let divider = NSLocalizedString(
            "slashMenu.divider",
            value: "Divider",
            comment: "Slash command — inserts a horizontal divider."
        )

        static let region = NSLocalizedString(
            "slashMenu.region",
            value: "Mark Region",
            comment: "Slash command — turns the selected text into a NoteRegion anchor."
        )

        static let link = NSLocalizedString(
            "slashMenu.link",
            value: "Link",
            comment: "Slash command — inserts a hyperlink."
        )

        static let event = NSLocalizedString(
            "slashMenu.event",
            value: "Calendar Event",
            comment: "Slash command — attaches a calendar event to the selected text."
        )

        static let pdfAttach = NSLocalizedString(
            "slashMenu.pdfAttach",
            value: "PDF",
            comment: "Slash command — attaches a PDF file."
        )

        static let voiceMemo = NSLocalizedString(
            "slashMenu.voiceMemo",
            value: "Voice Memo",
            comment: "Slash command — records a voice memo inline."
        )

        static let image = NSLocalizedString(
            "slashMenu.image",
            value: "Image",
            comment: "Slash command — inserts an image."
        )

        // MARK: - Dispatch

        static let dispatch = NSLocalizedString(
            "slashMenu.dispatch",
            value: "Send to…",
            comment: "Slash command — opens the dispatch flow for the selected text."
        )

        // MARK: - UI chrome

        /// Heading displayed at the top of the popover.
        static let header = NSLocalizedString(
            "slashMenu.header",
            value: "Insert",
            comment: "Header text shown at the top of the slash-command popover."
        )

        /// Empty state when the user's filter matches no commands.
        static let noMatches = NSLocalizedString(
            "slashMenu.noMatches",
            value: "No matching commands",
            comment: "Empty-state message when the slash menu filter has no results."
        )

        /// Trailing badge shown on commands whose action handler
        /// isn't wired yet, so users see the future roadmap rather
        /// than a row that does nothing on tap.
        static let comingSoonBadge = NSLocalizedString(
            "slashMenu.comingSoon",
            value: "Soon",
            comment: "Badge on a slash command whose action handler hasn't shipped yet."
        )

        /// Accessibility hint for the palette container.
        static let paletteAccessibilityLabel = NSLocalizedString(
            "slashMenu.accessibility.label",
            value: "Insert menu",
            comment: "VoiceOver label for the slash-command popover."
        )
    }
}
