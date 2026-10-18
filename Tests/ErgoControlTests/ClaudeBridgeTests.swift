import XCTest
import ErgoCore
@testable import ErgoControl

final class ClaudeBridgeTests: XCTestCase {
    var folder: URL!
    let desktop = "local_11111111-1111-4111-8111-111111111111"
    let hook = "22222222-2222-4222-8222-222222222222"
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("ergo-claude-bridge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }
    func records() throws -> [ClaudeThreadSummary] {
        [try JSONDecoder().decode(ClaudeThreadSummary.self, from: JSONSerialization.data(withJSONObject:
            ["sessionId": desktop, "cliSessionId": hook, "title": "Example", "lastActivityAt": 1000]))]
    }
    func enqueue(_ name: String = "UserPromptSubmit", time: Date = Date()) throws {
        let event = try ClaudeHookEvent.parse(JSONSerialization.data(withJSONObject:
            ["hook_event_name": name, "session_id": hook, "cwd": "/private/project"]), time: time)
        try JSONEncoder().encode(event).write(to: folder.appendingPathComponent("events/\(UUID().uuidString).json"))
    }
    func testDesktopAndEngineIDsAreMatchedWithoutInventingNavigationIDs() throws {
        let source = CodexBridgeTests.History()
        let bridge = ChatBridge(provider: .claude, folder: folder, startTimer: false, history: source)
        bridge.setEnabled(true); bridge.setLighting(true)
        try enqueue(); bridge.poll()
        XCTAssertNil(bridge.lightingColor)
        let rows = try records()
        bridge.receiveClaudeRecords(rows)
        source.onRecent?(ClaudeThreadSummary.slots(rows))
        XCTAssertEqual(bridge.displaySlots[0].threadID, desktop)
        XCTAssertEqual(bridge.activity(bridge.displaySlots[0]), .working)
        let duplicate = try JSONDecoder().decode(ClaudeThreadSummary.self, from: JSONSerialization.data(withJSONObject:
            ["sessionId": "local_33333333-3333-4333-8333-333333333333", "cliSessionId": hook]))
        bridge.receiveClaudeRecords(rows + [duplicate])
        XCTAssertEqual(bridge.activity(bridge.displaySlots[0]), .unknown, "Ambiguous engine identities must not color another desktop chat")
        bridge.receiveClaudeRecords(rows)
        XCTAssertEqual(bridge.url(for: bridge.displaySlots[0])?.query, "session=\(desktop)")
        XCTAssertFalse(bridge.url(for: bridge.displaySlots[0])!.absoluteString.contains(hook))
        bridge.receiveClaudeRecords([])
        XCTAssertEqual(bridge.activity(bridge.displaySlots[0]), .unknown)
        XCTAssertNil(bridge.lightingColor)
        bridge.shutdown()
    }
    func testFixedAssignmentsStillRefreshCatalogAndRestoreWithoutLiveStatus() throws {
        let source = CodexBridgeTests.History()
        let bridge = ChatBridge(provider: .claude, folder: folder, startTimer: false, history: source)
        bridge.setSelection(.fixed); bridge.setEnabled(true)
        XCTAssertEqual(source.refreshes, 1)
        bridge.assign(0, name: "Saved", link: desktop)
        bridge.receiveClaudeRecords(try records())
        try enqueue(); bridge.poll()
        XCTAssertEqual(bridge.activity(bridge.displaySlots[0]), .working)
        bridge.assign(1, name: "Duplicate", link: desktop)
        XCTAssertNil(bridge.settings.slots[1].threadID)
        bridge.shutdown()
        let restored = ChatBridge(provider: .claude, folder: folder, startTimer: false)
        XCTAssertEqual(restored.displaySlots[0].threadID, desktop)
        XCTAssertEqual(restored.activity(restored.displaySlots[0]), .unknown)
        restored.shutdown()
    }
    func testUnmappedClaudeKeysAndExplicitActionsNeverPostKeyboardInput() {
        let bridge = ChatBridge(provider: .claude, folder: folder, startTimer: false)
        bridge.setEnabled(true)
        XCTAssertEqual(bridge.defaultAction(for: "extra:32"), MappingAction(.claudeChat, "1"))
        var codex: [Int] = [], claude: [Int] = [], keys: [KeyboardOutput] = []
        let engine = ActionEngine(keyOutput: { output, _ in keys.append(output) })
        engine.onCodexSlot = { codex.append($0) }; engine.onClaudeSlot = { claude.append($0) }
        engine.perform(MappingAction(.claudeChat, "3"))
        engine.perform(MappingAction(.codexChat, "2"))
        engine.perform(MappingAction(.claudeChat, "6"))
        XCTAssertEqual(codex, [2]); XCTAssertEqual(claude, [3]); XCTAssertTrue(keys.isEmpty)
        engine.stop(); bridge.shutdown()
    }
    func testFailureAndResetReleaseLightingAndExpiredQueueIsDiscarded() throws {
        let source = CodexBridgeTests.History()
        let bridge = ChatBridge(provider: .claude, folder: folder, startTimer: false, history: source)
        bridge.setEnabled(true); bridge.setLighting(true)
        let rows = try records(); bridge.receiveClaudeRecords(rows); source.onRecent?(ClaudeThreadSummary.slots(rows))
        try enqueue(); bridge.poll(); XCTAssertNotNil(bridge.lightingColor)
        try enqueue("StopFailure"); bridge.poll(); XCTAssertNil(bridge.lightingColor)
        try enqueue(); bridge.poll(); bridge.resetStatus(); XCTAssertNil(bridge.lightingColor)
        try enqueue(time: Date().addingTimeInterval(-301)); bridge.poll(); XCTAssertTrue(bridge.sessions.isEmpty)
        try enqueue(); bridge.resetStatus(); bridge.poll()
        XCTAssertTrue(bridge.sessions.isEmpty, "A reset also rejects events already queued before the reset")
        bridge.shutdown()
        XCTAssertNil(bridge.lightingColor)
        XCTAssertNil(bridge.lightingSignalID)
    }
    func testProviderChoiceDefaultsToCodexAndPersistsIndependently() throws {
        let file = folder.appendingPathComponent("provider.json")
        let prefs = ChatPreferences(file: file)
        XCTAssertEqual(prefs.provider, .codex)
        XCTAssertTrue(prefs.select(.claude))
        XCTAssertEqual(ChatPreferences(file: file).provider, .claude)
        XCTAssertNotEqual(ChatBridge.defaultFolder(for: .codex), ChatBridge.defaultFolder(for: .claude))
    }

    func testAvailableClaudeChatDoesNotAssignAnExplicitCodexMacroKey() throws {
        let source = CodexBridgeTests.History()
        let bridge = ChatBridge(provider: .claude, folder: folder, startTimer: false, history: source)
        defer { bridge.shutdown() }
        bridge.setEnabled(true)
        source.onRecent?(ClaudeThreadSummary.slots(try records()))
        XCTAssertEqual(bridge.availableSlotCount, 1)
        var profile = MappingProfile()
        for slot in 1...5 { profile.mappings["extra:\(slot + 31)"] = MappingAction(.codexChat, String(slot)) }
        let keys = MappingResolver.macroKeys(profile: profile, alternateLayer: false, fallback: bridge.defaultAction)
        XCTAssertEqual(keys.filter { $0.provider == .codex }.count, 5)
        XCTAssertEqual(keys.filter { $0.provider == .claude }.count, 0)
        var codex: [Int] = [], claude: [Int] = []
        let engine = ActionEngine(keyOutput: { _, _ in XCTFail("Chat mappings must not post keyboard input") })
        defer { engine.stop() }
        engine.onCodexSlot = { codex.append($0) }; engine.onClaudeSlot = { claude.append($0) }
        keys.forEach { engine.perform($0.mapping.action) }
        XCTAssertEqual(codex, [1, 2, 3, 4, 5]); XCTAssertTrue(claude.isEmpty)
    }

    func testDisablingAutomaticKeysOrConnectionOnlyRemovesFallbackAssignments() {
        let bridge = ChatBridge(provider: .claude, folder: folder, startTimer: false)
        defer { bridge.shutdown() }
        var profile = MappingProfile()
        profile.mappings["extra:32"] = MappingAction(.codexChat, "3")
        profile.mappings["extra:33"] = MappingAction(.disabled)
        profile.mappings["extra:35"] = MappingAction(.claudeChat, "1")
        func keys() -> [MacroKeyAssignment] {
            MappingResolver.macroKeys(profile: profile, alternateLayer: false, fallback: bridge.defaultAction)
        }
        bridge.setEnabled(true)
        XCTAssertEqual(keys().filter { $0.provider == .claude }.map(\.id), [3, 4, 5])
        bridge.setUseUnmappedMacroKeys(false)
        XCTAssertEqual(keys().filter { $0.provider == .claude }.map(\.id), [4])
        bridge.setUseUnmappedMacroKeys(true); bridge.setEnabled(false)
        XCTAssertEqual(keys().filter { $0.provider == .claude }.map(\.id), [4])
        XCTAssertEqual(keys()[0].mapping.action, MappingAction(.codexChat, "3"))
        XCTAssertEqual(keys()[1].mapping.action.kind, .disabled)
        XCTAssertEqual(keys()[2].mapping.origin, .keyboardDefault)
    }
}
