import XCTest
@testable import ErgoCore

final class ConsumerKeyStateTests: XCTestCase {
    private func report(_ usage: UInt16) -> Data {
        Data([3, UInt8(usage & 255), UInt8(usage >> 8)] + Array(repeating: 0, count: 9))
    }
    func testNormalMediaPulsesReleaseOnceAndDuplicatePacketsDoNotRepeat() {
        var state = ConsumerKeyState()
        XCTAssertEqual(state.decode(report(0xcd), at: 1), [ConsumerKeyEvent(0xcd, pressed: true)])
        XCTAssertEqual(state.decode(report(0xcd), at: 1.01), [])
        XCTAssertEqual(state.decode(report(0), at: 1.03), [ConsumerKeyEvent(0xcd, pressed: false)])
        XCTAssertNil(state.releaseDeadline)
        XCTAssertEqual(state.releaseExpired(at: 2), [])
        XCTAssertEqual(state.decode(report(0xcd), at: 3), [ConsumerKeyEvent(0xcd, pressed: true)])
    }
    func testMissingReleaseDoesNotRequireVolumeOrMuteToRearmMediaGestures() {
        for usage: UInt16 in [0xcd, 0xb5, 0xb6] {
            var state = ConsumerKeyState()
            XCTAssertEqual(state.decode(report(usage), at: 0), [ConsumerKeyEvent(usage, pressed: true)])
            XCTAssertEqual(state.releaseExpired(at: 0.29), [])
            XCTAssertEqual(state.releaseExpired(at: 0.31), [ConsumerKeyEvent(usage, pressed: false)])
            XCTAssertEqual(state.releaseExpired(at: 0.6), [])
            XCTAssertEqual(state.decode(report(usage), at: 1), [ConsumerKeyEvent(usage, pressed: true)])
            // Recover even if the run-loop timer was delayed until the next click.
            XCTAssertEqual(state.decode(report(usage), at: 2), [
                ConsumerKeyEvent(usage, pressed: false), ConsumerKeyEvent(usage, pressed: true)])
        }
    }
    func testChangingControlOrLateNeutralDoesNotDoubleRelease() {
        var state = ConsumerKeyState()
        _ = state.decode(report(0xcd), at: 0)
        XCTAssertEqual(state.decode(report(0xe9), at: 0.1), [
            ConsumerKeyEvent(0xcd, pressed: false), ConsumerKeyEvent(0xe9, pressed: true)])
        XCTAssertEqual(state.releaseExpired(at: 2), [])
        XCTAssertEqual(state.decode(report(0), at: 3), [ConsumerKeyEvent(0xe9, pressed: false)])
        _ = state.decode(report(0xcd), at: 4)
        XCTAssertEqual(state.decode(report(0), at: 5), [ConsumerKeyEvent(0xcd, pressed: false)])
        XCTAssertEqual(state.decode(report(0), at: 6), [])
    }
    func testHeldControlsKeepTheirReleaseAndMalformedPacketsDoNotMutateState() {
        for usage: UInt16 in [0xe9, 0xea, 0xe2, 0xb3, 0xb4, 0x6f, 0x70] {
            var state = ConsumerKeyState()
            _ = state.decode(report(usage), at: 0)
            XCTAssertNil(state.releaseDeadline)
            XCTAssertEqual(state.releaseExpired(at: 10), [])
            XCTAssertNil(state.decode(Data([3,0]), at: 11))
            var wrongID = report(0); wrongID[0] = 5
            XCTAssertNil(state.decode(wrongID, at: 11))
            var reserved = report(0); reserved[3] = 1
            XCTAssertNil(state.decode(reserved, at: 11))
            XCTAssertEqual(state.decode(report(0), at: 12), [ConsumerKeyEvent(usage, pressed: false)])
        }
    }
}
