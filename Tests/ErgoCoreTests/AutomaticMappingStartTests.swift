import XCTest
@testable import ErgoCore

final class AutomaticMappingStartTests: XCTestCase {
    func testWaitsForKeyboardPermissionsAndRecoveryBeforeOneAttempt() {
        var policy = AutomaticMappingStart()
        policy.arm(at: 0)
        XCTAssertEqual(policy.next(at: 1, ready: false, permissions: true, busy: false, restorationPending: false), .wait)
        XCTAssertEqual(policy.next(at: 2, ready: true, permissions: false, busy: false, restorationPending: false), .wait)
        XCTAssertEqual(policy.next(at: 3, ready: true, permissions: true, busy: false, restorationPending: true), .wait)
        XCTAssertEqual(policy.next(at: 4, ready: true, permissions: true, busy: true, restorationPending: false), .wait)
        XCTAssertEqual(policy.next(at: 5, ready: true, permissions: true, busy: false, restorationPending: false), .start)
        XCTAssertEqual(policy.next(at: 6, ready: true, permissions: true, busy: false, restorationPending: false), .wait)
    }
    func testManualCancellationAndExpiryDoNotStartLater() {
        var policy = AutomaticMappingStart()
        policy.arm(at: 0); policy.cancel()
        XCTAssertEqual(policy.next(at: 1, ready: true, permissions: true, busy: false, restorationPending: false), .wait)
        policy.arm(at: 10)
        XCTAssertEqual(policy.next(at: 130, ready: true, permissions: true, busy: false, restorationPending: false), .expired)
        XCTAssertEqual(policy.next(at: 131, ready: true, permissions: true, busy: false, restorationPending: false), .wait)
        policy.arm(at: 140)
        XCTAssertEqual(policy.next(at: 141, ready: true, permissions: true, busy: false, restorationPending: false), .start)
    }
}
