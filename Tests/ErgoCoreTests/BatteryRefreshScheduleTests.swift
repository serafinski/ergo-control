import XCTest
@testable import ErgoCore

final class BatteryRefreshScheduleTests: XCTestCase {
    private func poll(_ schedule: inout BatteryRefreshSchedule, at time: TimeInterval, ready: Bool = true,
                      busy: Bool = false, preparing: Bool = false, owed: Bool = false,
                      driver: Bool = false) -> BatteryRefreshSchedule.Action? {
        schedule.next(at: time, ready: ready, busy: busy, preparingMappings: preparing,
                      restorationOwed: owed, driverModeVerified: driver)
    }

    func testInitialConnectionAndFiveMinuteReadsAreThrottled() {
        var schedule = BatteryRefreshSchedule()
        XCTAssertEqual(poll(&schedule, at: 0, ready: false), .connect)
        XCTAssertNil(poll(&schedule, at: 5, ready: false))
        XCTAssertEqual(poll(&schedule, at: 60, ready: false), .connect)
        XCTAssertEqual(poll(&schedule, at: 61), .read)
        XCTAssertNil(poll(&schedule, at: 65))
        XCTAssertNil(poll(&schedule, at: 360))
        XCTAssertEqual(poll(&schedule, at: 361), .read)
    }

    func testMappingTransitionsAndBusyChannelKeepBatteryReadPending() {
        var schedule = BatteryRefreshSchedule()
        XCTAssertNil(poll(&schedule, at: 0, busy: true))
        XCTAssertNil(poll(&schedule, at: 5, preparing: true))
        XCTAssertNil(poll(&schedule, at: 10, owed: true))
        // Active, verified driver mode permits read-only polling on an idle channel.
        XCTAssertEqual(poll(&schedule, at: 15, owed: true, driver: true), .read)
        XCTAssertNil(poll(&schedule, at: 315, busy: true, owed: true, driver: true))
        XCTAssertEqual(poll(&schedule, at: 320, owed: true, driver: true), .read)
    }

    func testDisconnectedRecoveryConnectsButDoesNotReadBatteryUntilRestored() {
        var schedule = BatteryRefreshSchedule()
        XCTAssertEqual(poll(&schedule, at: 0, ready: false, owed: true), .connect)
        XCTAssertNil(poll(&schedule, at: 5, ready: false, owed: true))
        XCTAssertNil(poll(&schedule, at: 10, owed: true), "The controller must finish recovery before reading battery")
        XCTAssertNil(poll(&schedule, at: 60, ready: false, owed: true, driver: true))
        XCTAssertEqual(poll(&schedule, at: 61, ready: false, owed: true), .connect)
        XCTAssertNil(poll(&schedule, at: 62, owed: true))
        XCTAssertEqual(poll(&schedule, at: 63), .read)
        XCTAssertEqual(poll(&schedule, at: 121, ready: false), .connect)
        XCTAssertEqual(poll(&schedule, at: 122), .read) // Fresh value after reconnection.
    }

    func testManualRefreshWaitsUntilSafeRatherThanLosingRequest() {
        var schedule = BatteryRefreshSchedule()
        XCTAssertEqual(poll(&schedule, at: 0), .read)
        XCTAssertNil(poll(&schedule, at: 1))
        schedule.refresh()
        XCTAssertNil(poll(&schedule, at: 2, busy: true))
        XCTAssertNil(poll(&schedule, at: 3, owed: true))
        XCTAssertEqual(poll(&schedule, at: 4), .read)
        XCTAssertNil(poll(&schedule, at: 5))
    }
}
