import Foundation

/// Global localized string namespace. Extend per feature:
///
///     // In Library/AppStrings+Library.swift
///     extension AppStrings {
///         enum Library {
///             static let title = NSLocalizedString("library.title", value: "Library", comment: "Library screen title")
///         }
///     }
///
///     // Usage in a component Model
///     Text(AppStrings.Library.title)
///
enum AppStrings {

    // MARK: - Common

    enum Common {
        static let cancel = NSLocalizedString("common.cancel", value: "Cancel", comment: "Cancel action")
        static let confirm = NSLocalizedString("common.confirm", value: "Confirm", comment: "Confirm action")
        static let create = NSLocalizedString("common.create", value: "Create", comment: "Create action")
        static let delete = NSLocalizedString("common.delete", value: "Delete", comment: "Delete action")
        static let done = NSLocalizedString("common.done", value: "Done", comment: "Done action")
        static let save = NSLocalizedString("common.save", value: "Save", comment: "Save action")
        static let search = NSLocalizedString("common.search", value: "Search", comment: "Search placeholder")
        static let untitled = NSLocalizedString("common.untitled", value: "Untitled", comment: "Default name for untitled items")
        /// Typographic "no value" placeholder. Em-dash by default —
        /// localized so RTL/CJK contexts can substitute (some scripts
        /// render em-dash with different width or replace it entirely).
        static let emptyValuePlaceholder = NSLocalizedString("common.emptyValuePlaceholder", value: "—", comment: "Placeholder rendered when a field has no value yet (em-dash by default)")
    }
}
