import Foundation

/// The canonical domain model for a task extracted from ink.
/// Maps to Linear issues, GitHub issues, Apple Reminders, Calendar events, and Mail drafts.
struct InkTask: Identifiable, Codable, Hashable {

    // MARK: - Core fields (universal across all destinations)

    let id: UUID
    /// Short title — maps to Linear/GitHub title, Reminder title, Calendar title, Mail subject.
    var title: String
    /// Full description or notes — maps to Linear description, GitHub body,
    /// Reminder notes, Calendar notes, Mail body.
    var body: String
    /// Display subtitle shown in task rows (e.g. "Due Fri · Cycle 12").
    /// Derived from OCR context; not sent to integrations directly.
    var detail: String
    /// Deadline or scheduled start date — Linear due date, Reminder due date, Calendar start.
    var dueDate: Date?
    var priority: TaskPriority
    /// Tags / project labels — Linear labels, GitHub labels.
    var labels: [String]
    /// Which integrations this task should be sent to.
    var destinations: Set<Integration>
    /// Destination-specific overrides that don't fit the universal fields above.
    var context: DestinationContext

    let extractedAt: Date
    var completedAt: Date?

    // MARK: - Init

    init(
        id: UUID = UUID(),
        title: String,
        body: String = "",
        detail: String = "",
        dueDate: Date? = nil,
        priority: TaskPriority = .none,
        labels: [String] = [],
        destinations: Set<Integration> = [],
        context: DestinationContext = DestinationContext(),
        extractedAt: Date = .now,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.detail = detail
        self.dueDate = dueDate
        self.priority = priority
        self.labels = labels
        self.destinations = destinations
        self.context = context
        self.extractedAt = extractedAt
        self.completedAt = completedAt
    }
}

// MARK: - DestinationContext

extension InkTask {
    /// Overrides and extra fields that only apply to specific destinations.
    struct DestinationContext: Codable, Hashable {

        // Linear
        var linearTeamId: String?
        var linearProjectId: String?
        var linearCycleId: String?
        var linearAssigneeId: String?

        // GitHub
        var githubRepository: String?
        var githubMilestone: String?
        var githubAssignees: [String]

        // Calendar (dueDate maps to start; end and extras go here)
        var calendarEndDate: Date?
        var calendarLocation: String?
        var calendarIsAllDay: Bool?

        // Mail
        var mailRecipients: [String]

        // Reminders
        var remindersListName: String?

        init(
            linearTeamId: String? = nil,
            linearProjectId: String? = nil,
            linearCycleId: String? = nil,
            linearAssigneeId: String? = nil,
            githubRepository: String? = nil,
            githubMilestone: String? = nil,
            githubAssignees: [String] = [],
            calendarEndDate: Date? = nil,
            calendarLocation: String? = nil,
            calendarIsAllDay: Bool? = nil,
            mailRecipients: [String] = [],
            remindersListName: String? = nil
        ) {
            self.linearTeamId = linearTeamId
            self.linearProjectId = linearProjectId
            self.linearCycleId = linearCycleId
            self.linearAssigneeId = linearAssigneeId
            self.githubRepository = githubRepository
            self.githubMilestone = githubMilestone
            self.githubAssignees = githubAssignees
            self.calendarEndDate = calendarEndDate
            self.calendarLocation = calendarLocation
            self.calendarIsAllDay = calendarIsAllDay
            self.mailRecipients = mailRecipients
            self.remindersListName = remindersListName
        }
    }
}
