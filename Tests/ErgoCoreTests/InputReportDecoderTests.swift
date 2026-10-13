import XCTest
@testable import ErgoCore

final class InputReportDecoderTests: XCTestCase {
    func testCapturedDriverModeLeftDialDirections() {
        var decoder = InputReportDecoder()
        XCTAssertEqual(decoder.describe(reportID: 2, hexadecimal: "020000010000000000"), ["Left dial · clockwise"])
        XCTAssertEqual(decoder.describe(reportID: 2, hexadecimal: "020000ff0000000000"), ["Left dial · counterclockwise"])
        XCTAssertNil(decoder.describe(reportID: 2, hexadecimal: "020100010000000000"))
        XCTAssertNil(decoder.describe(reportID: 2, hexadecimal: "020000000100000000"))
        XCTAssertNil(decoder.describe(reportID: 2, hexadecimal: "020000010001000000"))
    }

    func testCapturedConsumerPressAndReleasePairs() {
        for (hex, name) in [("e9", "Volume up"), ("ea", "Volume down"), ("e2", "Mute"),
                            ("cd", "Play / pause"), ("b5", "Next track"), ("b6", "Previous track")] {
            var decoder = InputReportDecoder()
            let report = "03\(hex)00000000000000000000"
            XCTAssertEqual(decoder.describe(reportID: 3, hexadecimal: report), ["\(name) · pressed"])
            XCTAssertEqual(decoder.describe(reportID: 3, hexadecimal: report), [])
            XCTAssertEqual(decoder.describe(reportID: 3, hexadecimal: "030000000000000000000000"), ["\(name) · released"])
        }
    }

    func testCapturedBrightnessNotificationAndUnknownPackets() {
        var decoder = InputReportDecoder()
        XCTAssertEqual(decoder.describe(reportID: 6, hexadecimal: "0605080c0000000000000000"), ["Keyboard brightness · 5%"])
        XCTAssertEqual(decoder.describe(reportID: 6, hexadecimal: "060508260000000000000000"), ["Keyboard brightness · 15%"])
        XCTAssertNil(decoder.describe(reportID: 6, hexadecimal: "060509260000000000000000"))
        XCTAssertNil(decoder.describe(reportID: 3, hexadecimal: "060508260000000000000000"))
        XCTAssertNil(decoder.describe(reportID: 6, hexadecimal: "0605"))
        XCTAssertNil(decoder.describe(reportID: 6, hexadecimal: "060508xx0000000000000000"))
    }
}
