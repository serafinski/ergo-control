import XCTest
@testable import ErgoControl

final class AppLogTests: XCTestCase {
    private var folder: URL!
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("ergo-log-\(UUID().uuidString)")
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }
    func testFailurePersistsAcrossLaunchAndCopyContainsReason() throws {
        let log = AppLog(folder: folder)
        log.record("Mapping stopped: malformed pointer report.", category: "Keyboard", level: .error)
        log.flush()
        let reopened = AppLog(folder: folder)
        XCTAssertEqual(reopened.entries.count, 1)
        XCTAssertEqual(reopened.entries[0].level, .error)
        XCTAssertTrue(reopened.text.contains("[error] Keyboard: Mapping stopped: malformed pointer report."))
        let attributes = try FileManager.default.attributesOfItem(atPath: log.file.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testHistoryAndMessagesAreBounded() {
        let log = AppLog(folder: folder)
        for index in 0..<(AppLog.limit + 2) { log.record("Event \(index)") }
        XCTAssertEqual(log.entries.count, AppLog.limit)
        XCTAssertEqual(log.entries.first?.message, "Event 2")
        log.record(String(repeating: "x", count: 1000))
        XCTAssertEqual(log.entries.last?.message.count, 800)
        log.flush()
        XCTAssertEqual(AppLog(folder: folder).entries.count, AppLog.limit)
    }
    func testDuplicateCoalescingAndClearArePersisted() {
        let log = AppLog(folder: folder)
        let time = Date()
        log.record("Lighting unavailable", level: .warning, now: time)
        log.record("Lighting unavailable", level: .warning, now: time.addingTimeInterval(0.5))
        XCTAssertEqual(log.entries.count, 1)
        log.record("Lighting unavailable", level: .warning, now: time.addingTimeInterval(2))
        XCTAssertEqual(log.entries.count, 2)
        log.clear()
        log.flush()
        XCTAssertTrue(AppLog(folder: folder).entries.isEmpty)
    }
}
