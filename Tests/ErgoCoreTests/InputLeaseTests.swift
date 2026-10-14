import XCTest
@testable import ErgoCore

final class InputLeaseTests: XCTestCase {
    func testIdleHeartbeatAndExpiry() {
        var lease = InputLease(); lease.begin(now: 10)
        XCTAssertTrue(lease.renew(ack: 0, now: 12))
        XCTAssertTrue(lease.isValid(now: 14.99))
        XCTAssertFalse(lease.isValid(now: 15))
        XCTAssertFalse(lease.renew(ack: 0, now: 15))
    }
    func testStalledReportReceiverCannotRenewForever() {
        var lease = InputLease(); lease.begin(now: 0)
        XCTAssertEqual(lease.nextReport(now: 0.1), 1)
        XCTAssertTrue(lease.renew(ack: 0, now: 2))
        XCTAssertFalse(lease.renew(ack: 0, now: 3))
        XCTAssertFalse(lease.active)
    }
    func testProgressRenewsAndForgedOrBackwardAcksStop() {
        var lease = InputLease(); lease.begin(now: 0)
        _ = lease.nextReport(now: 1)
        XCTAssertTrue(lease.renew(ack: 1, now: 2))
        XCTAssertTrue(lease.isValid(now: 4.9))
        XCTAssertFalse(lease.renew(ack: 0, now: 3))
        lease.begin(now: 10)
        XCTAssertFalse(lease.renew(ack: 1, now: 10.1))
    }
    func testBacklogAndEndedSessionRelease() {
        var lease = InputLease(); lease.begin(now: 0)
        for i in 1...InputLease.maximumPending { XCTAssertEqual(lease.nextReport(now: 0.1), i) }
        XCTAssertNil(lease.nextReport(now: 0.2))
        XCTAssertFalse(lease.active)
        lease.begin(now: 1); lease.end()
        XCTAssertNil(lease.nextReport(now: 1.1))
        XCTAssertFalse(lease.renew(ack: 0, now: 1.1))
    }
}
