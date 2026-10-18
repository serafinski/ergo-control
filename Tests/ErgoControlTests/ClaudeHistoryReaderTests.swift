import XCTest
import ErgoCore
@testable import ErgoControl

final class ClaudeHistoryReaderTests: XCTestCase {
    var root: URL!
    var scope: URL!
    let desktop = "local_11111111-1111-4111-8111-111111111111"
    let hook = "22222222-2222-4222-8222-222222222222"
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ergo-claude-\(UUID().uuidString)")
        scope = root.appendingPathComponent("account/org")
        try FileManager.default.createDirectory(at: scope, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    @discardableResult func write(_ extra: [String: Any] = [:], id: String? = nil, folder: URL? = nil) throws -> URL {
        let id = id ?? desktop
        var record: [String: Any] = ["sessionId": id, "cliSessionId": hook, "title": "Example", "lastActivityAt": 1000]
        record.merge(extra) { _, b in b }
        let url = (folder ?? scope).appendingPathComponent(id + ".json")
        try JSONSerialization.data(withJSONObject: record).write(to: url)
        return url
    }
    func testReadsMetadataWithoutTranscriptAccessOrWrites() throws {
        let file = try write(["prompt": "secret", "messages": ["secret content"], "transcriptPath": "/inaccessible/secret"])
        let original = try Data(contentsOf: file)
        let records = try ClaudeHistoryReader.readCatalog(root: root)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].id, desktop)
        XCTAssertEqual(records[0].hookID, hook)
        XCTAssertEqual(records[0].title, "Example")
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
    func testRecentAndStarredOrderFilterArchivedRemoteAndChildSessions() throws {
        _ = try write(["isStarred": true, "lastActivityAt": 20])
        let second = "local_33333333-3333-4333-8333-333333333333"
        _ = try write(["lastActivityAt": 30], id: second)
        for (key, value) in [("isArchived", true as Any), ("remoteTarget", ["host": "example"] as Any),
                              ("sshConfig", ["host": "example"] as Any), ("parentSessionId", desktop as Any),
                              ("sessionType", "cowork" as Any)] {
            _ = try write([key: value], id: "local_" + UUID().uuidString.lowercased())
        }
        let records = try ClaudeHistoryReader.readCatalog(root: root)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(ClaudeThreadSummary.slots(records).compactMap(\.threadID), [second, desktop])
        XCTAssertEqual(ClaudeThreadSummary.slots(records, starredOnly: true).compactMap(\.threadID), [desktop])
    }
    func testMultipleAccountsRequireExplicitScope() throws {
        _ = try write()
        let other = root.appendingPathComponent("other/org")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        XCTAssertThrowsError(try ClaudeHistoryReader.readCatalog(root: root))
        XCTAssertEqual(try ClaudeHistoryReader.readCatalog(root: root, selected: scope).count, 1)
        XCTAssertTrue(try ClaudeHistoryReader.readCatalog(root: root, selected: other).isEmpty)
    }
    func testMalformedNewRecordMustNotLeaveAWrongRecentList() throws {
        _ = try write()
        let second = scope.appendingPathComponent("local_33333333-3333-4333-8333-333333333333.json")
        try Data("{partial".utf8).write(to: second)
        XCTAssertThrowsError(try ClaudeHistoryReader.readCatalog(root: root))
    }
    func testRejectsMismatchedIDsOversizedFilesAndFutureFormats() throws {
        let file = try write()
        try JSONSerialization.data(withJSONObject: ["sessionId": "local_" + UUID().uuidString]).write(to: file)
        XCTAssertThrowsError(try ClaudeHistoryReader.readCatalog(root: root))
        try Data(repeating: 32, count: 1_048_577).write(to: file)
        XCTAssertThrowsError(try ClaudeHistoryReader.readCatalog(root: root))
        try FileManager.default.removeItem(at: file)
        try Data("{}".utf8).write(to: scope.appendingPathComponent("local_future.json"))
        XCTAssertThrowsError(try ClaudeHistoryReader.readCatalog(root: root))
    }
    func testIgnoresUnrelatedFilesAndRefusesCatalogSymlinks() throws {
        try Data("not a session".utf8).write(to: scope.appendingPathComponent("scheduled-tasks.json"))
        let file = try write()
        let records = try ClaudeHistoryReader.readCatalog(root: root)
        XCTAssertEqual(records.count, 1)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: scope)
        XCTAssertThrowsError(try ClaudeHistoryReader.readCatalog(root: root, selected: link))
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: scope.appendingPathComponent("scheduled-tasks.json"))
        XCTAssertThrowsError(try ClaudeHistoryReader.readCatalog(root: root, selected: scope))
    }
    func testRefreshDeliversOnMainAndStopSuppressesOldRead() throws {
        _ = try write()
        let reader = ClaudeHistoryReader(root: root)
        let done = expectation(description: "catalog")
        reader.onRecent = { slots in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(slots[0].threadID, self.desktop)
            done.fulfill()
        }
        reader.refresh()
        wait(for: [done], timeout: 3)
        reader.stop()
        let suppressed = expectation(description: "stopped callback"); suppressed.isInverted = true
        reader.onRecent = { _ in suppressed.fulfill() }
        reader.refresh(); reader.stop()
        wait(for: [suppressed], timeout: 0.15)
    }
}
