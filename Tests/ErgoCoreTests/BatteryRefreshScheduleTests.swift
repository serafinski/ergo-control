import XCTest
@testable import ErgoCore

final class BatteryRefreshScheduleTests: XCTestCase {
    private func poll(_ schedule: inout BatteryRefreshSchedule, at time: TimeInterval, ready: Bool = true,
                      busy: Bool = false, preparing: Bool = false, owed: Bool = false,
                      driver: Bool = false, automatic: Bool = false) -> BatteryRefreshSchedule.Action? {
        schedule.next(at: time, ready: ready, busy: busy, preparingMappings: preparing,
                      restorationOwed: owed, driverModeVerified: driver, automaticStartPending: automatic)
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

    func testPendingAutomaticStartConnectsMoreOftenWithoutInterruptingTransitions() {
        var schedule = BatteryRefreshSchedule()
        XCTAssertEqual(poll(&schedule, at: 0, ready: false, automatic: true), .connect)
        XCTAssertNil(poll(&schedule, at: 25, ready: false, automatic: true))
        XCTAssertNil(poll(&schedule, at: 30, ready: false, busy: true, automatic: true))
        XCTAssertNil(poll(&schedule, at: 31, ready: false, preparing: true, automatic: true))
        XCTAssertNil(poll(&schedule, at: 32, ready: false, driver: true, automatic: true))
        XCTAssertEqual(poll(&schedule, at: 33, ready: false, automatic: true), .connect)
        XCTAssertNil(poll(&schedule, at: 63, ready: false), "Cancellation returns to ordinary sixty-second polling")
        XCTAssertEqual(poll(&schedule, at: 93, ready: false), .connect)
    }

    func testLateKeyboardRecoveryStillAllowsPendingAutomaticActivation() {
        var schedule = BatteryRefreshSchedule()
        var startup = AutomaticMappingStart()
        startup.arm()
        // The old two-minute deadline expired before this keyboard arrived.
        for time in stride(from: 0.0, through: 150.0, by: 30.0) {
            XCTAssertEqual(poll(&schedule, at: time, ready: false, owed: true, automatic: true), .connect)
            XCTAssertEqual(startup.next(ready: false, permissions: true, busy: false, restorationPending: true), .wait)
        }
        XCTAssertNil(poll(&schedule, at: 151, owed: true, automatic: true))
        XCTAssertEqual(startup.next(ready: true, permissions: true, busy: false, restorationPending: true), .wait)
        // Recovery readback clears the journal. Start wins before any capture;
        // background battery reads remain suppressed throughout preparation.
        XCTAssertEqual(startup.next(ready: true, permissions: true, busy: false, restorationPending: false), .start)
        XCTAssertNil(poll(&schedule, at: 152, preparing: true))
        XCTAssertEqual(startup.next(ready: true, permissions: true, busy: false, restorationPending: false), .wait)
    }
}
