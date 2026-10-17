import XCTest
import ErgoCore

final class DriverModeCheckScheduleTests: XCTestCase {
    func testReadbacksFollowElapsedTimeInsteadOfRenewedLeaseCountdown() {
        var schedule = DriverModeCheckSchedule()
        XCTAssertTrue(schedule.isDue(at: 100))
        schedule.verified(at: 100)
        for time in stride(from: 105.0, through: 125.0, by: 5) {
            XCTAssertFalse(schedule.isDue(at: time), "Local lease renewal must not cause another Bluetooth read")
        }
        XCTAssertTrue(schedule.isDue(at: 130))
        schedule.verified(at: 130)
        XCTAssertFalse(schedule.isDue(at: 159.99))
        XCTAssertTrue(schedule.isDue(at: 160))
    }
    func testBusyChannelDoesNotConsumeReadbackAndNewSessionStartsFresh() {
        var schedule = DriverModeCheckSchedule()
        schedule.verified(at: 10)
        XCTAssertTrue(schedule.isDue(at: 40))
        XCTAssertTrue(schedule.isDue(at: 45)) // Skipped due to busy lighting.
        schedule.verified(at: 46)
        XCTAssertFalse(schedule.isDue(at: 75))
        XCTAssertTrue(schedule.isDue(at: 76))
        schedule.verified(at: 77) // Mandatory initial verification after a new start.
        XCTAssertFalse(schedule.isDue(at: 78))
    }
}
