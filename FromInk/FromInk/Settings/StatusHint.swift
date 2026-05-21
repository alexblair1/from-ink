import SwiftUI

/// Right-aligned summary text in a settings row that answers "do I
/// need to look in here?" before the user taps. Per the design's
/// principle 03: status before tap.
///
/// V1 ships only the `neutral` case — quiet prose-grey hint text
/// (e.g., the current Appearance value "System"). The design also
/// calls for an `attention` flag-red mono treatment for things like
/// "1 NEEDS AUTH" on Integrations, but no surface in V1 has the
/// underlying data to populate it. When the first attention hint
/// lands (Integrations gains auth state, Permissions gains denied
/// state, etc.), this enum gains an `.attention(String)` case in
/// the same slice that adds the `ink/FlagRed` color asset — no
/// speculative tokens.
///
enum StatusHint: Equatable {
    case neutral(String)
}

extension StatusHint {
    /// User-visible text for the hint. Centralized so the row view
    /// pattern-matches once.
    var text: String {
        switch self {
        case .neutral(let value): value
        }
    }
}
