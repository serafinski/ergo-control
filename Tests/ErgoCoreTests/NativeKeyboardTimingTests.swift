import XCTest
@testable import ErgoCore

final class NativeKeyboardTimingTests: XCTestCase {
    func testSystemTimingsRemainInSecondsWithoutSpeedClamping() {
        let normal = NativeKeyboardTiming(delay: 0.5, interval: 1.0 / 12)
        XCTAssertEqual(normal.delay, 0.5)
        XCTAssertEqual(normal.interval, 1.0 / 12)
        let customized = NativeKeyboardTiming(delay: 3, interval: 0.005)
        XCTAssertEqual(customized.delay, 3); XCTAssertEqual(customized.interval, 0.005)
    }
    func testMissingInvalidTimingCannotBecomeFastestRepeat() {
        for value in [0, -1, Double.nan, Double.infinity] {
            let timing = NativeKeyboardTiming(delay: value, interval: value)
            XCTAssertEqual(timing.delay, 0.5); XCTAssertEqual(timing.interval, 1.0 / 12)
        }
    }
    func testControlOptionPrecedeEveryArrowInASingleReport() {
        for arrow: UInt8 in 79...82 {
            let steps = NativeKeyboardTransitions.changes(from: [], to: [224, 226, arrow])
            XCTAssertEqual(steps.map(\.usage), [224,226,arrow])
            XCTAssertEqual(steps.map(\.modifiers), [1,5,5])
            XCTAssertTrue(steps.allSatisfy(\.pressed))
            XCTAssertTrue(NativeKeyboardTransitions.changes(from: [224,226,arrow], to: [224,226,arrow]).isEmpty)
        }
    }
    func testKeysReleaseBeforeModifiersAndStaggeredPressesKeepHeldState() {
        let up = NativeKeyboardTransitions.changes(from: [224,226,80], to: [])
        XCTAssertEqual(up.map(\.usage), [80,224,226])
        XCTAssertEqual(up.map(\.modifiers), [5,4,0])
        XCTAssertTrue(up.allSatisfy { !$0.pressed })
        let add = NativeKeyboardTransitions.changes(from: [228], to: [228,230,82])
        XCTAssertEqual(add.map(\.usage), [230,82])
        XCTAssertEqual(add.map(\.modifiers), [0x50,0x50])
        let replace = NativeKeyboardTransitions.changes(from: [224,80], to: [226,79])
        XCTAssertEqual(replace.map(\.usage), [80,224,226,79])
        XCTAssertEqual(replace.map(\.modifiers), [1,0,4,4])
    }
}
