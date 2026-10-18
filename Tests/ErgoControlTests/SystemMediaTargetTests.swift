import XCTest
import ErgoCore
@testable import ErgoControl

final class SystemMediaTargetTests: XCTestCase {
    func testSuccessfulReadReturnsOnMainAndReleasesTheNextQuery() {
        let reader = SystemMediaTarget(reader: { .available })
        let first = expectation(description: "First query")
        reader.query { result in
            XCTAssertTrue(Thread.isMainThread); XCTAssertEqual(result, .available)
            first.fulfill()
        }
        wait(for: [first], timeout: 1)
        let second = expectation(description: "Second query")
        reader.query { result in XCTAssertEqual(result, .available); second.fulfill() }
        wait(for: [second], timeout: 1)
    }
    func testHungReadHasBoundedFailureAndLateResultCannotIssueASecondCommand() {
        let gate = DispatchSemaphore(value: 0)
        let started = expectation(description: "Read started")
        let failed = expectation(description: "Timed out safely")
        let duplicate = expectation(description: "No late result")
        duplicate.isInverted = true
        let reader = SystemMediaTarget(reader: {
            started.fulfill(); gate.wait(); return .available
        }, timeout: 0.02)
        var replies = 0
        reader.query { result in
            replies += 1
            if replies == 1 { XCTAssertEqual(result, .unknown); failed.fulfill() }
            else { duplicate.fulfill() }
        }
        wait(for: [started, failed], timeout: 1)
        reader.query { result in XCTAssertEqual(result, .unknown) }
        gate.signal()
        wait(for: [duplicate], timeout: 0.1)
        XCTAssertEqual(replies, 1)
    }
}
