import Foundation

/// The three sections the daily brief header tabs between. Matches the
/// React design source's "Calendar · Reminders · Birthdays" model — each
/// is a separate "source" with its own count and its own row template
/// inside the expanded body.
///
enum BriefTab: String, CaseIterable, Equatable, Sendable {
    case calendar
    case reminders
    case birthdays
}
