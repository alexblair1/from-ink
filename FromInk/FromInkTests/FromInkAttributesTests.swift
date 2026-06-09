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
}
