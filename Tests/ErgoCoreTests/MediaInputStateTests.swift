import XCTest
@testable import ErgoCore

final class MediaInputStateTests: XCTestCase {
    private func driver(_ usage: UInt16) -> Data { Data([6,2,UInt8(usage & 255),UInt8(usage >> 8)] + Array(repeating: 0, count: 8)) }
    private func native(_ usage: UInt16) -> Data { Data([3,UInt8(usage & 255),UInt8(usage >> 8)] + Array(repeating: 0, count: 9)) }
    private func pulse(_ usage: UInt16) -> [ConsumerKeyEvent] { [.init(usage, pressed: true), .init(usage, pressed: false)] }
    func testDriverVolumeMuteAndPlaybackAreBalancedIndependentCommands() {
        for usage: UInt16 in [0xe9,0xea,0xe2,0xcd,0xb5,0xb6] {
            var state = MediaInputState()
            XCTAssertEqual(state.decode(driver(usage), at: 0), pulse(usage))
            XCTAssertEqual(state.decode(driver(usage), at: 0.03), pulse(usage), "Each same-source detent must work")
            XCTAssertEqual(state.decode(driver(0), at: 0.05), [])
            XCTAssertNil(state.releaseDeadline)
        }
    }
    func testNotificationsAndMalformedVendorRecordsCannotTriggerMediaOrChangeHeldNativeState() {
        var state = MediaInputState()
        XCTAssertEqual(state.decode(native(0xe9), at: 0), [.init(0xe9, pressed: true)])
        for report in [Data([6,5,8,100] + Array(repeating: 0, count: 8)), Data([6,2,0xcd]), Data([5,2,0xcd,0] + Array(repeating: 0, count: 8))] {
            XCTAssertNil(state.decode(report, at: 0.1)); XCTAssertNil(DriverMediaRecord(report))
        }
        var reserved = driver(0xcd); reserved[11] = 1
        XCTAssertNil(state.decode(reserved, at: 0.1))
        XCTAssertEqual(state.decode(native(0), at: 1), [.init(0xe9, pressed: false)])
    }
    func testDriverThenNativeCopyTogglesOnlyOnceAndConsumesLateNativeRelease() {
        for usage: UInt16 in [0xcd,0xe2,0xe9,0xb5,0xb6] {
            var state = MediaInputState()
            XCTAssertEqual(state.decode(driver(usage), at: 0), pulse(usage))
            XCTAssertEqual(state.decode(native(usage), at: 0.02), [])
            XCTAssertEqual(state.decode(native(0), at: 0.05), [])
            XCTAssertEqual(state.decode(driver(usage), at: 0.2), pulse(usage))
        }
    }
    func testNativeThenDriverCopyPreservesNativeReleaseAndNextGesture() {
        var state = MediaInputState()
        XCTAssertEqual(state.decode(native(0xcd), at: 0), [.init(0xcd, pressed: true)])
        XCTAssertEqual(state.decode(driver(0xcd), at: 0.02), [])
        XCTAssertEqual(state.decode(native(0), at: 0.05), [.init(0xcd, pressed: false)])
        XCTAssertEqual(state.decode(native(0xcd), at: 0.2), [.init(0xcd, pressed: true)])
        XCTAssertEqual(state.releaseExpired(at: 0.51), [.init(0xcd, pressed: false)])
    }
    func testDifferentUsagesAndSeparatedInputsAreNeverDeduplicated() {
        var state = MediaInputState()
        _ = state.decode(native(0xe9), at: 0)
        XCTAssertEqual(state.decode(driver(0xea), at: 0.01), pulse(0xea))
        XCTAssertEqual(state.decode(driver(0xe9), at: 0.2), pulse(0xe9))
    }
    func testSuppressedNativePulseTimeoutCannotReleaseAnotherPlayerOrRearmTwice() {
        var state = MediaInputState()
        _ = state.decode(driver(0xcd), at: 0)
        XCTAssertEqual(state.decode(native(0xcd), at: 0.01), [])
        XCTAssertEqual(state.releaseExpired(at: 0.32), [])
        XCTAssertEqual(state.decode(native(0), at: 0.4), [])
        XCTAssertEqual(state.decode(driver(0xcd), at: 1), pulse(0xcd))
    }
    func testProbeDescribesVendorMediaWithoutTreatingBrightnessNotificationAsPlayback() {
        var decoder = InputReportDecoder()
        XCTAssertEqual(decoder.describe(reportID: 6, hexadecimal: "0602e9000000000000000000"), ["Volume up · driver media event"])
        XCTAssertEqual(decoder.describe(reportID: 6, hexadecimal: "060000000000000000000000"), nil)
        XCTAssertEqual(decoder.describe(reportID: 6, hexadecimal: "060508ff0000000000000000"), ["Keyboard brightness · 100%"])
    }
}
