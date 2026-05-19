import Foundation

/// A birthday item shown in the brief's "Birthdays" tab.
///
/// Sourced eventually from `CNContact` via the Contacts framework. For now
/// (V1 of the tab rework), the wiring view provides placeholder data — the
/// Contacts-backed pipeline is a separate slice.
///
struct StoredBirthday: Equatable, Sendable, Identifiable {
    let id: UUID
    let name: String
    /// Initials shown in the circular avatar (e.g. "CM" for Carla Mendez).
    let initials: String
    /// Short context line: "Friend · Seattle", "Family", etc. Nil when
    /// unknown — the row renders without it.
    let relationship: String?
    /// Long-form note: a sentence or two of editorial context. Nil hides
    /// the note line. Foundation Models will eventually generate this from
    /// past notebook references.
    let note: String?
    /// Birthday age label (e.g. "Turns 41"). Nil when birth year is
    /// unknown — common case for older contacts.
    let ageLabel: String?

    init(
        id: UUID = UUID(),
        name: String,
        initials: String,
        relationship: String? = nil,
        note: String? = nil,
        ageLabel: String? = nil
    ) {
        self.id = id
        self.name = name
        self.initials = initials
        self.relationship = relationship
        self.note = note
        self.ageLabel = ageLabel
    }
}
