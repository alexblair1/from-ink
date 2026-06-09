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
    let tabIconSize: CGFloat
    let dismissIconSize: CGFloat
    let dismissHitTarget: CGFloat
    let headerPreviewMinHeight: CGFloat
    let timeBlockWidth: CGFloat
    let spineMinHeight: CGFloat
    let notebookCardWidth: CGFloat
    let notebookCardHeight: CGFloat
    let notebookSpineWidth: CGFloat
    let notebookCardSpacing: CGFloat
    let searchIconSize: CGFloat
    let chevronSize: CGFloat
    let labelIconSize: CGFloat
    let emptyStateIconSize: CGFloat
    let mastheadTracking: CGFloat
    let scrimOpacity: Double
    /// Onboarding custom Switch — track outer width.
    let onboardingSwitchTrackWidth: CGFloat
    /// Onboarding custom Switch — track height (capsule).
    let onboardingSwitchTrackHeight: CGFloat
    /// Onboarding custom Switch — thumb diameter.
    let onboardingSwitchThumbDiameter: CGFloat
    /// Onboarding custom Switch — inset between thumb and track edge.
    let onboardingSwitchThumbInset: CGFloat
    /// Width of the icon column on each value-screen feature row.
    /// Sized for the smaller 20pt-ish SF Symbols used in value rows.
    let onboardingFeatureRowIconColumn: CGFloat
    /// Width of the icon column on permissions rows and the
    /// informational microphone card. Sized for the larger 22pt SF
    /// Symbols used in those rows.
    let onboardingPermissionRowIconColumn: CGFloat

    // MARK: - Floating chrome (capsule toolbar, accessory bar, slash menu)
    //
    // Floating chrome elements detach from the screen edge and convey
    // elevation via shadow + border + corner radius. See `ShadowTokens`
    // for the matching shadow values. These tokens are reused by the
    // notebook toolbar today and by the text accessory bar / slash menu
    // when the text experience lands.

    /// Capsule corner radius. 26pt produces a true capsule for the
    /// 50pt-wide button column plus padding (50 + 10×2 = 70 → radius
    /// equal to half-height of an 8-button stack would over-round; 26
    /// keeps the pill ends round and the sides barely flat).
    let toolbarCapsuleCornerRadius: CGFloat
    /// Horizontal inset between the capsule and the screen edge.
    let toolbarCapsuleHorizontalInset: CGFloat
    /// Vertical inset between the capsule and the safe-area top / bottom.
    let toolbarCapsuleVerticalInset: CGFloat
    /// Horizontal padding inside the capsule (capsule wall → button column).
    let toolbarCapsulePaddingHorizontal: CGFloat
    /// Vertical padding inside the capsule (capsule top/bottom → first/last button).
    let toolbarCapsulePaddingVertical: CGFloat
    /// Vertical gap between buttons inside the capsule.
    let toolbarCapsuleInterItemSpacing: CGFloat
    /// Minimum vertical breathing room between the top and bottom capsules.
    /// The top capsule's content starts scrolling when allocating less than
    /// this gap to the gap would otherwise be required.
    let toolbarCapsuleMinPillGap: CGFloat
    /// Width of the hairline rule that separates sections inside a capsule
    /// (e.g. tools vs ink readout in the top capsule).
    let toolbarCapsuleInternalRuleWidth: CGFloat
    /// Round button diameter inside a capsule. Buttons are circular —
    /// width and height are this value, corner radius is half of it.
    let toolbarCapsuleButtonSize: CGFloat
    /// Scale applied to an active (selected) button. Cubic-bezier
    /// `pop` motion in the prototype maps to a linear lift in our
    /// animation system; the visible effect is the scale value.
    let toolbarCapsuleActiveScale: CGFloat

    // MARK: - Ink readout (bottom of the top capsule)

    /// Diameter of the inked color chip.
    let inkReadoutChipSize: CGFloat
    /// Thickness of the paper ring around the chip (inner ring).
    let inkReadoutChipInnerRingWidth: CGFloat
    /// Thickness of the rule ring around the chip (outer ring).
    let inkReadoutChipOuterRingWidth: CGFloat
    /// Number of weight pips rendered. The pips visualize the active
    /// stroke thickness — diameter scales with `thicknessIndex`.
    let inkReadoutPipCount: Int
    /// Minimum pip diameter (at thinnest stroke).
    let inkReadoutPipMinSize: CGFloat
    /// Maximum pip diameter (at thickest stroke).
    let inkReadoutPipMaxSize: CGFloat
    /// Horizontal gap between adjacent pips.
    let inkReadoutPipGap: CGFloat
    /// Vertical gap between the chip and the pip row.
    let inkReadoutSectionGap: CGFloat

    // MARK: - Text editor

    /// Maximum content width for the text editor on wide viewports.
    /// Optimal reading line length is 50–75 characters (~480–720pt at
    /// body size); 640pt is the high end of comfortable for serif
    /// notebook content. iPad full-screen and Mac wider windows
    /// constrain to this and center the editor.
    let textEditorMaxContentWidth: CGFloat

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
        tabIconSize: 15,
        dismissIconSize: 12,
        dismissHitTarget: 28,
        headerPreviewMinHeight: 80,
        timeBlockWidth: 72,
        spineMinHeight: 140,
        notebookCardWidth: 116,
        notebookCardHeight: 154,
        notebookSpineWidth: 6,
        notebookCardSpacing: 18,
        searchIconSize: 16,
        chevronSize: 14,
        labelIconSize: 11,
        emptyStateIconSize: 36,
        mastheadTracking: -1.12,
        scrimOpacity: 0.25,
        onboardingSwitchTrackWidth: 48,
        onboardingSwitchTrackHeight: 28,
        onboardingSwitchThumbDiameter: 22,
        onboardingSwitchThumbInset: 3,
        onboardingFeatureRowIconColumn: 30,
        onboardingPermissionRowIconColumn: 34,
        toolbarCapsuleCornerRadius: 26,
        toolbarCapsuleHorizontalInset: 18,
        toolbarCapsuleVerticalInset: 26,
        toolbarCapsulePaddingHorizontal: 10,
        toolbarCapsulePaddingVertical: 12,
        toolbarCapsuleInterItemSpacing: 4,
        toolbarCapsuleMinPillGap: 40,
        toolbarCapsuleInternalRuleWidth: 26,
        toolbarCapsuleButtonSize: 50,
        // Active scale removed (1.0). `scaleEffect` inside a ScrollView
        // clips at scroll bounds, cropping the top of the active button
        // when it sits flush against the capsule wall. Color inversion
        // (paper-on-ink) is sufficient signal for the active state.
        toolbarCapsuleActiveScale: 1.0,
        inkReadoutChipSize: 22,
        inkReadoutChipInnerRingWidth: 1.5,
        inkReadoutChipOuterRingWidth: 1,
        inkReadoutPipCount: 3,
        inkReadoutPipMinSize: 3,
        inkReadoutPipMaxSize: 6,
        inkReadoutPipGap: 4,
        inkReadoutSectionGap: 9,
        textEditorMaxContentWidth: 640
    )
}

// MARK: - Floating-chrome shadows

/// Drop-shadow tokens for floating chrome — capsule toolbar, accessory
/// bar, slash menu popovers. Content surfaces still ship no shadows per
/// the design principles in `CLAUDE.md`; shadows live here so chrome can
/// convey elevation without the rule leaking into list rows or canvas
/// content.
///
/// Two layers compose into the final shadow:
///   - `primary` — the soft, far-cast drop that anchors the element
///   - `ambient` — the close, low-y shadow that grounds it to the surface
///
/// SwiftUI shadows don't have spread; the prototype CSS uses negative
/// spread to tighten the shadow against its source. We approximate by
/// choosing tighter radii at higher opacity for ambient, looser at
/// lower opacity for primary.
struct ShadowTokens: Sendable {
    let toolbarCapsulePrimary: Shadow
    let toolbarCapsuleAmbient: Shadow
    let toolbarActiveButton: Shadow

    struct Shadow: Sendable {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    static let standard = ShadowTokens(
        toolbarCapsulePrimary: Shadow(
            color: Color(red: 31 / 255, green: 29 / 255, blue: 26 / 255).opacity(0.10),
            radius: 18,
            x: 0,
            y: 10
        ),
        toolbarCapsuleAmbient: Shadow(
            color: Color(red: 31 / 255, green: 29 / 255, blue: 26 / 255).opacity(0.05),
            radius: 4,
            x: 0,
            y: 2
        ),
        // Active button shadow disabled — the inverted color already
        // signals selection clearly, and a halo inside the tight capsule
        // padding reads as smudge rather than elevation. Kept as a token
        // for future tuning rather than removed from the design system.
        toolbarActiveButton: Shadow(
            color: .clear,
            radius: 0,
            x: 0,
            y: 0
        )
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
