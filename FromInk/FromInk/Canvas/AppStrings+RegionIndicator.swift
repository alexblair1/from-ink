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
    }
}
