import Foundation

extension AppStrings {
    enum RegionIndicator {
        static let headerBadgeAccessibility = NSLocalizedString(
            "regionIndicator.badge.header",
            value: "Header",
            comment: "VoiceOver label for the bookmark icon shown on a NoteRegion indicator when the region carries an OCR'd header text."
        )

        static let linkBadgeAccessibility = NSLocalizedString(
            "regionIndicator.badge.link",
            value: "External link",
            comment: "VoiceOver label for the link icon shown on a NoteRegion indicator when the region carries an external URL."
        )

        static let crossRefBadgeAccessibility = NSLocalizedString(
            "regionIndicator.badge.crossReference",
            value: "Cross-reference link",
            comment: "VoiceOver label for the arrow-circle icon shown on a NoteRegion indicator when the region links to another notebook page."
        )

        static let pdfBadgeAccessibility = NSLocalizedString(
            "regionIndicator.badge.pdf",
            value: "PDF link",
            comment: "VoiceOver label for the document icon shown on a NoteRegion indicator when the region links to a PDF."
        )

        static let brokenLinkBadgeAccessibility = NSLocalizedString(
            "regionIndicator.badge.brokenLink",
            value: "Broken link \u{2014} tap to repair",
            comment: "VoiceOver label for the broken-link icon shown on a NoteRegion indicator when the persisted link target can't be parsed."
        )

        static let manageAccessibility = NSLocalizedString(
            "regionIndicator.manage",
            value: "Manage region",
            comment: "VoiceOver label for the ellipsis chip on a NoteRegion indicator that opens a manage menu (Edit header, Edit link, Delete region, etc.)."
        )

        static let manageTitle = NSLocalizedString(
            "regionIndicator.manage.title",
            value: "Manage region",
            comment: "Title of the action sheet shown when the user taps the manage ellipsis on a NoteRegion indicator."
        )

        static let manageEditHeader = NSLocalizedString(
            "regionIndicator.manage.editHeader",
            value: "Edit header",
            comment: "Action sheet button that opens the header text editor for a NoteRegion."
        )

        static let manageEditLink = NSLocalizedString(
            "regionIndicator.manage.editLink",
            value: "Edit link",
            comment: "Action sheet button that opens the link editor for a NoteRegion."
        )

        static let manageDelete = NSLocalizedString(
            "regionIndicator.manage.delete",
            value: "Delete region",
            comment: "Destructive action sheet button that deletes the NoteRegion (preserves any event/reminder/PDF associations attached to it)."
        )

        static let manageCancel = NSLocalizedString(
            "regionIndicator.manage.cancel",
            value: "Cancel",
            comment: "Cancel button on the NoteRegion manage action sheet."
        )

        static let headerEditTitle = NSLocalizedString(
            "regionIndicator.headerEdit.title",
            value: "Edit header",
            comment: "Title of the modal sheet that edits a NoteRegion's header text."
        )

        static let headerEditPlaceholder = NSLocalizedString(
            "regionIndicator.headerEdit.placeholder",
            value: "Header text",
            comment: "Text field placeholder shown in the NoteRegion header edit modal."
        )

        static let headerEditSave = NSLocalizedString(
            "regionIndicator.headerEdit.save",
            value: "Save",
            comment: "Confirmation button for the NoteRegion header edit modal."
        )

        static let headerEditCancel = NSLocalizedString(
            "regionIndicator.headerEdit.cancel",
            value: "Cancel",
            comment: "Cancel button for the NoteRegion header edit modal."
        )
    }
}
