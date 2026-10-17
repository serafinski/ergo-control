import XCTest
@testable import ErgoCore

final class KeyboardPointerReportTests: XCTestCase {
    func testConfirmedHorizontalPanDirections() throws {
        XCTAssertEqual(try XCTUnwrap(KeyboardPointerReport(Data([2,0,0,1,0,0,0,0,0]))).horizontalPan, 1)
        XCTAssertEqual(try XCTUnwrap(KeyboardPointerReport(Data([2,0,0,255,0,0,0,0,0]))).horizontalPan, -1)
    }
    func testButtonsAlongsideDialRotationDoNotRejectReport() throws {
        let report = try XCTUnwrap(KeyboardPointerReport(Data([2,1,0,1,0,0,0,0,0])))
        XCTAssertEqual(report.buttons, 1)
        XCTAssertEqual(report.horizontalPan, 1)
        XCTAssertTrue(report.hasAuxiliaryInput)
    }
    func testDescriptorWheelMovementAndPaddingFields() throws {
        let report = try XCTUnwrap(KeyboardPointerReport(Data([2,0xff,0xab,0,0xff,0,0x80,0xff,0x7f])))
        XCTAssertEqual(report.buttons, 31)
        XCTAssertEqual(report.horizontalPan, 0, "Auxiliary fields must not trigger a second dial-mode action")
        XCTAssertEqual(report.verticalWheel, -1)
        XCTAssertEqual(report.deltaX, -32768)
        XCTAssertEqual(report.deltaY, 32767)
        XCTAssertTrue(report.hasAuxiliaryInput)
    }
    func testReleaseReportHasNoDialOrAuxiliaryAction() throws {
        let report = try XCTUnwrap(KeyboardPointerReport(Data([2,0,0,0,0,0,0,0,0])))
        XCTAssertEqual(report.horizontalPan, 0)
        XCTAssertFalse(report.hasAuxiliaryInput)
    }
    func testRightRollerWheelIsAControlRatherThanIgnoredAuxiliaryInput() throws {
        let report = try XCTUnwrap(KeyboardPointerReport(Data([2,0,0,0,1,0,0,0,0])))
        XCTAssertEqual(report.verticalWheel, 1)
        XCTAssertEqual(report.horizontalPan, 0)
        XCTAssertFalse(report.hasAuxiliaryInput)
    }
    func testMalformedReportsStillReject() {
        XCTAssertNil(KeyboardPointerReport(Data([2,0,0])))
        XCTAssertNil(KeyboardPointerReport(Data([5,0,0,1,0,0,0,0,0])))
        XCTAssertNil(KeyboardPointerReport(Data(repeating: 2, count: 12)))
    }
}
