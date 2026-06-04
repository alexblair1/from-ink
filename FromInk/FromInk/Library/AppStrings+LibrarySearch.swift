import Foundation

extension AppStrings {
    enum LibrarySearch {
        static let searchPlaceholder = NSLocalizedString(
            "librarySearch.placeholder",
            value: "Search your library",
            comment: "Placeholder text for the library search field — shown across the browse surface and any future picker / quick-switcher uses."
        )

        static func emptyNoResults(_ query: String) -> String {
            String.localizedStringWithFormat(
                NSLocalizedString(
                    "librarySearch.empty.noResults",
                    value: "No matches for \u{201C}%@\u{201D}.",
                    comment: "Empty state when a non-empty search query returns zero hits. %@ is the user's query."
                ),
                query
            )
        }

        static let emptyLibrary = NSLocalizedString(
            "librarySearch.empty.library",
            value: "Your library is empty.",
            comment: "Empty state when the library has nothing in it (no query active)."
        )

        // MARK: - Row kind labels (mono uppercase chip on each result row)

        static let kindNotebook = NSLocalizedString(
            "librarySearch.kind.notebook",
            value: "NOTEBOOK",
            comment: "Mono-uppercase chip rendered next to a notebook result so the user can tell content kinds apart at a glance."
        )

        static let kindFolder = NSLocalizedString(
            "librarySearch.kind.folder",
            value: "FOLDER",
            comment: "Mono-uppercase chip rendered next to a folder result."
        )

        static let kindPDF = NSLocalizedString(
            "librarySearch.kind.pdf",
            value: "PDF",
            comment: "Mono-uppercase chip rendered next to a PDF result."
        )

        // MARK: - Browse surface chrome

        static let browseTitle = NSLocalizedString(
            "librarySearch.browse.title",
            value: "Library",
            comment: "Title bar text shown above the full-screen browse surface."
        )

        static let dismissAction = NSLocalizedString(
            "librarySearch.dismiss",
            value: "Close",
            comment: "VoiceOver label for the X button that dismisses the browse surface."
        )

        // MARK: - Per-kind count summaries (under each row's title)

        /// "12 pages" / "1 page" — currently single format, locale-plural
        /// handled by translators via `.stringsdict` when shipped.
        static func pageCount(_ count: Int) -> String {
            String.localizedStringWithFormat(
                NSLocalizedString(
                    "librarySearch.pageCount",
                    value: "%d pages",
                    comment: "Page-count summary shown under a notebook or PDF result row. %d is the page count."
                ),
                count
            )
        }

        static func notebookCount(_ count: Int) -> String {
            String.localizedStringWithFormat(
                NSLocalizedString(
                    "librarySearch.notebookCount",
                    value: "%d notebooks",
                    comment: "Notebook-count summary shown under a folder result row. %d is the notebook count."
                ),
                count
            )
        }
    }
}
