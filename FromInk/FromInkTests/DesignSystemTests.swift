import XCTest
@testable import FromInk

final class DesignSystemTests: XCTestCase {

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

    func test_layoutTokens_toolbarIconSize() {
        XCTAssertEqual(LayoutTokens.standard.toolbarIconSize, 20)
    }

    func test_layoutTokens_dragHandleDimensions() {
        XCTAssertEqual(LayoutTokens.standard.dragHandleCapsuleWidth, 20)
        XCTAssertEqual(LayoutTokens.standard.dragHandleCapsuleHeight, 2)
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

    // MARK: - DesignSystem standard instance

    func test_standardInstance_hasExpectedTokens() {
        let ds = DesignSystem.standard
        XCTAssertEqual(ds.spacing.base, 16)
        XCTAssertEqual(ds.layout.hitTarget, 44)
        XCTAssertEqual(ds.cornerRadius.content, 0)
    }
}
