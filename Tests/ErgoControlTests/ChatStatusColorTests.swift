import XCTest
import ErgoCore
@testable import ErgoControl

final class ChatStatusColorTests: XCTestCase {
    var folder: URL!
    let custom = DialColor(red: 20, green: 200, blue: 160)
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("ergo-colors-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }
    func event(_ name: String, at time: Date) throws {
        let value = try CodexHookEvent(input: JSONSerialization.data(withJSONObject: ["hook_event_name": name,
            "session_id": "11111111-1111-4111-8111-111111111111", "turn_id": "same-turn"]), time: time)
        try JSONEncoder().encode(value).write(to: folder.appendingPathComponent("events/\(UUID().uuidString).json"))
    }
    func testSeparateDefaultsPersistenceAndResetDoNotChangeOtherProvider() throws {
        let codexFolder = folder.appendingPathComponent("Codex"), claudeFolder = folder.appendingPathComponent("Claude")
        let codex = ChatBridge(folder: codexFolder, startTimer: false)
        let claude = ChatBridge(provider: .claude, folder: claudeFolder, startTimer: false)
        XCTAssertEqual(codex.statusColors, .defaults(for: .codex))
        XCTAssertEqual(claude.statusColors, .defaults(for: .claude))
        codex.setStatusColor(custom, for: .working)
        claude.setStatusColor(custom, for: .attention)
        codex.shutdown(); claude.shutdown()
        let reopenedCodex = ChatBridge(folder: codexFolder, startTimer: false)
        let reopenedClaude = ChatBridge(provider: .claude, folder: claudeFolder, startTimer: false)
        XCTAssertEqual(reopenedCodex.statusColors.working, custom)
        XCTAssertEqual(reopenedClaude.statusColors.attention, custom)
        reopenedClaude.resetStatusColors()
        XCTAssertNil(reopenedClaude.settings.statusColors)
        XCTAssertEqual(reopenedClaude.statusColors, .defaults(for: .claude))
        XCTAssertEqual(reopenedCodex.statusColors.working, custom)
        reopenedCodex.shutdown(); reopenedClaude.shutdown()
    }
    func testEditingLiveWorkingColorNotifiesWithoutChangingWaveIdentity() throws {
        let bridge = ChatBridge(folder: folder, startTimer: false)
        bridge.setSelection(.fixed); bridge.setEnabled(true); bridge.setLighting(true); bridge.setLightingArea(.completionWave)
        try event("UserPromptSubmit", at: Date()); bridge.poll()
        let phase = bridge.lightingSignalID
        var outputs: [DialColor?] = []
        bridge.onLightingChange = { outputs.append($0) }
        bridge.setStatusColor(custom, for: .working)
        XCTAssertEqual(outputs, [custom])
        XCTAssertEqual(bridge.lightingSignalID, phase)
        bridge.shutdown()
    }
    func testEqualRGBStatesStillNotifySoApprovalStopsTheWorkingPulse() throws {
        var time = Date()
        let bridge = ChatBridge(folder: folder, startTimer: false, now: { time })
        bridge.setSelection(.fixed); bridge.setEnabled(true); bridge.setLighting(true); bridge.setPulseWhileWorking(true)
        for activity in [CodexActivity.working, .attention, .finished] { bridge.setStatusColor(custom, for: activity) }
        var activities: [CodexActivity] = []
        bridge.onLightingChange = { _ in activities.append(bridge.lightingActivity) }
        try event("UserPromptSubmit", at: time); bridge.poll()
        time.addTimeInterval(1); try event("PermissionRequest", at: time); bridge.poll()
        time.addTimeInterval(1); try event("Stop", at: time); bridge.poll()
        XCTAssertEqual(activities, [.working, .attention, .finished])
        bridge.shutdown()
    }
    func testClaudePreviewUsesSavedPaletteAndRestoresWithoutSyntheticEvents() {
        var clock: TimeInterval = 100
        let bridge = ChatBridge(provider: .claude, folder: folder, startTimer: false, uptime: { clock })
        bridge.setEnabled(true); bridge.setLighting(true); bridge.setStatusColor(custom, for: .attention)
        bridge.startLightingTest()
        XCTAssertEqual(bridge.lightingColor, ChatStatusColors.defaults(for: .claude).working)
        clock = 104; bridge.poll(); XCTAssertEqual(bridge.lightingColor, custom)
        clock = 108; bridge.poll(); XCTAssertEqual(bridge.lightingColor, ChatStatusColors.defaults(for: .claude).finished)
        clock = 112; bridge.poll(); XCTAssertNil(bridge.lightingColor)
        XCTAssertTrue(bridge.sessions.isEmpty)
        bridge.shutdown()
    }
}
