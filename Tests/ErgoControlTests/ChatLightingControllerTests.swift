import XCTest
import ErgoCore
@testable import ErgoControl

final class ChatLightingControllerTests: XCTestCase {
    var folder: URL!
    var clock = Date(timeIntervalSince1970: 1000)
    var codex: ChatBridge!
    var claude: ChatBridge!
    var controller: ChatLightingController!
    let codexID = "11111111-1111-4111-8111-111111111111"
    let claudeID = "22222222-2222-4222-8222-222222222222"
    let desktopID = "local_33333333-3333-4333-8333-333333333333"
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("ergo-lighting-routing-\(UUID().uuidString)")
        codex = ChatBridge(folder: folder.appendingPathComponent("Codex"), startTimer: false, now: { [unowned self] in clock })
        claude = ChatBridge(provider: .claude, folder: folder.appendingPathComponent("Claude"), startTimer: false, now: { [unowned self] in clock })
        for bridge in [codex!, claude!] { bridge.setSelection(.fixed); bridge.setEnabled(true); bridge.setLighting(true) }
        codex.assign(0, name: "Codex example", link: codexID)
        claude.assign(0, name: "Claude example", link: desktopID)
        let record = try JSONDecoder().decode(ClaudeThreadSummary.self, from: JSONSerialization.data(withJSONObject:
            ["sessionId": desktopID, "cliSessionId": claudeID, "title": "Claude example"]))
        claude.receiveClaudeRecords([record])
        controller = ChatLightingController(codex: codex, claude: claude, uptime: { [unowned self] in clock.timeIntervalSince1970 })
    }
    override func tearDownWithError() throws {
        codex.shutdown(); claude.shutdown(); controller = nil; codex = nil; claude = nil
        try FileManager.default.removeItem(at: folder)
    }
    private func emit(_ provider: ChatProvider, _ event: String, turn: String = "turn-a") throws {
        clock += 1
        let bridge = provider == .codex ? codex! : claude!
        let data = try JSONSerialization.data(withJSONObject:
            ["session_id": provider == .codex ? codexID : claudeID, "hook_event_name": event, "turn_id": turn,
             "prompt_id": turn == "turn-a" ? "44444444-4444-4444-8444-444444444444" : "55555555-5555-4555-8555-555555555555"])
        let normalized = provider == .codex ? try CodexHookEvent(input: data, time: clock) : try ClaudeHookEvent.parse(data, time: clock)
        try JSONEncoder().encode(normalized).write(to: folder.appendingPathComponent("\(provider.directory)/events/\(UUID().uuidString).json"))
        bridge.poll()
    }
    func testCompletionBrieflyOverridesOtherWorkThenResumesItsPaletteAndStyle() throws {
        claude.setLightingArea(.completionWave); claude.setWaveSpeed(.quick); claude.setDarkStatusBackground(true)
        codex.setLightingArea(.wholeKeyboard)
        try emit(.claude, "UserPromptSubmit")
        var output = controller.output(mode: .automatic)
        XCTAssertEqual(output.provider, .claude); XCTAssertEqual(output.color, claude.statusColors.working)
        let claudePhase = output.signalID
        XCTAssertEqual(output.area, .completionWave); XCTAssertEqual(output.speed, .quick); XCTAssertTrue(output.darkBackground)
        try emit(.codex, "UserPromptSubmit")
        output = controller.output(mode: .automatic)
        XCTAssertEqual(output.provider, .codex); XCTAssertEqual(output.color, codex.statusColors.working)
        XCTAssertEqual(output.area, .wholeKeyboard)
        try emit(.claude, "PreToolUse")
        XCTAssertEqual(controller.output(mode: .automatic).provider, .codex)
        try emit(.codex, "Stop")
        output = controller.output(mode: .automatic)
        XCTAssertEqual(output.provider, .codex); XCTAssertEqual(output.color, codex.statusColors.finished)
        XCTAssertEqual(output.refreshAfter, 4)
        clock += 4
        output = controller.output(mode: .automatic)
        XCTAssertEqual(output.provider, .claude); XCTAssertEqual(output.signalID, claudePhase)
        try emit(.claude, "SessionEnd")
        XCTAssertNil(controller.output(mode: .automatic).color, "The Codex completion already played once")
    }
    func testApprovalResumptionReturnsToNewestTurnAndIdleRestoresAfterFinalCompletion() throws {
        codex.setLightingArea(.completionWave); claude.setLightingArea(.completionWave)
        try emit(.claude, "UserPromptSubmit"); try emit(.codex, "UserPromptSubmit")
        _ = controller.output(mode: .automatic)
        try emit(.claude, "PermissionRequest")
        XCTAssertEqual(controller.output(mode: .automatic).color, claude.statusColors.attention)
        try emit(.claude, "PreToolUse")
        XCTAssertEqual(controller.output(mode: .automatic).provider, .codex)
        try emit(.codex, "Stop")
        let codexCompletion = controller.output(mode: .automatic)
        XCTAssertEqual(codexCompletion.color, codex.statusColors.finished)
        XCTAssertTrue(controller.completeWave(try XCTUnwrap(codexCompletion.signalID)))
        XCTAssertEqual(controller.output(mode: .automatic).provider, .claude)
        try emit(.claude, "Stop")
        var output = controller.output(mode: .automatic)
        XCTAssertEqual(output.color, claude.statusColors.finished); XCTAssertEqual(output.activity, .finished)
        clock += 9; codex.poll(); claude.poll()
        output = controller.output(mode: .automatic)
        XCTAssertEqual(output.activity, .finished, "Wait for the acknowledged wave even after hook activity becomes idle")
        XCTAssertTrue(controller.completeWave(try XCTUnwrap(output.signalID)))
        output = controller.output(mode: .automatic)
        XCTAssertNil(output.color); XCTAssertTrue(output.allowCompletionToFinish)
    }
    func testClaudeFinishingFirstShowsCyanThenReturnsToCodexWithoutReplaying() throws {
        codex.setLightingArea(.completionWave); claude.setLightingArea(.completionWave)
        try emit(.claude, "UserPromptSubmit"); try emit(.codex, "UserPromptSubmit")
        let working = controller.output(mode: .automatic)
        XCTAssertEqual(working.provider, .codex)
        try emit(.claude, "Stop")
        let completion = controller.output(mode: .automatic)
        XCTAssertEqual(completion.provider, .claude); XCTAssertEqual(completion.color, claude.statusColors.finished)
        XCTAssertTrue(controller.completeWave(try XCTUnwrap(completion.signalID)))
        XCTAssertEqual(controller.output(mode: .automatic).signalID, working.signalID)
        try emit(.claude, "Stop")
        XCTAssertEqual(controller.output(mode: .automatic).activity, .working)
    }
    func testWorkingHooksNeitherStealNorExtendASolidCompletionNotification() throws {
        try emit(.codex, "UserPromptSubmit"); try emit(.claude, "Stop")
        XCTAssertEqual(controller.output(mode: .automatic).color, claude.statusColors.finished)
        try emit(.codex, "PreToolUse")
        let stillFinishing = controller.output(mode: .automatic)
        XCTAssertEqual(stillFinishing.color, claude.statusColors.finished)
        XCTAssertEqual(stillFinishing.refreshAfter, 3)
        clock += 3
        XCTAssertEqual(controller.output(mode: .automatic).color, codex.statusColors.working)
    }
    func testApprovalDefersCompletionPastExpiryAndRendererFailureHasFiniteFallback() throws {
        claude.setLightingArea(.completionWave)
        try emit(.codex, "PermissionRequest"); try emit(.claude, "Stop")
        XCTAssertEqual(controller.output(mode: .automatic).color, codex.statusColors.attention)
        clock += 20; claude.poll()
        try emit(.codex, "PreToolUse")
        let completion = controller.output(mode: .automatic)
        XCTAssertEqual(completion.color, claude.statusColors.finished)
        XCTAssertEqual(completion.refreshAfter, 30)
        clock += 30
        XCTAssertEqual(controller.output(mode: .automatic).provider, .codex)
        XCTAssertFalse(controller.completeWave(try XCTUnwrap(completion.signalID)))
    }
    func testManualModeAndDisabledProviderRespectOptInsAndShutdown() throws {
        try emit(.codex, "UserPromptSubmit"); try emit(.claude, "UserPromptSubmit")
        XCTAssertEqual(controller.output(mode: .codex).provider, .codex)
        XCTAssertEqual(controller.output(mode: .claude).provider, .claude)
        claude.setLighting(false)
        XCTAssertEqual(controller.output(mode: .automatic).provider, .codex)
        claude.setLighting(true); claude.setEnabled(false)
        XCTAssertEqual(controller.output(mode: .automatic).provider, .codex)
        codex.shutdown()
        let output = controller.output(mode: .automatic)
        XCTAssertNil(output.color); XCTAssertFalse(output.allowCompletionToFinish)
    }
    func testNewTurnNotifiesEvenWhenSolidWorkingColorIsUnchanged() throws {
        var changes = 0
        codex.onLightingChange = { _ in changes += 1 }
        try emit(.codex, "UserPromptSubmit")
        let first = changes
        try emit(.codex, "PreToolUse")
        XCTAssertEqual(changes, first)
        try emit(.codex, "UserPromptSubmit", turn: "turn-b")
        XCTAssertEqual(changes, first + 1, "Arbitration needs the new turn even in solid lighting styles")
    }
    func testPreviewTemporarilyOverridesBothAppsThenResumesLiveStatus() throws {
        try emit(.codex, "PermissionRequest"); try emit(.claude, "UserPromptSubmit")
        claude.startLightingTest()
        XCTAssertEqual(controller.output(mode: .automatic).provider, .claude)
        XCTAssertEqual(controller.output(mode: .codex).provider, .codex)
        claude.cancelLightingTest()
        XCTAssertEqual(controller.output(mode: .automatic).color, codex.statusColors.attention)
    }
    func testLegacyProviderSettingsMigrateToIndependentAutomaticLighting() throws {
        let file = folder.appendingPathComponent("provider.json")
        try JSONEncoder().encode(ChatProvider.claude).write(to: file)
        let prefs = ChatPreferences(file: file)
        XCTAssertEqual(prefs.provider, .claude); XCTAssertEqual(prefs.lightingMode, .automatic)
        XCTAssertTrue(prefs.selectLighting(.codex))
        XCTAssertEqual(prefs.provider, .claude)
        XCTAssertTrue(prefs.select(.codex)); XCTAssertEqual(prefs.lightingMode, .codex)
        let saved = ChatPreferences(file: file)
        XCTAssertEqual(saved.provider, .codex); XCTAssertEqual(saved.lightingMode, .codex)
        XCTAssertTrue(saved.selectLighting(.automatic))
        XCTAssertEqual(ChatPreferences(file: file).lightingMode, .automatic)
    }
    func testFailedPreferenceWritePreservesBothSelections() throws {
        let blocked = folder.appendingPathComponent("blocked")
        try Data("not a directory".utf8).write(to: blocked)
        let prefs = ChatPreferences(file: blocked.appendingPathComponent("provider.json"))
        XCTAssertFalse(prefs.selectLighting(.claude))
        XCTAssertFalse(prefs.select(.claude))
        XCTAssertEqual(prefs.provider, .codex); XCTAssertEqual(prefs.lightingMode, .automatic)
        XCTAssertNotNil(prefs.error)
    }
}
