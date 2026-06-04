import Foundation

extension AppStrings {
    enum NotebookPicker {
        static let chooseNotebookTitle = NSLocalizedString(
            "notebookPicker.chooseNotebook.title",
            value: "Choose a notebook",
            comment: "Modal title shown in the picker's first phase (notebook selection grid)."
        )

        static let choosePageTitle = NSLocalizedString(
            "notebookPicker.choosePage.title",
            value: "Choose a page",
            comment: "Modal title shown in the picker's second phase (page selection)."
        )

        static let searchPlaceholder = NSLocalizedString(
            "notebookPicker.searchPlaceholder",
            value: "Search notebooks",
            comment: "Placeholder text for the notebook-search text field."
        )

        static let lastEditedPage = NSLocalizedString(
            "notebookPicker.page.lastEdited",
            value: "Last edited page",
            comment: "Preset row label — open the most recently edited page in the chosen notebook."
        )

        static let newPage = NSLocalizedString(
            "notebookPicker.page.new",
            value: "New page",
            comment: "Preset row label — create a fresh page in the chosen notebook."
        )

        static let morePages = NSLocalizedString(
            "notebookPicker.page.more",
            value: "Specific page",
            comment: "Disclosure row label — expand a grid of every page in the notebook so the user can pick one."
        )

        static let backAction = NSLocalizedString(
            "notebookPicker.back",
            value: "Back",
            comment: "VoiceOver label for the back arrow that returns from page selection to notebook selection."
        )

        static let dismissAction = NSLocalizedString(
            "notebookPicker.dismiss",
            value: "Close",
            comment: "VoiceOver label for the X button that dismisses the entire picker."
        )

        static let emptyNoNotebooks = NSLocalizedString(
            "notebookPicker.empty.noNotebooks",
            value: "No notebooks yet.",
            comment: "Empty state in the notebook grid when the user has zero notebooks."
        )

        static func emptyNoSearchMatches(_ query: String) -> String {
            String.localizedStringWithFormat(
                NSLocalizedString(
                    "notebookPicker.empty.noSearchMatches",
                    value: "No notebooks match \u{201C}%@\u{201D}.",
                    comment: "Empty state in the notebook grid when the search query has no matches. %@ is the user's query."
                ),
                query
            )
        }

        /// "%d pages" — page-count summary under each notebook card in
        /// the picker grid. Translators will provide `.stringsdict`
        /// plural rules eventually; until then a single format string
        /// handles English's two cases approximately.
        static func pageCount(_ count: Int) -> String {
            String.localizedStringWithFormat(
                NSLocalizedString(
                    "notebookPicker.pageCount",
                    value: "%d pages",
                    comment: "Page-count summary shown under each notebook card in the picker grid. %d is the page count."
                ),
                count
            )
        }

        /// "Page %d" — the label rendered under each page thumbnail in
        /// the "Specific page" grid. `%d` is 1-indexed for human reading.
        static func pageNumberLabel(_ oneBasedIndex: Int) -> String {
            String.localizedStringWithFormat(
                NSLocalizedString(
                    "notebookPicker.page.numberLabel",
                    value: "Page %d",
                    comment: "Caption under each page thumbnail in the picker's expanded page grid. %d is the 1-based page number."
                ),
                oneBasedIndex
            )
        }
    }
}
