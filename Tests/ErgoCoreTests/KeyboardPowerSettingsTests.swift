import XCTest
import ErgoCore

final class KeyboardPowerSettingsTests: XCTestCase {
    func testNativePowerPacketsUseRecoveredBatteryAndProfileFields() throws {
        let dim = try Protocol30Request.keyboardDimming(transaction: 2, value: KeyboardDimming(enabled: true, seconds: 300))
        XCTAssertEqual(dim.header, Data([2,4,0,0,5,10,0,1]))
        XCTAssertEqual(dim.payload, Data([1,44,1,20]))
        let sleep = try Protocol30Request.keyboardSleepTimer(transaction: 2, seconds: 900)
        XCTAssertEqual(sleep.header, Data([2,2,0,0,5,4,0,0]))
        XCTAssertEqual(sleep.payload, Data([132,3]))
        let enabled = try Protocol30Request.keyboardAutoSleep(transaction: 2, enabled: false)
        XCTAssertEqual(enabled.header, Data([2,1,0,0,5,7,0,1]))
        XCTAssertEqual(enabled.payload, Data([0]))
    }
    func testNativePowerBoundsAndMalformedDimmingRepliesAreRejected() {
        for seconds: UInt16 in [0,59,901,65535] {
            XCTAssertThrowsError(try Protocol30Request.keyboardDimming(transaction: 1, value: KeyboardDimming(enabled: true, seconds: seconds)))
        }
        for seconds: UInt16 in [0,59,3601,65535] { XCTAssertThrowsError(try Protocol30Request.keyboardSleepTimer(transaction: 1, seconds: seconds)) }
        for bytes: [UInt8] in [[],[1,44,1],[2,44,1,20],[1,44,1,101]] { XCTAssertThrowsError(try KeyboardDimming(payload: Data(bytes))) }
    }
    func testOffPolicyDefaultsKeepStatusLightsOnAndDisplayAndIdleAreIndependent() {
        var policy = LightingOffPreferences()
        XCTAssertFalse(policy.shouldTurnOff(displayAsleep: true, idleSeconds: 10000))
        policy.whenDisplaySleeps = true
        XCTAssertTrue(policy.shouldTurnOff(displayAsleep: true, idleSeconds: 0))
        XCTAssertFalse(policy.shouldTurnOff(displayAsleep: false, idleSeconds: 10000))
        policy.whenDisplaySleeps = false; policy.whenIdle = true; policy.idleMinutes = 3
        XCTAssertFalse(policy.shouldTurnOff(displayAsleep: false, idleSeconds: 179.9))
        XCTAssertTrue(policy.shouldTurnOff(displayAsleep: false, idleSeconds: 180))
        XCTAssertFalse(policy.shouldTurnOff(displayAsleep: false, idleSeconds: 0))
        XCTAssertFalse(policy.shouldTurnOff(displayAsleep: false, idleSeconds: .nan))
    }
    func testOffPolicyAndExactBrightnessJournalRoundTrip() throws {
        var policy = LightingOffPreferences(); policy.whenIdle = true; policy.idleMinutes = 5
        XCTAssertEqual(try JSONDecoder().decode(LightingOffPreferences.self, from: JSONEncoder().encode(policy)), policy)
        let saved = SavedKeyboardBrightness(peripheral: UUID(), brightness: 13)
        XCTAssertEqual(try JSONDecoder().decode(SavedKeyboardBrightness.self, from: JSONEncoder().encode(saved)), saved)
    }
}
