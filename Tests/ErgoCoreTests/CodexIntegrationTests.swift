import XCTest
@testable import ErgoCore

final class CodexIntegrationTests: XCTestCase {
    let id = "01a13698-ddb7-7381-9a6a-8e9e47173a07"
    func event(_ name: String, turn: String = "turn-a", time: Double = 100) throws -> CodexHookEvent {
        try CodexHookEvent(input: JSONSerialization.data(withJSONObject: ["hook_event_name": name,
            "session_id": id, "turn_id": turn, "cwd": "/Users/private/project"]), time: Date(timeIntervalSince1970: time))
    }
    func testHookInputDropsSensitiveContents() throws {
        let input: [String: Any] = ["hook_event_name": "PermissionRequest", "session_id": id,
            "cwd": "/Users/private/project", "transcript_path": "/secret/transcript",
            "prompt": "secret prompt", "tool_input": ["command": "private command"], "tool_response": "secret output"]
        let value = try CodexHookEvent(input: JSONSerialization.data(withJSONObject: input))
        let encoded = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        XCTAssertEqual(value.project, "project")
        for secret in ["secret", "private", "transcript", "tool_input", "prompt"] { XCTAssertFalse(encoded.contains(secret)) }
        XCTAssertEqual(value.activity, .attention)
    }
    func testRejectsUnsupportedSubagentAndOversizedEvents() throws {
        XCTAssertThrowsError(try event("SubagentStop"))
        for key in ["agent_id", "subagent_id"] {
            XCTAssertThrowsError(try CodexHookEvent(input: JSONSerialization.data(withJSONObject:
                ["session_id": id, "hook_event_name": "Stop", key: "child"])))
        }
        XCTAssertThrowsError(try CodexHookEvent(input: Data(repeating: 32, count: 1_048_577)))
        XCTAssertThrowsError(try CodexHookEvent(input: Data("{}".utf8)))
    }
    func testStatusesAreCoarseAndExpire() throws {
        XCTAssertEqual(try event("Stop").activity, .finished)
        XCTAssertEqual(try event("PostToolUse").activity, .working)
        XCTAssertEqual(try event("Interrupt").activity, .idle)
        let state = CodexSessionStatus(try event("UserPromptSubmit"))
        XCTAssertEqual(state.activity(now: Date(timeIntervalSince1970: 101)), .working)
        XCTAssertEqual(state.activity(now: Date(timeIntervalSince1970: 1901)), .unknown)
    }
    func testOutOfOrderAndPreviousTurnStopsCannotFinishCurrentTurn() throws {
        var state = CodexSessionStatus(try event("UserPromptSubmit", turn: "new", time: 200))
        state.receive(try event("Stop", turn: "new", time: 100))
        state.receive(try event("Stop", turn: "old", time: 201))
        XCTAssertEqual(state.latest.event, "UserPromptSubmit")
        state.receive(try event("Stop", turn: "new", time: 202))
        XCTAssertEqual(state.latest.activity, .finished)
    }
    func testOldOrFutureQueueEventsAreRejected() throws {
        let now = Date(timeIntervalSince1970: 100)
        XCTAssertTrue(try event("Stop", time: 99).validate(now: now))
        XCTAssertFalse(try event("Stop", time: -201).validate(now: now))
        XCTAssertFalse(try event("Stop", time: 106).validate(now: now))
    }
    func testSlotLinksOnlyAllowCanonicalLocalChatTargets() {
        XCTAssertEqual(CodexSlot.threadID(from: "codex://threads/\(id)"), id)
        XCTAssertEqual(CodexSlot.threadID(from: id.uppercased()), id)
        for bad in ["https://example.com/\(id)", "codex://threads/new", "codex://threads/\(id)?prompt=hello",
                    "codex://threads/\(id)/other", "codex://user@threads/\(id)", "file:///tmp/test"] {
            XCTAssertNil(CodexSlot.threadID(from: bad))
        }
    }
    func testSettingsAndDuplicateAssignments() throws {
        var value = CodexSettings()
        XCTAssertFalse(value.enabled); XCTAssertFalse(value.lighting)
        try value.validate()
        value.slots[0].threadID = id; value.slots[1].threadID = id.uppercased()
        XCTAssertThrowsError(try value.validate())
        value.slots.removeLast()
        XCTAssertThrowsError(try value.validate())
    }
    func testSharedColumnPriorityAndWhiteBackground() {
        XCTAssertEqual(CodexActivity.priority([.finished, .working, .attention]), .attention)
        XCTAssertEqual(CodexActivity.priority([.finished, .working]), .working)
        XCTAssertEqual(CodexActivity.priority([.unknown]), .unknown)
        let colors = MacroStatusFrame.colors(CodexActivity.attention.color)
        XCTAssertEqual(colors.count, 19)
        XCTAssertEqual(colors[0], CodexActivity.attention.color)
        XCTAssertTrue(colors.dropFirst().allSatisfy { $0 == DialColor(red: 160, green: 160, blue: 160) })
    }
    func testHookInstallMergeIsIdempotentAndRemovalKeepsForeignHandlers() throws {
        let foreign: [String: Any] = ["description": "keep me", "extra": ["value": 42],
            "hooks": ["Stop": [["hooks": [["type": "command", "command": "echo foreign"]]]],
                      "SessionStart": [["matcher": "startup", "hooks": []]],
                      "Unrelated": [["keep": true]]]]
        let original = try JSONSerialization.data(withJSONObject: foreign)
        let installed = try CodexHookConfiguration.updating(original, executable: "/a b/c'd", install: true)
        let twice = try CodexHookConfiguration.updating(installed, executable: "/a b/c'd", install: true)
        XCTAssertEqual(installed, twice)
        let removed = try CodexHookConfiguration.updating(installed, executable: "/a b/c'd", install: false)
        let final = try JSONSerialization.jsonObject(with: removed) as! NSDictionary
        XCTAssertEqual(final, foreign as NSDictionary)
        XCTAssertEqual(CodexHookConfiguration.command(executable: "/a b/c'd"), "'/a b/c'\\''d' --ergo-codex-hook-v1")
    }
    func testMalformedHookConfigIsNotReplaced() {
        for text in ["[]", "oops", "{\"hooks\":true}", "{\"hooks\":{\"Stop\":true}}"] {
            XCTAssertThrowsError(try CodexHookConfiguration.updating(Data(text.utf8), executable: "/sender", install: true))
        }
    }
    func testUnknownOrCustomLightingCannotBecomeRestoreSnapshot() throws {
        let custom = try KeyboardEffect(payload: Data([8,0,0,0]))
        XCTAssertThrowsError(try SavedMacroLighting(region: 5, effect: custom))
        XCTAssertThrowsError(try SavedMacroLighting(region: 0, effect: KeyboardEffect(kind: .wave)))
        let saved = try SavedMacroLighting(region: 5, effect: KeyboardEffect(kind: .wave))
        XCTAssertEqual(try saved.validatedEffect().kind, .wave)
    }
}
