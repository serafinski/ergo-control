import XCTest
import ErgoCore
@testable import ErgoControl

final class CodexBridgeTests: XCTestCase {
    final class History: CodexHistorySource {
        var onRecent: (([CodexSlot]) -> Void)?
        var onPinned: (([CodexSlot]) -> Void)?
        var onProblem: ((CodexHistoryIssue) -> Void)?
        var refreshes = 0
        var stops = 0
        func refresh() { refreshes += 1 }
        func stop() { stops += 1 }
    }
    var folder: URL!
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("ergo-codex-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }
    func fixedBridge() -> CodexBridge {
        let bridge = CodexBridge(folder: folder, startTimer: false)
        bridge.setSelection(.fixed)
        return bridge
    }
    func enqueue(_ index: Int, name: String = "UserPromptSubmit", time: Date = Date(), turn: String? = nil) throws -> String {
        let id = String(format: "01a13698-ddb7-7381-9a6a-%012d", index)
        var fields: [String: Any] = ["session_id": id, "cwd": "/private/project-\(index)", "hook_event_name": name]
        if let turn { fields["turn_id"] = turn }
        let input = try JSONSerialization.data(withJSONObject: fields)
        let event = try CodexHookEvent(input: input, time: time)
        try JSONEncoder().encode(event).write(to: folder.appendingPathComponent("events/\(UUID().uuidString).json"))
        return id
    }
    func testOptInAndShutdownControlSenderPresence() throws {
        let bridge = fixedBridge()
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
        let bridge = fixedBridge(); bridge.setEnabled(true)
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
        let bridge = fixedBridge(); bridge.setEnabled(true)
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
        let bridge = fixedBridge(); bridge.setEnabled(true)
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
    func testRecentChatsFollowHistoryUpdatesAndPinnedIsOptional() throws {
        let source = History()
        let bridge = CodexBridge(folder: folder, startTimer: false, history: source)
        XCTAssertEqual(bridge.settings.selection, .recent)
        XCTAssertEqual(source.refreshes, 0)
        bridge.setEnabled(true)
        XCTAssertEqual(source.refreshes, 1)
        var a = CodexSlot(1); a.name = "Recent A"; a.threadID = UUID().uuidString.lowercased()
        var b = CodexSlot(1); b.name = "Recent B"; b.threadID = UUID().uuidString.lowercased()
        source.onRecent?([a])
        XCTAssertEqual(bridge.displaySlots[0], a)
        source.onRecent?([b])
        XCTAssertEqual(bridge.displaySlots[0], b, "M1 must follow the current list without manual reassignment")
        source.onPinned?([a])
        XCTAssertEqual(bridge.displaySlots[0], b, "Receiving pinned metadata must not make it the default")
        bridge.setSelection(.pinned)
        XCTAssertEqual(bridge.displaySlots[0], a)
        bridge.setSelection(.recent)
        XCTAssertEqual(bridge.displaySlots[0], b)
        XCTAssertTrue(bridge.settings.slots.allSatisfy { $0.threadID == nil }, "Automatic lists must not overwrite fixed assignments")
        bridge.shutdown()
    }
    func testFixedAssignmentsSurviveModeChangesAndHistoryStopsWhenDisabled() throws {
        let source = History()
        let bridge = CodexBridge(folder: folder, startTimer: false, history: source)
        bridge.setEnabled(true)
        let id = UUID().uuidString.lowercased()
        bridge.assign(0, name: "Keep this", link: id)
        bridge.setSelection(.fixed)
        XCTAssertEqual(source.stops, 1)
        XCTAssertEqual(bridge.displaySlots[0].threadID, id)
        bridge.setSelection(.recent)
        bridge.setSelection(.fixed)
        XCTAssertEqual(bridge.displaySlots[0].name, "Keep this")
        bridge.setEnabled(false)
        XCTAssertGreaterThanOrEqual(source.stops, 2)
        bridge.shutdown()
    }
    func testUnavailableHistoryClearsAutomaticTargetsButKeepsFixedSettings() {
        let source = History()
        let bridge = CodexBridge(folder: folder, startTimer: false, history: source)
        bridge.setEnabled(true)
        var chat = CodexSlot(1); chat.threadID = UUID().uuidString.lowercased()
        source.onRecent?([chat]); source.onPinned?([chat])
        source.onProblem?(.pinnedUnavailable)
        XCTAssertNotNil(bridge.displaySlots[0].threadID)
        bridge.setSelection(.pinned)
        XCTAssertTrue(bridge.displaySlots.allSatisfy { $0.threadID == nil })
        source.onProblem?(.unavailable("offline"))
        bridge.setSelection(.recent)
        XCTAssertTrue(bridge.displaySlots.allSatisfy { $0.threadID == nil })
        bridge.shutdown()
    }
    func testUnmappedMacroDefaultsNeedNoPerKeyConfigurationAndStayInScope() {
        let bridge = CodexBridge(folder: folder, startTimer: false)
        XCTAssertNil(bridge.defaultAction(for: "extra:32"))
        bridge.setEnabled(true)
        for slot in 1...5 {
            XCTAssertEqual(bridge.defaultAction(for: "extra:\(slot + 31)"), MappingAction(.codexChat, String(slot)))
        }
        for control in ["extra:31", "extra:37", "extra:65", "extra:247", "key:32", "leftCW"] {
            XCTAssertNil(bridge.defaultAction(for: control))
        }
        bridge.setUseUnmappedMacroKeys(false)
        XCTAssertNil(bridge.defaultAction(for: "extra:32"))
        bridge.shutdown()
    }
    func testDynamicLightingFollowsVisibleSlotsAndRetainsObservedStateAcrossReordering() throws {
        let source = History()
        let bridge = CodexBridge(folder: folder, startTimer: false, history: source)
        bridge.setEnabled(true); bridge.setLighting(true)
        let id = try enqueue(1, name: "PermissionRequest"); bridge.poll()
        XCTAssertNil(bridge.lightingColor, "Unlisted activity must not color the column")
        var slot = CodexSlot(1); slot.threadID = id
        source.onRecent?([slot])
        XCTAssertEqual(bridge.lightingColor, CodexActivity.attention.color)
        source.onPinned?([]); bridge.setSelection(.pinned)
        XCTAssertNil(bridge.lightingColor)
        bridge.setSelection(.recent)
        XCTAssertEqual(bridge.activity(slot), .attention)
        bridge.shutdown()
    }
    func testLightingPreviewRunsThroughProductionColorsAndResumesRealStatus() throws {
        var clock: TimeInterval = 100
        let bridge = CodexBridge(folder: folder, startTimer: false, uptime: { clock })
        bridge.setSelection(.fixed); bridge.setEnabled(true); bridge.setLighting(true)
        _ = try enqueue(1); bridge.poll()
        var colors: [DialColor?] = []
        bridge.onLightingChange = { colors.append($0) }
        bridge.startLightingTest()
        XCTAssertEqual(bridge.lightingTestStage, .working)
        XCTAssertEqual(bridge.lightingColor, CodexActivity.working.color)
        clock = 104; bridge.poll()
        XCTAssertEqual(bridge.lightingColor, CodexActivity.attention.color)
        _ = try enqueue(1, name: "Stop"); bridge.poll()
        XCTAssertEqual(bridge.activity(bridge.displaySlots[0]), .finished, "Preview must never replace real hook activity")
        XCTAssertEqual(bridge.lightingColor, CodexActivity.attention.color)
        clock = 108; bridge.poll()
        XCTAssertEqual(bridge.lightingColor, CodexActivity.finished.color)
        clock = 112; bridge.poll()
        XCTAssertEqual(bridge.lightingTestStage, .restore)
        XCTAssertNil(bridge.lightingColor, "The normal renderer must restore the saved effect during this stage")
        clock = 116; bridge.poll()
        XCTAssertNil(bridge.lightingTestStage)
        XCTAssertEqual(bridge.lightingColor, CodexActivity.finished.color)
        XCTAssertEqual(colors, [CodexActivity.attention.color, CodexActivity.finished.color,
                                nil, CodexActivity.finished.color])
        bridge.shutdown()
    }
    func testLightingPreviewRequiresOptInAndCancellationCannotRestartIt() throws {
        var clock: TimeInterval = 100
        let bridge = CodexBridge(folder: folder, startTimer: false, uptime: { clock })
        bridge.startLightingTest(); XCTAssertNil(bridge.lightingTestStage)
        bridge.setEnabled(true); bridge.startLightingTest(); XCTAssertNil(bridge.lightingTestStage)
        bridge.setLighting(true); bridge.startLightingTest(); XCTAssertNotNil(bridge.lightingTestStage)
        bridge.setLighting(false)
        XCTAssertNil(bridge.lightingTestStage); XCTAssertNil(bridge.lightingColor)
        bridge.setLighting(true); bridge.startLightingTest(); bridge.cancelLightingTest()
        clock = 108; bridge.poll()
        XCTAssertNil(bridge.lightingTestStage); XCTAssertNil(bridge.lightingColor)
        bridge.startLightingTest(); bridge.setEnabled(false)
        XCTAssertNil(bridge.lightingTestStage); XCTAssertNil(bridge.lightingColor)
        bridge.setEnabled(true); bridge.startLightingTest(); bridge.shutdown()
        XCTAssertNil(bridge.lightingTestStage)
    }

    func testRealCompletionReleasesLightingWhileEnabledAndNewWorkReacquiresIt() throws {
        var time = Date()
        let bridge = CodexBridge(folder: folder, startTimer: false, now: { time })
        bridge.setSelection(.fixed); bridge.setEnabled(true); bridge.setLighting(true)
        var colors: [DialColor?] = []
        bridge.onLightingChange = { colors.append($0) }
        _ = try enqueue(1, time: time); bridge.poll()
        time.addTimeInterval(1)
        _ = try enqueue(1, name: "Stop", time: time); bridge.poll()
        XCTAssertEqual(bridge.lightingColor, CodexActivity.finished.color)
        time.addTimeInterval(3.9); bridge.poll()
        XCTAssertEqual(bridge.activity(bridge.displaySlots[0]), .finished)
        time.addTimeInterval(0.2); bridge.poll()
        XCTAssertEqual(bridge.activity(bridge.displaySlots[0]), .idle)
        XCTAssertNil(bridge.lightingColor)
        XCTAssertNil(colors.last!)
        XCTAssertTrue(bridge.settings.lighting, "Idle must release the renderer without disabling future status updates")
        bridge.setLightingArea(.wholeKeyboard)
        XCTAssertNil(bridge.lightingColor, "Changing area must not revive old green")
        _ = try enqueue(1, name: "PreToolUse", time: time); bridge.poll()
        XCTAssertEqual(bridge.lightingColor, CodexActivity.working.color)
        let count = colors.count
        bridge.setLightingArea(.macroColumn)
        XCTAssertEqual(colors.count, count + 1, "Area changes must send a new frame even when color is unchanged")
        bridge.shutdown()
        let restored = CodexBridge(folder: folder, startTimer: false)
        XCTAssertEqual(restored.settings.lightingArea, .macroColumn)
        restored.shutdown()
    }
    func testIdleDoesNotClearAnotherWorkingOrApprovalChat() throws {
        var time = Date()
        let bridge = CodexBridge(folder: folder, startTimer: false, now: { time })
        bridge.setSelection(.fixed); bridge.setEnabled(true); bridge.setLighting(true)
        _ = try enqueue(1, name: "Stop", time: time); bridge.poll()
        _ = try enqueue(2, name: "PreToolUse", time: time); bridge.poll()
        time.addTimeInterval(5); bridge.poll()
        XCTAssertEqual(bridge.activity(bridge.displaySlots[0]), .idle)
        XCTAssertEqual(bridge.lightingColor, CodexActivity.working.color)
        _ = try enqueue(2, name: "PermissionRequest", time: time); bridge.poll()
        XCTAssertEqual(bridge.lightingColor, CodexActivity.attention.color)
        time.addTimeInterval(1)
        _ = try enqueue(2, name: "Interrupt", time: time); bridge.poll()
        XCTAssertNil(bridge.lightingColor)
        bridge.shutdown()
    }

    func testWaveCompletionIdentityTracksRealTurnsAndDoesNotColorWorkingAcrossWholeKeyboard() throws {
        var time = Date()
        let bridge = CodexBridge(folder: folder, startTimer: false, now: { time })
        bridge.setSelection(.fixed); bridge.setEnabled(true); bridge.setLighting(true)
        bridge.setLightingArea(.completionWave)
        _ = try enqueue(1, time: time, turn: "turn-a"); bridge.poll()
        XCTAssertNil(bridge.lightingCompletionID)
        time.addTimeInterval(1)
        _ = try enqueue(1, name: "Stop", time: time, turn: "turn-a"); bridge.poll()
        let first = bridge.lightingCompletionID
        XCTAssertNotNil(first)
        time.addTimeInterval(5); bridge.poll()
        XCTAssertEqual(bridge.lightingCompletionID, first, "Give the acknowledged wave time to finish without retriggering it")
        time.addTimeInterval(1)
        _ = try enqueue(1, name: "Stop", time: time, turn: "turn-a"); bridge.poll()
        XCTAssertEqual(bridge.lightingCompletionID, first, "Duplicate Stops from the same turn must not replay a wave")
        time.addTimeInterval(1)
        _ = try enqueue(1, name: "PreToolUse", time: time, turn: "turn-b"); bridge.poll()
        time.addTimeInterval(1)
        _ = try enqueue(1, name: "Stop", time: time, turn: "turn-b"); bridge.poll()
        XCTAssertNotEqual(bridge.lightingCompletionID, first)
        time.addTimeInterval(8); bridge.poll()
        XCTAssertNil(bridge.lightingCompletionID); XCTAssertNil(bridge.lightingColor)
        bridge.shutdown()
    }

}
