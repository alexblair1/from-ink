import SwiftUI
import XCTest
@testable import FromInk

/// Pins the `FromInkAttributes` custom attribute scope's serialization
/// contract.
///
/// The load-bearing claim: `AttributedString` carrying our custom
/// attributes (`regionAnchor`, `highlight`, `slashInsertion`)
/// round-trips through `JSONEncoder` / `JSONDecoder` losslessly when
/// passed the `FromInkAttributes` scope as `CodableConfiguration`.
///
/// This is what unlocks Path B in `PageBlockSnapshot.decodeBody`. If
/// the round-trip ever drops a custom attribute, every text-anchored
/// region in every text block silently loses its anchor on the next
/// save — the data-loss class of bug we wrote `decodeBody`'s scope-
/// aware encoder to prevent.
final class FromInkAttributesTests: XCTestCase {

    func test_regionAnchor_roundTripsThroughCodable() throws {
        let regionID = UUID()
        var attributed = AttributedString("Q3 budget meeting")
        let range = attributed.range(of: "Q3 budget")!
        attributed[range].fromInk.regionAnchor = regionID

        let data = try JSONEncoder().encode(
            attributed,
            configuration: AttributeScopes.FromInkAttributes.self
        )
        let decoded = try JSONDecoder().decode(
            AttributedString.self,
            from: data,
            configuration: AttributeScopes.FromInkAttributes.self
        )

        let recoveredRange = decoded.range(of: "Q3 budget")!
        XCTAssertEqual(decoded[recoveredRange].fromInk.regionAnchor, regionID)
    }

    func test_highlight_roundTripsThroughCodable() throws {
        var attributed = AttributedString("Important note")
        let range = attributed.range(of: "Important")!
        attributed[range].fromInk.highlight = .yellow

        let data = try JSONEncoder().encode(
            attributed,
            configuration: AttributeScopes.FromInkAttributes.self
        )
        let decoded = try JSONDecoder().decode(
            AttributedString.self,
            from: data,
            configuration: AttributeScopes.FromInkAttributes.self
        )

        let recoveredRange = decoded.range(of: "Important")!
        XCTAssertEqual(decoded[recoveredRange].fromInk.highlight, .yellow)
    }

    func test_slashInsertion_roundTripsThroughCodable() throws {
        var attributed = AttributedString("/divider")
        let range = attributed.range(of: "/divider")!
        attributed[range].fromInk.slashInsertion = SlashCommandID(rawValue: "divider")

        let data = try JSONEncoder().encode(
            attributed,
            configuration: AttributeScopes.FromInkAttributes.self
        )
        let decoded = try JSONDecoder().decode(
            AttributedString.self,
            from: data,
            configuration: AttributeScopes.FromInkAttributes.self
        )

        let recoveredRange = decoded.range(of: "/divider")!
        XCTAssertEqual(decoded[recoveredRange].fromInk.slashInsertion?.rawValue, "divider")
    }

    func test_multipleAttributes_onSameSpan_allRoundTrip() throws {
        // Region anchor + highlight on the same span — both must
        // survive. This is the realistic "I highlighted Q3 Budget AND
        // marked it as a region" composition from EDD §12.5.
        let regionID = UUID()
        var attributed = AttributedString("Q3 Budget")
        let range = attributed.range(of: "Q3 Budget")!
        attributed[range].fromInk.regionAnchor = regionID
        attributed[range].fromInk.highlight = .yellow

        let data = try JSONEncoder().encode(
            attributed,
            configuration: AttributeScopes.FromInkAttributes.self
        )
        let decoded = try JSONDecoder().decode(
            AttributedString.self,
            from: data,
            configuration: AttributeScopes.FromInkAttributes.self
        )

        let recoveredRange = decoded.range(of: "Q3 Budget")!
        XCTAssertEqual(decoded[recoveredRange].fromInk.regionAnchor, regionID)
        XCTAssertEqual(decoded[recoveredRange].fromInk.highlight, .yellow)
    }

    func test_plainAttributedString_roundTrips() throws {
        // Sanity: a body with no custom attributes still works.
        let attributed = AttributedString("Just plain text.")
        let data = try JSONEncoder().encode(
            attributed,
            configuration: AttributeScopes.FromInkAttributes.self
        )
        let decoded = try JSONDecoder().decode(
            AttributedString.self,
            from: data,
            configuration: AttributeScopes.FromInkAttributes.self
        )
        XCTAssertEqual(String(decoded.characters), "Just plain text.")
    }

    // MARK: - PageBlockSnapshot.encodeBody/decodeBody round-trip

    func test_encodeBodyDecodeBody_preservesCustomAttributes() throws {
        let regionID = UUID()
        var original = AttributedString("Follow up with Sarah")
        let range = original.range(of: "Sarah")!
        original[range].fromInk.regionAnchor = regionID
        original[range].fromInk.highlight = .red

        let data = try PageBlockSnapshot.encodeBody(original)
        let (recovered, failed) = PageBlockSnapshot.decodeBody(data, blockID: UUID())

        XCTAssertFalse(failed, "Path B round-trip must succeed without falling through to Path A")
        let recoveredRange = recovered.range(of: "Sarah")!
        XCTAssertEqual(recovered[recoveredRange].fromInk.regionAnchor, regionID)
        XCTAssertEqual(recovered[recoveredRange].fromInk.highlight, .red)
    }

    // MARK: - Editor attributes regression (Foundation + SwiftUI sub-scopes)

    /// Regression for the data-loss bug fixed in commit 4 review:
    /// before composing `FoundationAttributes` + `SwiftUIAttributes`
    /// into the `FromInkAttributes` scope, every editor-produced
    /// attribute (`inlinePresentationIntent`, `presentationIntent`,
    /// `underlineStyle`) was silently dropped on save. The user's
    /// bold / italic / heading / underline formatting disappeared on
    /// the next page load. This test pins the composition so the bug
    /// can never come back undetected.
    ///
    /// The realistic shape we exercise: a heading 2 paragraph, with
    /// a bold span inside it, and an underline span overlapping the
    /// bold — all three concurrent on the same character.
    func test_encodeBodyDecodeBody_preservesEditorAttributes_boldHeadingUnderline() throws {
        var original = AttributedString("Q3 budget review")

        // Heading 2 over the whole paragraph.
        let paragraphRange = original.startIndex..<original.endIndex
        original[paragraphRange].presentationIntent = PresentationIntent(
            .header(level: 2),
            identity: 1
        )

        // Bold over "Q3 budget".
        let boldRange = original.range(of: "Q3 budget")!
        original[boldRange].inlinePresentationIntent = .stronglyEmphasized

        // Underline over "budget review" — intentionally overlaps the
        // bold so we prove independent attributes co-exist on the same
        // character (the "budget" word).
        let underlineRange = original.range(of: "budget review")!
        original[underlineRange].underlineStyle = .single

        let data = try PageBlockSnapshot.encodeBody(original)
        let (recovered, failed) = PageBlockSnapshot.decodeBody(data, blockID: UUID())
        XCTAssertFalse(failed, "Path B round-trip must succeed")

        // Heading survives over the recovered paragraph. We compare
        // by the rendered description because `IntentType.Kind` has no
        // direct equality on its associated values and `PresentationIntent`
        // does conform to `CustomStringConvertible` with a stable form.
        let recoveredParagraph = recovered.startIndex..<recovered.endIndex
        let recoveredIntent = recovered[recoveredParagraph].presentationIntent
        XCTAssertNotNil(
            recoveredIntent,
            "Heading 2 must survive encode/decode — without the FoundationAttributes sub-scope this drops to nil"
        )
        let recoveredKindString = recoveredIntent?.components
            .map { String(describing: $0.kind) }
            .joined(separator: ",") ?? ""
        XCTAssertTrue(
            recoveredKindString.contains("header"),
            "Heading kind must round-trip — got components: \(recoveredKindString)"
        )

        // Bold survives over the bold span.
        let recoveredBoldRange = recovered.range(of: "Q3 budget")!
        let recoveredBold = recovered[recoveredBoldRange].inlinePresentationIntent ?? []
        XCTAssertTrue(
            recoveredBold.contains(.stronglyEmphasized),
            "Bold must survive encode/decode — without FoundationAttributes this drops to nil"
        )

        // Underline survives over the underline span.
        let recoveredUnderlineRange = recovered.range(of: "budget review")!
        XCTAssertEqual(
            recovered[recoveredUnderlineRange].underlineStyle,
            .single,
            "Underline must survive encode/decode — without SwiftUIAttributes this drops to nil"
        )

        // Sanity: on the overlap character ("b" of "budget"), both
        // bold AND underline are present. Independent attribute
        // dimensions don't clobber each other.
        let overlapStart = recovered.range(of: "budget")!.lowerBound
        let overlapEnd = recovered.characters.index(after: overlapStart)
        let overlapRange = overlapStart..<overlapEnd
        let overlapBold = recovered[overlapRange].inlinePresentationIntent ?? []
        XCTAssertTrue(overlapBold.contains(.stronglyEmphasized))
        XCTAssertEqual(recovered[overlapRange].underlineStyle, .single)
    }
}
