import XCTest
import ErgoCore
@testable import ErgoControl

final class CodexBridgeTests: XCTestCase {
    var folder: URL!
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("ergo-codex-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }
    func enqueue(_ index: Int, name: String = "UserPromptSubmit") throws -> String {
        let id = String(format: "01a13698-ddb7-7381-9a6a-%012d", index)
        let input = try JSONSerialization.data(withJSONObject: ["session_id": id, "cwd": "/private/project-\(index)",
                                                               "hook_event_name": name])
        let event = try CodexHookEvent(input: input)
        try JSONEncoder().encode(event).write(to: folder.appendingPathComponent("events/\(UUID().uuidString).json"))
        return id
    }
    func testOptInAndShutdownControlSenderPresence() throws {
        let bridge = CodexBridge(folder: folder, startTimer: false)
        let marker = folder.appendingPathComponent("receiver.pid")
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        _ = try enqueue(1); bridge.poll()
        XCTAssertTrue(bridge.sessions.isEmpty)
        bridge.setEnabled(true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        _ = try enqueue(1); bridge.poll()
        XCTAssertEqual(bridge.sessions.count, 1)
        bridge.shutdown()
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }
    func testFiveSlotsDoNotReorderOrEvictExistingAssignments() throws {
        let bridge = CodexBridge(folder: folder, startTimer: false); bridge.setEnabled(true)
        var ids: [String] = []
        for index in 1...6 { ids.append(try enqueue(index)); bridge.poll() }
        XCTAssertEqual(bridge.settings.slots.compactMap(\.threadID), Array(ids.prefix(5)))
        XCTAssertEqual(bridge.sessions.count, 5)
        _ = try enqueue(1, name: "Stop"); bridge.poll()
        XCTAssertEqual(bridge.settings.slots.compactMap(\.threadID), Array(ids.prefix(5)))
        XCTAssertEqual(bridge.activity(bridge.settings.slots[0]), .finished)
        let saved = CodexBridge(folder: folder, startTimer: false)
        XCTAssertEqual(saved.settings, bridge.settings)
        XCTAssertTrue(saved.sessions.isEmpty, "Activity should not persist as a live status across launch")
        saved.shutdown(); bridge.shutdown()
    }
    func testLightingIsOptInAndPriorityUsesOnlyAssignedChats() throws {
        let bridge = CodexBridge(folder: folder, startTimer: false); bridge.setEnabled(true)
        var colors: [DialColor?] = []
        bridge.onLightingChange = { colors.append($0) }
        _ = try enqueue(1); bridge.poll()
        XCTAssertTrue(colors.isEmpty)
        bridge.setLighting(true)
        XCTAssertEqual(colors.last!, CodexActivity.working.color)
        _ = try enqueue(2, name: "PermissionRequest"); bridge.poll()
        XCTAssertEqual(colors.last!, CodexActivity.attention.color)
        _ = try enqueue(2, name: "Stop"); bridge.poll()
        XCTAssertEqual(colors.last!, CodexActivity.working.color)
        bridge.setEnabled(false)
        XCTAssertNil(colors.last!)
        XCTAssertTrue(bridge.sessions.isEmpty)
    }
    func testManualAssignmentRejectsUnsafeLinksAndDuplicates() throws {
        let bridge = CodexBridge(folder: folder, startTimer: false); bridge.setEnabled(true)
        let id = try enqueue(1); bridge.poll()
        bridge.assign(1, name: "duplicate", link: id)
        XCTAssertNil(bridge.settings.slots[1].threadID)
        bridge.assign(1, name: "unsafe", link: "https://example.com")
        XCTAssertNil(bridge.settings.slots[1].threadID)
        bridge.assign(0, name: "reset", link: "")
        XCTAssertTrue(bridge.sessions.isEmpty)
        XCTAssertNil(bridge.settings.slots[0].threadID)
        bridge.shutdown()
    }
    func testCodexActionOnlyCallsItsDedicatedCallback() {
        var slots: [Int] = []
        var keys: [KeyboardOutput] = []
        let engine = ActionEngine(keyOutput: { output, _ in keys.append(output) })
        engine.onCodexSlot = { slots.append($0) }
        for number in 1...5 { engine.perform(MappingAction(.codexChat, String(number))) }
        XCTAssertEqual(slots, [1,2,3,4,5])
        XCTAssertTrue(keys.isEmpty)
        engine.stop()
    }
}
