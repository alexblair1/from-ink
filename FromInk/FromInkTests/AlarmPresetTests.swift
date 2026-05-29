import XCTest
@testable import FromInk

/// Round-trip tests for `AlarmPreset` — specifically the `.custom(Int)`
/// case added to preserve non-preset alarm offsets loaded from an
/// existing EKEvent. The reducer itself never sees `AlarmPreset` (it
/// stores `Int?`), so these tests poke the helper directly to verify
/// the wiring contract: state's `Int?` survives a round-trip through
/// the picker layer without quietly being clamped to `.none`.
final class AlarmPresetTests: XCTestCase {

    // MARK: - from(minutesBefore:)

    func test_from_minutesBefore_nilProducesNone() {
        XCTAssertEqual(AlarmPreset.from(minutesBefore: nil), .none)
    }

    func test_from_minutesBefore_presetsResolveToOwnCase() {
        XCTAssertEqual(AlarmPreset.from(minutesBefore: 0), .atTime)
        XCTAssertEqual(AlarmPreset.from(minutesBefore: 5), .fiveMin)
        XCTAssertEqual(AlarmPreset.from(minutesBefore: 15), .fifteenMin)
        XCTAssertEqual(AlarmPreset.from(minutesBefore: 30), .thirtyMin)
        XCTAssertEqual(AlarmPreset.from(minutesBefore: 60), .oneHour)
        XCTAssertEqual(AlarmPreset.from(minutesBefore: 1440), .oneDay)
    }

    func test_from_minutesBefore_nonPresetIsPreservedAsCustom() {
        // The bug Stage 4b's review documented: a 7-minute alarm
        // loaded from an existing EKEvent used to collapse to .none,
        // setting up a destroy-on-tap. With .custom(Int), the value
        // round-trips intact.
        XCTAssertEqual(AlarmPreset.from(minutesBefore: 7), .custom(7))
        XCTAssertEqual(AlarmPreset.from(minutesBefore: 90), .custom(90))
        XCTAssertEqual(AlarmPreset.from(minutesBefore: 10_080), .custom(10_080))  // 1 week
    }

    // MARK: - from(id:)

    func test_from_id_presetsRoundTrip() {
        XCTAssertEqual(AlarmPreset.from(id: "none"), .none)
        XCTAssertEqual(AlarmPreset.from(id: "0"), .atTime)
        XCTAssertEqual(AlarmPreset.from(id: "15"), .fifteenMin)
        XCTAssertEqual(AlarmPreset.from(id: "1440"), .oneDay)
    }

    func test_from_id_customMinutesRoundTrip() {
        // The picker appends a "custom" row with id = stringified minutes
        // when state holds a non-preset value. Tapping that row emits
        // its id back through `onAlarmSelected`; from(id:) must decode
        // it as `.custom(m)` so state stays put.
        XCTAssertEqual(AlarmPreset.from(id: "7"), .custom(7))
        XCTAssertEqual(AlarmPreset.from(id: "90"), .custom(90))
    }

    func test_from_id_unparseable_fallsBackToNone() {
        // Impossible in production — the picker only emits IDs from
        // our own choices list — but documents the harmless fallback.
        XCTAssertEqual(AlarmPreset.from(id: "garbage"), .none)
        XCTAssertEqual(AlarmPreset.from(id: ""), .none)
    }

    // MARK: - id <-> minutesBefore symmetry

    func test_idAndMinutesBefore_areConsistent() {
        // For every preset, id is "none" or the stringified minutes;
        // for a custom value, id stringifies the underlying Int. The
        // picker's uniqueness invariant relies on this: every active
        // value has a distinct id.
        for preset in AlarmPreset.allPresets {
            let expectedID = preset.minutesBefore.map(String.init) ?? "none"
            XCTAssertEqual(preset.id, expectedID, "id mismatch for \(preset)")
        }
        XCTAssertEqual(AlarmPreset.custom(7).id, "7")
        XCTAssertEqual(AlarmPreset.custom(90).id, "90")
    }
}
