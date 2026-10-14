import XCTest
@testable import ErgoCore

final class USBKnobReadTests: XCTestCase {
    func testUSBIndicatorGettersUseSeparateReadTemplates() throws {
        let state = try USBKnobRead.indicatorState.request(transaction: 3)
        XCTAssertEqual(Array(state.prefix(10)), [0,3,0,0,0,3,3,0x80,1,39])
        XCTAssertEqual(state[88], 0xa6)
        let rgb = try USBKnobRead.indicatorRGB.request(transaction: 4)
        XCTAssertEqual(Array(rgb.prefix(10)), [0,4,0,0,0,5,3,0x81,1,39])
        XCTAssertEqual(rgb[88], 0xa1)
        XCTAssertTrue(USBKnobRead.allCases.allSatisfy { $0.commandID >= 0x80 })
    }
    func testUSBGettersUseRecoveredTemplatesAndChecksum() throws {
        let mode = try USBKnobRead.currentMode.request(transaction: 1)
        XCTAssertEqual(mode.count, 90)
        XCTAssertEqual(Array(mode.prefix(10)), [0,1,0,0,0,8,3,0x93,1,39])
        XCTAssertEqual(mode[88], 0xbe)
        XCTAssertEqual(mode[89], 0)
        let config = try USBKnobRead.configuration.request(transaction: 2)
        XCTAssertEqual(Array(config.prefix(10)), [0,2,0,0,0,50,3,0x92,1,39])
        XCTAssertEqual(config[88], 0x85)
        XCTAssertThrowsError(try USBKnobRead.currentMode.request(transaction: 0))
        XCTAssertThrowsError(try USBKnobRead.currentMode.request(transaction: 32))
    }

    func testReplyRejectsWrongTransactionOpcodeChecksumAndAddress() throws {
        var reply = try USBKnobRead.currentMode.request(transaction: 1)
        reply[0] = 2; reply[13] = 255 // Current mode RGB red.
        reply[88] = reply[2..<88].reduce(0, ^)
        XCTAssertEqual(try USBKnobRead.currentMode.response(reply, transaction: 1).payload,
                       Data([1,39,0,0,0,255,0,0]))
        XCTAssertThrowsError(try USBKnobRead.currentMode.response(reply, transaction: 2))
        XCTAssertThrowsError(try USBKnobRead.configuration.response(reply, transaction: 1))
        var corrupted = reply; corrupted[20] ^= 1
        XCTAssertThrowsError(try USBKnobRead.currentMode.response(corrupted, transaction: 1))
        corrupted = reply; corrupted[9] = 5; corrupted[88] = corrupted[2..<88].reduce(0, ^)
        XCTAssertThrowsError(try USBKnobRead.currentMode.response(corrupted, transaction: 1))
        XCTAssertThrowsError(try USBKnobRead.currentMode.response(Data(reply.dropLast()), transaction: 1))
    }

    func testBusyAndUnsupportedRepliesExposeNoPayload() throws {
        var reply = try USBKnobRead.currentMode.request(transaction: 1)
        for status: UInt8 in [1,3,5] {
            reply[0] = status
            let result = try USBKnobRead.currentMode.response(reply, transaction: 1)
            XCTAssertEqual(result.status, status)
            XCTAssertTrue(result.payload.isEmpty)
        }
    }
}
