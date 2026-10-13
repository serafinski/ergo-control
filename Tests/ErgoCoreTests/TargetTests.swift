import XCTest
@testable import ErgoCore

final class TargetTests: XCTestCase {
    func testOnlyExactBluetoothIdentityIsEligible() {
        XCTAssertTrue(ErgoTarget.matches(vendor: 1678, product: 707, transport: "Bluetooth Low Energy"))
        XCTAssertFalse(ErgoTarget.matches(vendor: 0x046d, product: 707, transport: "Bluetooth Low Energy"))
        XCTAssertFalse(ErgoTarget.matches(vendor: 1678, product: 708, transport: "USB"))
        XCTAssertFalse(ErgoTarget.matches(vendor: 1678, product: 707, transport: "USB"))
        XCTAssertFalse(ErgoTarget.matches(vendor: 0x1532, product: 707, transport: "Bluetooth Low Energy"))
    }
}
