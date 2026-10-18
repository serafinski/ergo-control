import XCTest
@testable import ErgoCore

final class ClaudeIntegrationTests: XCTestCase {
    let id = "11111111-1111-4111-8111-111111111111"
    let prompt = "22222222-2222-4222-8222-222222222222"
    func event(_ name: String, extra: [String: Any] = [:], time: Double = 100) throws -> CodexHookEvent {
        var fields: [String: Any] = ["hook_event_name": name, "session_id": id, "prompt_id": prompt,
                                    "cwd": "/private/example/project"]
        fields.merge(extra) { _, b in b }
        return try ClaudeHookEvent.parse(JSONSerialization.data(withJSONObject: fields), time: Date(timeIntervalSince1970: time))
    }
    func testLifecycleMappingAndQuestions() throws {
        for name in ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure"] {
            XCTAssertEqual(try event(name).activity, .working)
        }
        XCTAssertEqual(try event("PermissionRequest").activity, .attention)
        XCTAssertEqual(try event("PreToolUse", extra: ["tool_name": "AskUserQuestion"]).activity, .attention)
        XCTAssertEqual(try event("Stop").activity, .finished)
        for name in ["StopFailure", "SessionStart", "SessionEnd"] { XCTAssertEqual(try event(name).activity, .idle) }
        XCTAssertEqual(try event("Stop").turnID, prompt)
    }
    func testNotificationsAreFilteredAndIdleCannotDismissApproval() throws {
        XCTAssertThrowsError(try event("Notification", extra: ["notification_type": "auth_success"]))
        let idle = try event("Notification", extra: ["notification_type": "idle_prompt"], time: 110)
        XCTAssertTrue(idle.validate(now: Date(timeIntervalSince1970: 110)))
        var state = CodexSessionStatus(try event("UserPromptSubmit"))
        state.receive(idle); XCTAssertEqual(state.latest.activity, .idle)
        state = CodexSessionStatus(try event("Notification", extra: ["notification_type": "permission_prompt"]))
        state.receive(idle); XCTAssertEqual(state.latest.activity, .attention)
    }
    func testPreviousPromptCompletionAndIdleCannotEndNewWork() throws {
        let start = try event("UserPromptSubmit", extra: ["prompt_id": UUID().uuidString])
        var state = CodexSessionStatus(start)
        state.receive(try event("Stop", time: 101))
        state.receive(try event("Notification", extra: ["notification_type": "idle_prompt"], time: 102))
        XCTAssertEqual(state.latest, start)
    }
    func testPayloadPrivacySubagentsAndLimits() throws {
        let value = try event("PostToolUse", extra: ["prompt": "secret prompt", "transcript_path": "/secret/transcript",
            "tool_input": ["command": "private command"], "tool_response": "private output", "last_assistant_message": "secret answer"])
        let data = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        XCTAssertEqual(value.project, "project")
        for word in ["secret", "private", "transcript", "tool_input", "tool_response", "assistant_message"] {
            XCTAssertFalse(data.contains(word))
        }
        for name in ["SubagentStop", "SubagentStart", "Interrupt", "Unknown"] { XCTAssertThrowsError(try event(name)) }
        for key in ["agent_id", "subagent_id"] { XCTAssertThrowsError(try event("Stop", extra: [key: "child"])) }
        XCTAssertThrowsError(try event("Stop", extra: ["session_id": "invalid"]))
        XCTAssertThrowsError(try ClaudeHookEvent.parse(Data(repeating: 32, count: 1_048_577)))
    }
    func testOnlyExistingDesktopTargetsAreAllowed() {
        let desktop = "local_" + id
        let provider = ChatProvider.claude
        XCTAssertEqual(provider.sessionID(from: desktop), desktop)
        XCTAssertEqual(provider.sessionID(from: "claude://code/continue?session=\(desktop)&source=spotlight"), desktop)
        XCTAssertEqual(provider.url(for: desktop)?.absoluteString, "claude://code/continue?session=\(desktop)")
        for bad in [id, "local_../file", "session_remote", "claude://code/new", "claude://code/continue?session=last",
                    "claude://code/continue?session=\(desktop)&q=send", "claude://code/continue?session=\(desktop)&session=\(desktop)",
                    "claude://code/continue?session=\(desktop)#fragment", "claude://user@code/continue?session=\(desktop)",
                    "https://claude.ai/code/\(desktop)", "codex://threads/\(id)"] {
            XCTAssertNil(provider.sessionID(from: bad), bad)
        }
        XCTAssertNil(ChatProvider.codex.sessionID(from: desktop))
    }
    func testClaudeSettingsAndCodexMigrationAreSeparate() throws {
        var settings = CodexSettings()
        settings.slots[0].threadID = "local_" + id
        try settings.validate(provider: .claude)
        XCTAssertThrowsError(try settings.validate())
        let legacy = try JSONDecoder().decode(CodexSettings.self, from: Data("""
        {"enabled":true,"lighting":true,"slots":[{"id":1,"name":"A","threadID":"\(id)"},{"id":2,"name":"B"},{"id":3,"name":"C"},{"id":4,"name":"D"},{"id":5,"name":"E"}]}
        """.utf8))
        try legacy.validate()
        XCTAssertNil(legacy.catalogPath)
        XCTAssertEqual(legacy.slots[0].threadID, id)
    }
    func testClaudeHookMergePreservesPermissionsAndForeignMatchers() throws {
        let foreign: [String: Any] = ["permissions": ["allow": ["Read"]], "env": ["EXAMPLE": "preserve"],
            "hooks": ["Notification": [["matcher": "auth_success", "hooks": [["type": "command", "command": "foreign"]]]],
                      "Stop": [["hooks": [["type": "command", "command": "foreign-stop"]]]]]]
        let original = try JSONSerialization.data(withJSONObject: foreign)
        let installed = try CodexHookConfiguration.updating(original, executable: "/a b/sender", install: true, provider: .claude)
        XCTAssertEqual(installed, try CodexHookConfiguration.updating(installed, executable: "/a b/sender", install: true, provider: .claude))
        let root = try JSONSerialization.jsonObject(with: installed) as! [String: Any]
        let hooks = root["hooks"] as! [String: Any]
        XCTAssertNil(hooks["Interrupt"])
        XCTAssertNotNil(hooks["StopFailure"])
        let notifications = hooks["Notification"] as! [[String: Any]]
        XCTAssertEqual(notifications.last?["matcher"] as? String, "^(permission_prompt|idle_prompt)$")
        let removed = try CodexHookConfiguration.updating(installed, executable: "/a b/sender", install: false, provider: .claude)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: removed) as! NSDictionary, foreign as NSDictionary)
    }
}
