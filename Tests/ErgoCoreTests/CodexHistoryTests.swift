import XCTest
import ErgoCore

final class CodexHistoryTests: XCTestCase {
    let id = "01a13698-ddb7-7381-9a6a-8e9e47173a07"
    func testRecentIsTheDefaultIncludingUpgradeFromFixedOnlyVersion() throws {
        XCTAssertEqual(CodexSettings().selection, .recent)
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CodexSettings())) as! [String: Any]
        old.removeValue(forKey: "selection"); old.removeValue(forKey: "useUnmappedMacroKeys")
        var slots = old["slots"] as! [[String: Any]]; slots[0]["threadID"] = id; old["slots"] = slots
        let saved = try JSONDecoder().decode(CodexSettings.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(saved.selection, .recent)
        XCTAssertTrue(saved.useUnmappedMacroKeys)
        XCTAssertEqual(saved.slots[0].threadID, id, "Keep fixed assignments available when selecting Fixed later")
    }
    func testMetadataParsingIgnoresContentAndInvalidSubagentOrEphemeralRows() throws {
        let rows: [[String: Any]] = [
            ["id": id, "name": "Actual title", "preview": "secret prompt", "turns": ["secret transcript"]],
            ["id": id, "name": "duplicate"],
            ["id": UUID().uuidString, "parentThreadId": id],
            ["id": UUID().uuidString, "ephemeral": true],
            ["id": "not-a-local-chat"],
            ["id": UUID().uuidString]]
        let parsed = try CodexThreadSummary.list(from: JSONSerialization.data(withJSONObject: ["data": rows, "nextCursor": "next-page"]))
        XCTAssertEqual(parsed.cursor, "next-page")
        let slots = CodexThreadSummary.slots(parsed.threads)
        XCTAssertEqual(slots.count, 5)
        XCTAssertEqual(slots[0].threadID, id)
        XCTAssertEqual(slots[0].name, "Actual title")
        XCTAssertEqual(slots[1].name, "Untitled chat")
        XCTAssertNil(slots[2].threadID)
    }
    func testMetadataKeepsServerOrderingAndBoundsFiveSlots() throws {
        let rows = (1...8).map { ["id": String(format: "01a13698-ddb7-7381-9a6a-%012d", $0), "name": "Chat \($0)"] }
        let parsed = try CodexThreadSummary.list(from: JSONSerialization.data(withJSONObject: ["data": rows]))
        XCTAssertEqual(CodexThreadSummary.slots(parsed.threads).map(\.name), (1...5).map { "Chat \($0)" })
        XCTAssertEqual(CodexThreadSummary.slots(Array(parsed.threads.reversed())).map(\.name), (4...8).reversed().map { "Chat \($0)" })
    }
    func testMetadataRequestsCannotStartResumeReadContentOrChangeChats() throws {
        let requests: [CodexHistoryRequest] = [.initialize, .initialized, .sections, .recent(nil), .recent("cursor"), .pinned(section: "pins", cursor: nil)]
        let allowed = Set(["initialize", "initialized", "thread/list", "threadSection/list"])
        for request in requests {
            let d = try JSONSerialization.jsonObject(with: request.data(id: 42)) as! [String: Any]
            XCTAssertTrue(allowed.contains(d["method"] as! String))
            if d["method"] as? String == "thread/list" {
                let p = d["params"] as! [String: Any]
                XCTAssertEqual(p["useStateDbOnly"] as? Bool, true, "Avoid scanning/repairing transcript files")
                XCTAssertEqual(p["archived"] as? Bool, false)
            }
        }
        let pinned = try JSONSerialization.jsonObject(with: CodexHistoryRequest.pinned(section: "pins", cursor: "next").data(id: 4)) as! [String: Any]
        let p = pinned["params"] as! [String: Any]
        XCTAssertEqual(p["sectionId"] as? String, "pins")
        XCTAssertEqual(p["sortKey"] as? String, "section_position")
        XCTAssertEqual(p["sortDirection"] as? String, "asc")
        XCTAssertEqual(p["cursor"] as? String, "next")
        XCTAssertNil(p["isPinned"], "This client version silently ignores isPinned; use its actual section API")
    }
}
