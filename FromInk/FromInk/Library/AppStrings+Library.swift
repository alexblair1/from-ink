import Foundation

extension AppStrings {
    enum Library {
        static let title = NSLocalizedString("library.title", value: "From Ink", comment: "Library screen nav bar title")
        static let folders = NSLocalizedString("library.folders", value: "Folders", comment: "Folders section header")
        static let notebooks = NSLocalizedString("library.notebooks", value: "Notebooks", comment: "Notebooks section header")
        static let searchPlaceholder = NSLocalizedString("library.search.placeholder", value: "Search notebooks", comment: "Library search field placeholder")
        static let newNotebook = NSLocalizedString("library.newNotebook", value: "New Notebook", comment: "New notebook sheet title")
        static let createAndOpen = NSLocalizedString("library.createAndOpen", value: "Create & Open", comment: "Create notebook and open it")
        static let emptyTitle = NSLocalizedString("library.empty.title", value: "No notebooks yet", comment: "Empty state when no notebooks exist")
        static let myNotebook = NSLocalizedString("library.myNotebook", value: "My Notebook", comment: "Default first notebook name")

        static func folderCount(_ count: Int) -> String {
            String.localizedStringWithFormat(
                NSLocalizedString("library.folderCount", value: "%d FOLDERS", comment: "Number of folders"),
                count
            )
        }

        static func notebookCount(_ count: Int) -> String {
            String.localizedStringWithFormat(
                NSLocalizedString("library.notebookCount", value: "%d NOTEBOOKS", comment: "Number of notebooks"),
                count
            )
        }
    }
}
