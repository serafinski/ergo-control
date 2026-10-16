import XCTest
import ErgoCore
@testable import ErgoDevice

final class PairedKeyboardDiscoveryTests: XCTestCase {
    private func properties(_ id: UUID = UUID()) -> [String: Any] {
        ["VendorID": ErgoTarget.vendorID, "ProductID": ErgoTarget.productID,
         "Transport": ErgoTarget.transport, "PhysicalDeviceUniqueID": id.uuidString]
    }
    func testMultipleInterfacesOfSameKeyboardResolveToOneEndpoint() {
        let id = UUID()
        let value = PairedKeyboardSnapshot(properties: [properties(id), properties(id)])
        XCTAssertEqual(value.matchingServices, 2)
        XCTAssertEqual(value.uniqueID, id)
        XCTAssertFalse(value.missingIdentity)
    }
    func testUSBAndOtherDevicesCannotBeSelected() {
        var usb = properties(); usb["Transport"] = "USB"
        var other = properties(); other["ProductID"] = 0
        let value = PairedKeyboardSnapshot(properties: [usb, other])
        XCTAssertEqual(value.matchingServices, 0)
        XCTAssertNil(value.uniqueID)
    }
    func testMissingMalformedOrAmbiguousIdentityCannotBeSelected() {
        var missing = properties(); missing.removeValue(forKey: "PhysicalDeviceUniqueID")
        var invalid = properties(); invalid["PhysicalDeviceUniqueID"] = "not-a-uuid"
        XCTAssertNil(PairedKeyboardSnapshot(properties: [missing]).uniqueID)
        XCTAssertNil(PairedKeyboardSnapshot(properties: [invalid]).uniqueID)
        XCTAssertNil(PairedKeyboardSnapshot(properties: [properties(), properties()]).uniqueID)
        XCTAssertNil(PairedKeyboardSnapshot(properties: [properties(), missing]).uniqueID)
    }
    func testRecoveryConnectsKnownPairedEndpointBeforeHIDArrives() {
        let saved = UUID()
        let beforeArrival = PairedKeyboardSnapshot(properties: [])
        XCTAssertNil(beforeArrival.connectionTarget(recoveryID: nil))
        XCTAssertEqual(beforeArrival.connectionTarget(recoveryID: saved), saved)
        let afterArrival = PairedKeyboardSnapshot(properties: [properties(saved)])
        XCTAssertEqual(afterArrival.connectionTarget(recoveryID: saved), saved)
    }
    func testRecoveryRejectsDifferentAmbiguousOrUnreadableIdentity() {
        let saved = UUID()
        XCTAssertNil(PairedKeyboardSnapshot(properties: [properties()]).connectionTarget(recoveryID: saved))
        XCTAssertNil(PairedKeyboardSnapshot(properties: [properties(saved), properties()]).connectionTarget(recoveryID: saved))
        var missing = properties(); missing.removeValue(forKey: "PhysicalDeviceUniqueID")
        XCTAssertNil(PairedKeyboardSnapshot(properties: [missing]).connectionTarget(recoveryID: saved))
        XCTAssertNil(PairedKeyboardSnapshot(properties: [], lookupResult: -1).connectionTarget(recoveryID: saved))
    }
}
