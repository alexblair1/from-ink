import Foundation

extension AppStrings {
    enum Home {
        static let title = NSLocalizedString("home.title", value: "From Ink", comment: "Home screen wordmark")
        static let editorsNote = NSLocalizedString("home.editorsNote", value: "Editor's note", comment: "AI editorial section label")
        static let highlights = NSLocalizedString("home.highlights", value: "Highlights", comment: "Brief highlights section label")
        static let collapse = NSLocalizedString("home.collapse", value: "Collapse", comment: "Collapse expanded brief")
        static let readMore = NSLocalizedString("home.readMore", value: "Read More", comment: "Expand brief")
        static let viewDetails = NSLocalizedString("home.viewDetails", value: "View details", comment: "View full brief details")
        static let startWriting = NSLocalizedString("home.startWriting", value: "Start writing", comment: "Empty state title")
        static let emptySubtitle = NSLocalizedString("home.emptySubtitle", value: "Create your first notebook to begin.", comment: "Empty state subtitle")
        static let newNotebook = NSLocalizedString("home.newNotebook", value: "New Notebook", comment: "New notebook button/dialog title")
        static let createAndOpen = NSLocalizedString("home.createAndOpen", value: "Create & Open", comment: "Create and open new notebook")
        static let searchPlaceholder = NSLocalizedString("home.searchPlaceholder", value: "Search folders, notebooks and pages", comment: "Home search placeholder")
        static let dailyBrief = NSLocalizedString("home.dailyBrief", value: "Daily brief", comment: "Daily brief section label")
        static let lastModified = NSLocalizedString("home.lastModified", value: "Last modified", comment: "Notebooks sort label")
        static let nextUp = NSLocalizedString("home.nextUp", value: "Next up", comment: "Next event highlight label")
        static let overdue = NSLocalizedString("home.overdue", value: "Overdue", comment: "Overdue reminder label")
        static let today = NSLocalizedString("home.today", value: "Today", comment: "Today reminder label")
        static let birthday = NSLocalizedString("home.birthday", value: "Birthday", comment: "Birthday highlight label")
        static let titleLabel = NSLocalizedString("home.titleLabel", value: "Title", comment: "Title field label")
        static let events = NSLocalizedString("home.events", value: "events", comment: "Events count label")
        static let due = NSLocalizedString("home.due", value: "due", comment: "Due reminders count label")
    }
}
