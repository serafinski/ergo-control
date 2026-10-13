import XCTest
@testable import ErgoCore

final class InputAccessModeTests: XCTestCase {
    func testMacroButtonsNeverRelayOrdinaryOrDialReports() {
        XCTAssertTrue(InputAccessMode.macroButtons.accepts(reportID: 5))
        for id: UInt32 in [1, 2, 3, 4, 6] { XCTAssertFalse(InputAccessMode.macroButtons.accepts(reportID: id)) }
        for control in ["extra:32", "extra:247", "extra:96", "extra:65"] {
            XCTAssertTrue(InputAccessMode.macroButtons.supports(control: control))
        }
        for control in ["key:4", "leftCW", "rightClick", "mediaSingle"] {
            XCTAssertFalse(InputAccessMode.macroButtons.supports(control: control))
        }
    }
    func testFullKeyboardRetainsReportAndMappingSupport() {
        for id: UInt32 in 1...6 { XCTAssertTrue(InputAccessMode.fullKeyboard.accepts(reportID: id)) }
        XCTAssertTrue(InputAccessMode.fullKeyboard.supports(control: "key:4"))
    }
}
