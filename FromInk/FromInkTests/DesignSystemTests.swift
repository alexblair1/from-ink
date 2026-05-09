import XCTest
@testable import FromInk

@MainActor
final class DesignSystemTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        DesignSystem.use(.standard)
    }

    // MARK: - DesignSystem.current

    func test_current_defaultsToStandard() {
        let current = DesignSystem.current
        XCTAssertEqual(current.spacing.base, 16)
        XCTAssertEqual(current.layout.hitTarget, 44)
        XCTAssertEqual(current.cornerRadius.content, 0)
    }

    func test_use_replacesCurrent() {
        addTeardownBlock { @MainActor in
            DesignSystem.use(.standard)
        }

        let custom = DesignSystem(
            colors: .standard,
            typography: .standard,
            spacing: SpacingScale(
                xxs: 1,
                xs: 2,
                sm: 4,
                md: 6,
                base: 8,
                lg: 12,
                xl: 16,
                xxl: 24
            ),
            layout: .standard,
            animation: .standard,
            cornerRadius: .standard
        )

        DesignSystem.use(custom)
        XCTAssertEqual(DesignSystem.current.spacing.base, 8)
    }

    func test_withDesignSystem_restoresPrevious() {
        let custom = DesignSystem(
            colors: .standard,
            typography: .standard,
            spacing: SpacingScale(
                xxs: 1,
                xs: 2,
                sm: 4,
                md: 6,
                base: 8,
                lg: 12,
                xl: 16,
                xxl: 24
            ),
            layout: .standard,
            animation: .standard,
            cornerRadius: .standard
        )

        DesignSystem.withDesignSystem(custom) {
            XCTAssertEqual(DesignSystem.current.spacing.base, 8)
        }

        XCTAssertEqual(DesignSystem.current.spacing.base, 16)
    }

    func test_withDesignSystem_restoresOnThrow() {
        struct TestError: Error {}

        let custom = DesignSystem(
            colors: .standard,
            typography: .standard,
            spacing: SpacingScale(
                xxs: 1,
                xs: 2,
                sm: 4,
                md: 6,
                base: 8,
                lg: 12,
                xl: 16,
                xxl: 24
            ),
            layout: .standard,
            animation: .standard,
            cornerRadius: .standard
        )

        do {
            try DesignSystem.withDesignSystem(custom) {
                XCTAssertEqual(DesignSystem.current.spacing.base, 8)
                throw TestError()
            }
            XCTFail("Should have thrown")
        } catch {
            // Expected
        }

        XCTAssertEqual(DesignSystem.current.spacing.base, 16)
    }

    // MARK: - SpacingScale

    func test_spacingScale_values() {
        let s = SpacingScale.standard
        XCTAssertEqual(s.xxs, 2)
        XCTAssertEqual(s.xs, 4)
        XCTAssertEqual(s.sm, 8)
        XCTAssertEqual(s.md, 12)
        XCTAssertEqual(s.base, 16)
        XCTAssertEqual(s.lg, 24)
        XCTAssertEqual(s.xl, 32)
        XCTAssertEqual(s.xxl, 48)
    }

    // MARK: - LayoutTokens

    func test_layoutTokens_hitTarget() {
        XCTAssertEqual(LayoutTokens.standard.hitTarget, 44)
    }

    func test_layoutTokens_toolbarDimensions() {
        XCTAssertEqual(LayoutTokens.standard.toolbarWidth, 48)
        XCTAssertEqual(LayoutTokens.standard.toolbarButtonHeight, 54)
    }

    // MARK: - CornerRadiusScale

    func test_cornerRadius_contentIsZero() {
        XCTAssertEqual(CornerRadiusScale.standard.content, 0)
    }

    func test_cornerRadius_chromeValues() {
        let cr = CornerRadiusScale.standard
        XCTAssertEqual(cr.chip, 6)
        XCTAssertEqual(cr.row, 10)
        XCTAssertEqual(cr.sheet, 14)
    }

    // MARK: - ColorTokens semantic aliases

    func test_colorTokens_tintAliasesInk() {
        let c = ColorTokens.standard
        XCTAssertEqual(c.tint, c.ink)
    }

    func test_colorTokens_selectionAliasesHighlight() {
        let c = ColorTokens.standard
        XCTAssertEqual(c.selection, c.highlight)
    }

    func test_colorTokens_labelAliases() {
        let c = ColorTokens.standard
        XCTAssertEqual(c.primaryLabel, c.ink)
        XCTAssertEqual(c.secondaryLabel, c.ink2)
        XCTAssertEqual(c.tertiaryLabel, c.ink3)
    }

    func test_colorTokens_separatorAliasesRule() {
        let c = ColorTokens.standard
        XCTAssertEqual(c.separator, c.rule)
    }

    // MARK: - TypographyTokens

    func test_displayProducesDifferentFontsForDifferentSizes() {
        let t = TypographyTokens.standard
        XCTAssertNotEqual(t.display(size: 24), t.display(size: 96))
    }

    func test_numeralsProducesDifferentFontsForDifferentSizes() {
        let t = TypographyTokens.standard
        XCTAssertNotEqual(t.numerals(size: 32), t.numerals(size: 56))
    }
}
