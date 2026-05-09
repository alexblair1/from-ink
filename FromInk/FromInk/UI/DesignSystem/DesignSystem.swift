import SwiftUI

// MARK: - Design System

/// Value-type token bundle for From Ink.
/// Accessed through `DesignSystem.current` (a `@MainActor`-isolated static).
/// Component views never read this directly — they read `model.style.*`.
/// Feature views may use `private let ds = DesignSystem.standard` or
/// read tokens through `DesignSystem.current` inside `Style.standard`.
///
/// See Documentation/design_system_edd.md for the full specification.
///
struct DesignSystem: Sendable {
    let colors: ColorTokens
    let typography: TypographyTokens
    let spacing: SpacingScale
    let layout: LayoutTokens
    let animation: AnimationTokens
    let cornerRadius: CornerRadiusScale

    static let standard = DesignSystem(
        colors: .standard,
        typography: .standard,
        spacing: .standard,
        layout: .standard,
        animation: .standard,
        cornerRadius: .standard
    )
}

// MARK: - Injection Seam

extension DesignSystem {
    /// The active design system. v1 always returns `.standard`.
    /// Future settings UI calls `use(_:)` to swap themes.
    @MainActor
    static private(set) var current: DesignSystem = .standard

    /// Replace the active design system. v1 calls this at most once at app
    /// startup. Future settings UI calls this when the user selects a theme.
    @MainActor
    static func use(_ system: DesignSystem) {
        current = system
    }

    /// Run a closure with a temporarily replaced design system.
    /// Used by snapshot tests and per-preview theme variants.
    /// Restores the previous value on return.
    @MainActor
    static func withDesignSystem<T>(
        _ system: DesignSystem,
        perform: () throws -> T
    ) rethrows -> T {
        let previous = current
        current = system
        defer { current = previous }
        return try perform()
    }
}
