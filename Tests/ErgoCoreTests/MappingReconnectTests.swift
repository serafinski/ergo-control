import XCTest
@testable import ErgoCore

final class MappingReconnectTests: XCTestCase {
    func testEstablishedSessionWaitsThroughLongDisconnectAndRestorationThenStartsOnce() {
        var reconnect = MappingReconnectPolicy()
        var startup = AutomaticMappingStart()
        reconnect.activated(timed: false)
        XCTAssertEqual(reconnect.connectionLost(running: true, preparing: false, automatic: true, terminating: false), .resume)
        startup.arm()
        // A keyboard can sleep indefinitely; no capture/activation occurs while
        // it is missing, while permissions are absent, or before restoration.
        for _ in 0..<600 {
            XCTAssertEqual(startup.next(ready: false, permissions: true, busy: false, restorationPending: true), .wait)
        }
        XCTAssertEqual(startup.next(ready: true, permissions: true, busy: false, restorationPending: true), .wait)
        XCTAssertEqual(startup.next(ready: true, permissions: false, busy: false, restorationPending: false), .wait)
        XCTAssertEqual(startup.next(ready: true, permissions: true, busy: true, restorationPending: false), .wait)
        XCTAssertEqual(startup.next(ready: true, permissions: true, busy: false, restorationPending: false), .start)
        XCTAssertEqual(startup.next(ready: true, permissions: true, busy: false, restorationPending: false), .wait)
        // Failed activation does not establish a session and must not rearm.
        XCTAssertEqual(reconnect.connectionLost(running: false, preparing: true, automatic: true, terminating: false), .stop)
        reconnect.activated(timed: false)
        XCTAssertEqual(reconnect.connectionLost(running: true, preparing: false, automatic: true, terminating: false), .resume)
    }
    func testDuplicateTransportLossDoesNotCancelPendingResumeAndManualStopDoes() {
        var reconnect = MappingReconnectPolicy()
        var startup = AutomaticMappingStart()
        reconnect.activated(timed: false)
        XCTAssertEqual(reconnect.connectionLost(running: true, preparing: false, automatic: true, terminating: false), .resume)
        startup.arm()
        for _ in 0..<3 {
            XCTAssertEqual(reconnect.connectionLost(running: false, preparing: false, automatic: true, terminating: false), .ignore)
        }
        XCTAssertEqual(startup.next(ready: true, permissions: true, busy: false, restorationPending: true), .wait)
        reconnect.cancel(); startup.cancel()
        XCTAssertEqual(startup.next(ready: true, permissions: true, busy: false, restorationPending: false), .wait)
        XCTAssertEqual(reconnect.connectionLost(running: false, preparing: false, automatic: true, terminating: false), .ignore)
    }
    func testDisabledAutomaticStartupTimedTestsAndTerminationDoNotResume() {
        for scenario in [(automatic: false, timed: false, terminating: false),
                         (automatic: true, timed: true, terminating: false),
                         (automatic: true, timed: false, terminating: true)] {
            var reconnect = MappingReconnectPolicy()
            reconnect.activated(timed: scenario.timed)
            XCTAssertEqual(reconnect.connectionLost(running: true, preparing: false,
                automatic: scenario.automatic, terminating: scenario.terminating), .stop)
        }
    }
    func testManualOrFatalStopClearsEstablishedIntentAndPreparationCannotRearmIt() {
        var reconnect = MappingReconnectPolicy()
        reconnect.activated(timed: false)
        reconnect.cancel()
        XCTAssertEqual(reconnect.connectionLost(running: false, preparing: true, automatic: true, terminating: false), .stop)
        XCTAssertEqual(reconnect.connectionLost(running: false, preparing: false, automatic: true, terminating: false), .ignore)
    }
    func testOnlyExactPhysicalKeyboardLossFromTheExistingHelperIsRecoverable() {
        XCTAssertEqual(InputCaptureStopReason(helperMessage: "PT Ergo disconnected"), .keyboardDisconnected)
        for reason in ["The input helper disconnected. Native keyboard input will return automatically.",
                       "The input lease ended. Enable mappings to try again.",
                       "PT Ergo input changed or capture failed", "Input delivery changed; mappings stopped", ""] {
            XCTAssertEqual(InputCaptureStopReason(helperMessage: reason), .failure)
        }
    }
}
