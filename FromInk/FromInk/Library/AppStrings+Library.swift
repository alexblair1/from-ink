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
        static let highlightSelectionMenuItem = NSLocalizedString(
            "library.pdfViewer.highlightSelection.menuItem",
            value: "Highlight",
            comment: "Item title in PDFView's text-selection edit menu that turns the current selection into a yellow highlight annotation"
        )
        static let annotationRemoveAction = NSLocalizedString(
            "library.pdfViewer.annotation.remove",
            value: "Remove",
            comment: "Edit-menu action that deletes the tapped PDF annotation"
        )

        // MARK: - Drawing mode

        static let drawingEnterButton = NSLocalizedString(
            "library.pdfViewer.drawing.enter",
            value: "Draw",
            comment: "Accessibility label for the top-bar button that enters drawing mode on the open PDF"
        )
        static let drawingDoneButton = NSLocalizedString(
            "library.pdfViewer.drawing.done",
            value: "Done",
            comment: "Button that commits the in-progress drawing and exits drawing mode"
        )
        static let drawingCancelButton = NSLocalizedString(
            "library.pdfViewer.drawing.cancel",
            value: "Cancel",
            comment: "Button that discards the in-progress drawing and exits drawing mode"
        )
        static let drawingToolPen = NSLocalizedString(
            "library.pdfViewer.drawing.tool.pen",
            value: "Pen",
            comment: "Accessibility label for the pen tool in the PDF drawing toolbar"
        )
        static let drawingToolPencil = NSLocalizedString(
            "library.pdfViewer.drawing.tool.pencil",
            value: "Pencil",
            comment: "Accessibility label for the pencil tool in the PDF drawing toolbar"
        )
        static let drawingToolMarker = NSLocalizedString(
            "library.pdfViewer.drawing.tool.marker",
            value: "Marker",
            comment: "Accessibility label for the marker / highlighter tool in the PDF drawing toolbar"
        )
        static let drawingToolEraser = NSLocalizedString(
            "library.pdfViewer.drawing.tool.eraser",
            value: "Eraser",
            comment: "Accessibility label for the eraser tool in the PDF drawing toolbar"
        )
        static let drawingToolLasso = NSLocalizedString(
            "library.pdfViewer.drawing.tool.lasso",
            value: "Lasso",
            comment: "Accessibility label for the lasso selection tool in the PDF drawing toolbar"
        )
        static let drawingWidthSmall = NSLocalizedString(
            "library.pdfViewer.drawing.width.small",
            value: "Thin",
            comment: "Accessibility label for the thinnest stroke width in the PDF drawing toolbar"
        )
        static let drawingWidthMedium = NSLocalizedString(
            "library.pdfViewer.drawing.width.medium",
            value: "Medium",
            comment: "Accessibility label for the medium stroke width in the PDF drawing toolbar"
        )
        static let drawingWidthLarge = NSLocalizedString(
            "library.pdfViewer.drawing.width.large",
            value: "Thick",
            comment: "Accessibility label for the thickest stroke width in the PDF drawing toolbar"
        )
        static let drawingUndoButton = NSLocalizedString(
            "library.pdfViewer.drawing.undo",
            value: "Undo",
            comment: "Accessibility label for the undo button in the PDF drawing toolbar"
        )
        static let drawingRedoButton = NSLocalizedString(
            "library.pdfViewer.drawing.redo",
            value: "Redo",
            comment: "Accessibility label for the redo button in the PDF drawing toolbar"
        )
        static let drawingColorBlack = NSLocalizedString(
            "library.pdfViewer.drawing.color.black",
            value: "Black ink",
            comment: "Accessibility label for the black ink color swatch"
        )
        static let drawingColorRed = NSLocalizedString(
            "library.pdfViewer.drawing.color.red",
            value: "Red ink",
            comment: "Accessibility label for the red ink color swatch"
        )
        static let drawingColorBlue = NSLocalizedString(
            "library.pdfViewer.drawing.color.blue",
            value: "Blue ink",
            comment: "Accessibility label for the blue ink color swatch"
        )
        static let drawingColorGreen = NSLocalizedString(
            "library.pdfViewer.drawing.color.green",
            value: "Green ink",
            comment: "Accessibility label for the green ink color swatch"
        )
        static let drawingColorYellow = NSLocalizedString(
            "library.pdfViewer.drawing.color.yellow",
            value: "Yellow ink",
            comment: "Accessibility label for the yellow ink color swatch"
        )
        static let searchButton = NSLocalizedString(
            "library.pdfViewer.search.button",
            value: "Search PDF",
            comment: "Accessibility label for the top-bar button that opens the in-PDF search field"
        )
        static let searchFieldPlaceholder = NSLocalizedString(
            "library.pdfViewer.search.placeholder",
            value: "Search",
            comment: "Placeholder text inside the in-PDF search field"
        )
        static let searchCloseButton = NSLocalizedString(
            "library.pdfViewer.search.close",
            value: "Close Search",
            comment: "Accessibility label for the button that exits in-PDF search and clears the query"
        )
        static let searchPreviousMatchButton = NSLocalizedString(
            "library.pdfViewer.search.previous",
            value: "Previous Match",
            comment: "Accessibility label for the chevron that steps to the previous in-PDF search match"
        )
        static let searchNextMatchButton = NSLocalizedString(
            "library.pdfViewer.search.next",
            value: "Next Match",
            comment: "Accessibility label for the chevron that steps to the next in-PDF search match"
        )
        static func searchMatchCount(current: Int, total: Int) -> String {
            String.localizedStringWithFormat(
                NSLocalizedString(
                    "library.pdfViewer.search.count",
                    value: "%1$d / %2$d",
                    comment: "Search-result counter shown next to in-PDF search controls; %1$d is the current match (1-based), %2$d is the total"
                ),
                current, total
            )
        }
        static let searchNoMatches = NSLocalizedString(
            "library.pdfViewer.search.noMatches",
            value: "No matches",
            comment: "Counter shown when an in-PDF search query returned zero results"
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
                    value: "This PDF is %@. From Ink limits imports to %@ to keep things smooth on iPhone and avoid eating your iCloud storage. Compress the PDF first — most PDF editors can reduce image quality or remove embedded fonts.",
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
