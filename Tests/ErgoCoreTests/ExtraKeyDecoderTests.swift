import XCTest
@testable import ErgoCore

final class ExtraKeyDecoderTests: XCTestCase {
    private func report(_ keys: [UInt8] = []) -> Data {
        Data([5, 4] + keys + Array(repeating: 0, count: 10 - keys.count))
    }

    func testCapturedMacroAndAIReports() {
        for (key, name) in [(UInt8(32), "M1"), (33, "M2"), (34, "M3"), (35, "M4"), (36, "M5"),
                            (247, "AI button"), (96, "Left dial click"), (65, "Battery button")] {
            var decoder = ExtraKeyDecoder()
            let press = decoder.decode(reportID: 5, bytes: report([key]))!
            XCTAssertEqual(press, [ExtraKeyEvent(key: key, pressed: true)])
            XCTAssertEqual(press.first?.name, name)
            XCTAssertEqual(decoder.decode(reportID: 5, bytes: report()), [ExtraKeyEvent(key: key, pressed: false)])
        }
    }

    func testDuplicateSnapshotsAndMultipleHeldKeys() {
        var decoder = ExtraKeyDecoder()
        XCTAssertEqual(decoder.decode(reportID: 5, bytes: report([32, 33]))?.count, 2)
        XCTAssertEqual(decoder.decode(reportID: 5, bytes: report([33, 32, 32])), [])
        XCTAssertEqual(decoder.decode(reportID: 5, bytes: report([33, 247])),
                       [ExtraKeyEvent(key: 32, pressed: false), ExtraKeyEvent(key: 247, pressed: true)])
    }

    func testInvalidOrUnrelatedReportsDoNotReleaseHeldKeys() {
        var decoder = ExtraKeyDecoder()
        _ = decoder.decode(reportID: 5, bytes: report([32]))
        XCTAssertNil(decoder.decode(reportID: 1, bytes: report()))
        XCTAssertNil(decoder.decode(reportID: 5, bytes: Data([5, 4])))
        XCTAssertNil(decoder.decode(reportID: 5, bytes: Data([5, 5] + Array(repeating: 0, count: 10))))
        XCTAssertEqual(decoder.decode(reportID: 5, bytes: report()), [ExtraKeyEvent(key: 32, pressed: false)])
    }
}
