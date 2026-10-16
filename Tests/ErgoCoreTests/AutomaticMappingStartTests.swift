import XCTest
@testable import ErgoCore

final class AutomaticMappingStartTests: XCTestCase {
    func testWaitsForKeyboardPermissionsAndRecoveryBeforeOneAttempt() {
        var policy = AutomaticMappingStart()
        policy.arm()
        XCTAssertEqual(policy.next(ready: false, permissions: true, busy: false, restorationPending: false), .wait)
        XCTAssertEqual(policy.next(ready: true, permissions: false, busy: false, restorationPending: false), .wait)
        XCTAssertEqual(policy.next(ready: true, permissions: true, busy: false, restorationPending: true), .wait)
        XCTAssertEqual(policy.next(ready: true, permissions: true, busy: true, restorationPending: false), .wait)
        XCTAssertEqual(policy.next(ready: true, permissions: true, busy: false, restorationPending: false), .start)
        XCTAssertEqual(policy.next(ready: true, permissions: true, busy: false, restorationPending: false), .wait)
    }
    func testManualCancellationDoesNotStartLater() {
        var policy = AutomaticMappingStart()
        policy.arm(); policy.cancel()
        XCTAssertEqual(policy.next(ready: true, permissions: true, busy: false, restorationPending: false), .wait)
        policy.arm()
        XCTAssertEqual(policy.next(ready: true, permissions: true, busy: false, restorationPending: false), .start)
        XCTAssertEqual(policy.next(ready: true, permissions: true, busy: false, restorationPending: false), .wait)
    }
    func testLongReadinessWaitStillStartsExactlyOnce() {
        var policy = AutomaticMappingStart()
        policy.arm()
        // Ten minutes of two-second readiness checks, with the keyboard absent
        // first, then permissions/recovery/channel readiness arriving later.
        for tick in 0..<300 {
            XCTAssertEqual(policy.next(ready: tick >= 100, permissions: tick >= 150,
                                       busy: tick >= 250, restorationPending: tick >= 150 && tick < 250), .wait)
        }
        XCTAssertEqual(policy.next(ready: true, permissions: true, busy: false, restorationPending: false), .start)
        // Once activation is attempted, failure/disconnection must not rearm it.
        XCTAssertEqual(policy.next(ready: false, permissions: true, busy: false, restorationPending: false), .wait)
        XCTAssertEqual(policy.next(ready: true, permissions: true, busy: false, restorationPending: false), .wait)
    }
}
