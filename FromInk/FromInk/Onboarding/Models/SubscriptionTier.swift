import Foundation

/// The three subscription/purchase tiers offered on the paywall.
///
/// Per the subscription EDD §2, From Ink Plus ships three SKUs:
/// `.lifetime` (one-time non-consumable IAP at $19.99, default-selected),
/// `.yearly` (auto-renewable subscription at $14.99/year), and
/// `.monthly` (auto-renewable subscription at $2.99/month). The tiers
/// differ in payment cadence; the feature set is identical.
///
/// Lifetime is the brand-position default — see EDD §5.5 for rationale.
///
enum SubscriptionTier: String, Equatable, Hashable, Sendable, CaseIterable, Identifiable {
    case lifetime
    case yearly
    case monthly

    var id: String { rawValue }
}
