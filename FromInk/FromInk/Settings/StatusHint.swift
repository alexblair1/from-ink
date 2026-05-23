import SwiftUI

/// Right-aligned summary text in a settings row that answers "do I
/// need to look in here?" before the user taps. Per the design's
/// principle 03: status before tap.
///
/// Two presentations, distinguished by intent:
///   - `.neutral` — quiet prose-grey hint (ink-2). Used for the
///     current setting value: "System", "Right", "7:00 am".
///   - `.attention` — flag-red mono uppercase. Reserved for
///     user-actionable callouts that need immediate eye: "1 NEEDS
///     AUTH", "Re-authenticate", "Permissions denied". Color comes
///     from `ColorTokens.flagRed`; loudness is intentional and
///     sparing — overuse erodes the signal.
///
enum StatusHint: Equatable {
    case neutral(String)
    case attention(String)
}

extension StatusHint {
    /// User-visible text for the hint. Centralized so callers
    /// pattern-match once.
    var text: String {
        switch self {
        case .neutral(let value):   value
        case .attention(let value): value
        }
    }
}
