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

        // MARK: - PDF import

        static let importPDFButton = NSLocalizedString(
            "library.importPDF.button",
            value: "Import PDF",
            comment: "Accessibility label for the home-screen import-PDF button"
        )
        static let importPDFDuplicateTitle = NSLocalizedString(
            "library.importPDF.duplicate.title",
            value: "Already in Your Library",
            comment: "Alert title when a re-imported PDF is detected as a duplicate"
        )
        static func importPDFDuplicateMessage(title: String) -> String {
            String.localizedStringWithFormat(
                NSLocalizedString(
                    "library.importPDF.duplicate.message",
                    value: "%@ is already in your library. Opening the existing copy.",
                    comment: "Alert body for duplicate PDF; %@ is the PDF title"
                ),
                title
            )
        }
        static let importPDFFailedTitle = NSLocalizedString(
            "library.importPDF.failed.title",
            value: "Couldn't Import PDF",
            comment: "Alert title when PDF import fails"
        )
        static let pdfViewerLoadFailedMessage = NSLocalizedString(
            "library.pdfViewer.loadFailed.message",
            value: "Couldn't open this PDF right now. Try again, or remove and re-import it from your library.",
            comment: "Body shown in the PDF viewer when bytes can't load or PDFKit can't parse them"
        )
        static let highlightSelectionButton = NSLocalizedString(
            "library.pdfViewer.highlightSelection.button",
            value: "Highlight Selection",
            comment: "Accessibility label for the floating button that turns the current PDF text selection into a highlight"
        )
        static let annotationRemoveAction = NSLocalizedString(
            "library.pdfViewer.annotation.remove",
            value: "Remove",
            comment: "Edit-menu action that deletes the tapped PDF annotation"
        )
        static let importPDFOpenButton = NSLocalizedString(
            "library.importPDF.openButton",
            value: "Open",
            comment: "Alert button that confirms opening the existing duplicate PDF"
        )
        static let importPDFDismissButton = NSLocalizedString(
            "library.importPDF.dismissButton",
            value: "OK",
            comment: "Alert button that dismisses the import-failure alert"
        )
        static func importPDFTooLargeMessage(byteCount: Int, limit: Int) -> String {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useMB, .useGB]
            formatter.countStyle = .file
            let actual = formatter.string(fromByteCount: Int64(byteCount))
            let cap = formatter.string(fromByteCount: Int64(limit))
            return String.localizedStringWithFormat(
                NSLocalizedString(
                    "library.importPDF.tooLarge.message",
                    value: "This PDF is %@. From Ink syncs PDFs via iCloud, which has a %@ per-file limit. Compress the PDF first — most PDF editors can reduce image quality or remove embedded fonts.",
                    comment: "Alert body for oversized PDF; first %@ is actual size, second %@ is the limit"
                ),
                actual, cap
            )
        }
        static let importPDFInvalidMessage = NSLocalizedString(
            "library.importPDF.invalid.message",
            value: "From Ink couldn't read this file as a PDF. It may be corrupt or in an unsupported format.",
            comment: "Alert body when PDFKit can't parse the file"
        )
        static let importPDFAccessDeniedMessage = NSLocalizedString(
            "library.importPDF.accessDenied.message",
            value: "From Ink couldn't open this file. Try moving it to a location that From Ink can access (e.g. iCloud Drive or Files).",
            comment: "Alert body when security-scoped access is denied"
        )
        static let importPDFAttributesUnavailableMessage = NSLocalizedString(
            "library.importPDF.attributesUnavailable.message",
            value: "From Ink couldn't read file attributes. The file may have moved or been deleted.",
            comment: "Alert body when FileManager can't read file attributes"
        )

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
