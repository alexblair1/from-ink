import SwiftUI

/// 4pt grid spacing values. Six core values plus two edge cases (xxs, xxl).
/// If a layout calls for a value outside this set, the layout is wrong, not the scale.
///
struct SpacingScale: Sendable {
    let xxs:  CGFloat
    let xs:   CGFloat
    let sm:   CGFloat
    let md:   CGFloat
    let base: CGFloat
    let lg:   CGFloat
    let xl:   CGFloat
    let xxl:  CGFloat

    static let standard = SpacingScale(
        xxs:  2,
        xs:   4,
        sm:   8,
        md:   12,
        base: 16,
        lg:   24,
        xl:   32,
        xxl:  48
    )
}

/// Fixed structural dimensions for chrome — not part of the spacing rhythm.
///
struct LayoutTokens: Sendable {
    let hitTarget: CGFloat
    let toolbarWidth: CGFloat
    let toolbarButtonHeight: CGFloat
    let navBarHeight: CGFloat
    let sheetHeaderHeight: CGFloat
    let footerHeight: CGFloat
    let dialogActionHeight: CGFloat
    let iconFrame: CGFloat
    let thumbnailSize: CGFloat
    let dialogWidth: CGFloat
    let panelWidth: CGFloat
    let headerSpacer: CGFloat
    let toolHitTarget: CGFloat
    let toolbarIconSize: CGFloat
    let dragHandleCapsuleWidth: CGFloat
    let dragHandleCapsuleHeight: CGFloat
    let dragHandleCapsuleSpacing: CGFloat
    let dragHandleSwitchThreshold: CGFloat
    let toolbarPanelGap: CGFloat
    let toolbarActiveIndicatorWidth: CGFloat
    let borderWidth: CGFloat
    let actionIconSize: CGFloat
    let timeBlockWidth: CGFloat
    let spineMinHeight: CGFloat

    static let standard = LayoutTokens(
        hitTarget: 44,
        toolbarWidth: 48,
        toolbarButtonHeight: 54,
        navBarHeight: 44,
        sheetHeaderHeight: 52,
        footerHeight: 60,
        dialogActionHeight: 48,
        iconFrame: 24,
        thumbnailSize: 64,
        dialogWidth: 300,
        panelWidth: 420,
        headerSpacer: 60,
        toolHitTarget: 48,
        toolbarIconSize: 20,
        dragHandleCapsuleWidth: 20,
        dragHandleCapsuleHeight: 2,
        dragHandleCapsuleSpacing: 3,
        dragHandleSwitchThreshold: 40,
        toolbarPanelGap: 8,
        toolbarActiveIndicatorWidth: 3,
        borderWidth: 1,
        actionIconSize: 17,
        timeBlockWidth: 72,
        spineMinHeight: 140
    )
}

/// Corner radii. Content surfaces use 0 (hairline rules are the structural element).
///
struct CornerRadiusScale: Sendable {
    let content: CGFloat
    let chip: CGFloat
    let row: CGFloat
    let sheet: CGFloat

    static let standard = CornerRadiusScale(
        content: 0,
        chip: 6,
        row: 10,
        sheet: 14
    )
}

/// Linear only — no spring physics, no bounce.
/// 80–120ms range per CLAUDE.md design principles.
///
struct AnimationTokens: Sendable {
    /// 80ms — tool selection, icon state changes.
    let fast: Animation
    /// 100ms — toolbar visibility, panel slides.
    let standard: Animation
    /// 120ms — page-level transitions.
    let slow: Animation

    static let standard = AnimationTokens(
        fast: .linear(duration: 0.08),
        standard: .linear(duration: 0.10),
        slow: .linear(duration: 0.12)
    )
}
