import SwiftUI

// MARK: - Legacy Design System
//
// DEPRECATED: This file exists only to support existing code that has not yet
// been migrated to the new design system (DesignSystem.swift, ColorTokens.swift,
// TypographyTokens.swift, SpacingScale.swift).
//
// Migration: replace `@Environment(\.ds)` and `private let ds = DesignSystem.standard`
// references with the new `DesignSystem.current` / `Style.standard` pattern.
// Once all consumers are migrated, delete this file.

// MARK: - Legacy Environment Injection

private struct LegacyDesignSystemKey: EnvironmentKey {
    @MainActor static let defaultValue = DesignSystem.standard
}

extension EnvironmentValues {
    var ds: DesignSystem {
        get { self[LegacyDesignSystemKey.self] }
        set { self[LegacyDesignSystemKey.self] = newValue }
    }
}

extension View {
    func designSystem(_ ds: DesignSystem) -> some View {
        environment(\.ds, ds)
    }
}
