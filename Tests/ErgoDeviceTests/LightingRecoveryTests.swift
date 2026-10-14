import XCTest
import ErgoCore
@testable import ErgoDevice

final class LightingRecoveryTests: XCTestCase {
    func testNegativeAcknowledgementDoesNotDisconnectWorkingMappings() {
        XCTAssertFalse(BluetoothFailure.rejected(7).requiresReconnect)
        XCTAssertTrue(BluetoothFailure.message("Timed out with a partial response").requiresReconnect)
    }

    func testUnsupportedRGBFallbackRequiresAnInitiallyOffLight() {
        let off = SavedDialLight.fallbackForUnsupportedRGB(state: 0, status: 7)
        XCTAssertNotNil(off); XCTAssertNil(off?.color); XCTAssertEqual(off?.on, false)
        XCTAssertNil(SavedDialLight.fallbackForUnsupportedRGB(state: 1, status: 7))
        XCTAssertNil(SavedDialLight.fallbackForUnsupportedRGB(state: 2, status: 7))
        XCTAssertNil(SavedDialLight.fallbackForUnsupportedRGB(state: 0, status: 5))
    }

    func testOldRecoveryJournalAndOffOnlySnapshotRoundTrip() throws {
        let data = Data(#"{"peripheral":"00000000-0000-0000-0000-000000000001","mode":0,"parameter":0}"#.utf8)
        var saved = try JSONDecoder().decode(SavedMode.self, from: data)
        XCTAssertNil(saved.dialLight)
        saved.dialLight = SavedDialLight(color: nil, on: false)
        let recovered = try JSONDecoder().decode(SavedMode.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(recovered.mode, 0); XCTAssertEqual(recovered.parameter, 0)
        XCTAssertNotNil(recovered.dialLight); XCTAssertNil(recovered.dialLight?.color)
        XCTAssertEqual(recovered.dialLight?.on, false)
    }
}
