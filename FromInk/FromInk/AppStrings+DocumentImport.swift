import Foundation

extension AppStrings {
    enum DocumentImport {
        // Alert / dialog title (used by the error alert)
        static let title = NSLocalizedString(
            "documentImport.title",
            value: "Add a document",
            comment: "Title of the document-import error alert."
        )

        // Menu items
        static let importFileMenuItem = NSLocalizedString(
            "documentImport.menu.importFile",
            value: "Import file",
            comment: "Pull-down menu item that opens the system file picker."
        )

        static let scanDocumentMenuItem = NSLocalizedString(
            "documentImport.menu.scanDocument",
            value: "Scan document",
            comment: "Pull-down menu item that presents the VisionKit document scanner."
        )

        // Error messages
        static let filePickerFailedMessage = NSLocalizedString(
            "documentImport.error.filePickerFailed",
            value: "Couldn't open that file.",
            comment: "Shown when the system file picker reports an error reading the user's selection."
        )

        static let scannerFailedMessage = NSLocalizedString(
            "documentImport.error.scannerFailed",
            value: "Scanning failed. Try again, or grant camera access in Settings.",
            comment: "Shown when VNDocumentCameraViewController fails to present or reports an internal error — most commonly a permission state issue."
        )

        static let assemblyFailedMessage = NSLocalizedString(
            "documentImport.error.assemblyFailed",
            value: "Couldn't save the scanned pages. Try scanning again.",
            comment: "Shown when PDFAssemblyService fails to convert scanned images into a PDF."
        )

        // Alert dismissal button
        static let okay = NSLocalizedString(
            "documentImport.error.okay",
            value: "Okay",
            comment: "Acknowledge button on the document-import error alert."
        )
    }
}
