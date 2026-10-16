import XCTest
@testable import ErgoDevice

final class BluetoothPacketLogTests: XCTestCase {
    private var folder: URL!
    private var url: URL { folder.appendingPathComponent("packets.jsonl") }
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("ergo-packets-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]))
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }

    func testEnqueueDoesNotWaitForDiskAndFlushPreservesOrderAndCaptureTimes() throws {
        let queue = DispatchQueue(label: "ergo-log-test")
        let log = BluetoothPacketLog(file: try FileHandle(forWritingTo: url), queue: queue)
        queue.suspend()
        for index in 0..<50 {
            log.append("packet", fields: ["index": index, "hex": Data([UInt8(index), 255])],
                       time: Date(timeIntervalSince1970: Double(index)), uptime: Double(index) + 0.125)
        }
        let pendingSize = (try? Data(contentsOf: url).count) ?? -1
        queue.resume() // Never leave a suspended queue if an assertion fails.
        XCTAssertEqual(pendingSize, 0, "Capture must not perform synchronous file writes")
        log.flush()
        let entries = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map {
            try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
        }
        XCTAssertEqual(entries.count, 50)
        XCTAssertEqual(entries.map { ($0["index"] as! NSNumber).intValue }, Array(0..<50))
        XCTAssertEqual(entries.first?["hex"] as? String, "00ff")
        XCTAssertEqual(entries.first?["time"] as? String, "1970-01-01T00:00:00Z")
        XCTAssertEqual(entries.last?["uptime"] as? Double, 49.125)
    }

    func testWriteFailureReportsOnceWithoutBlockingCaller() throws {
        let problem = expectation(description: "One diagnostic failure")
        problem.assertForOverFulfill = true
        let log = BluetoothPacketLog(file: try FileHandle(forReadingFrom: url), onFailure: { problem.fulfill() })
        log.append("first", fields: [:]); log.append("second", fields: [:])
        log.flush()
        wait(for: [problem], timeout: 2)
        XCTAssertEqual(try Data(contentsOf: url).count, 0)
    }
}
