import SwiftUI

/// Value-type token bundle for From Ink.
///
/// Plain immutable struct with a `static let standard` instance.
/// Component view Models resolve tokens at init time via a `ds: DesignSystem = .standard`
/// parameter. Views read flat fields off the Model — never from DesignSystem directly.
///
/// To add a theme later, add another static instance (e.g. `static let highContrast`)
/// and pass it through Model construction.
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
    /// Shadow + highlight values for the neumorphic "stamped paper"
    /// surface treatment used by tabs and any future stamped-paper UI.
    let neumorphicElevation: NeumorphicElevation
    /// Geometry of neumorphic tab strips (padding, content sizes,
    /// seam-killer dimensions, and the derived panel overlap).
    let neumorphicTab: NeumorphicTabStyle

    static let standard = DesignSystem(
        colors: .standard,
        typography: .standard,
        spacing: .standard,
        layout: .standard,
        animation: .standard,
        cornerRadius: .standard,
        neumorphicElevation: .standard,
        neumorphicTab: .standard
    )
}
