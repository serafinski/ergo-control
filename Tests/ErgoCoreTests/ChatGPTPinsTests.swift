import XCTest
@testable import ErgoCore

final class ChatGPTPinsTests: XCTestCase {
    private func snapshot(_ pins: [[String: Any]], accounts: Int = 1, version: String = "v2") throws -> Data {
        let entries = Dictionary(uniqueKeysWithValues: (0..<accounts).map {
            ("account-\($0)", ["pinnedConversations": pins])
        })
        return try JSONSerialization.data(withJSONObject: ["electron-persisted-atom-state": ["chatgpt-sidebar-state-\(version)": entries]])
    }
    private func pin(_ id: String, _ title: String = "Title") -> [String: Any] {
        ["conversation": ["id": id, "title": title, "titlePrompt": ["prompt": "ignored private content"]], "pinnedAt": "ignored"]
    }
    func testPinsPreserveOrderDeduplicateAndOnlyKeepFiveMetadataRecords() throws {
        let ids = (0..<7).map { _ in UUID().uuidString.lowercased() }
        let data = try snapshot([pin("invalid"), pin(ids[0], "A\nB"), pin(ids[0], "duplicate")]
                                + ids.dropFirst().map { pin($0, String(repeating: "x", count: 200)) })
        let slots = try ChatGPTPins.slots(from: data)
        XCTAssertEqual(slots.map(\.id), Array(1...5))
        XCTAssertEqual(slots.compactMap(\.threadID), Array(ids.prefix(5)))
        XCTAssertEqual(slots[0].name, "AB")
        XCTAssertEqual(slots[1].name.count, 80)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(slots), as: UTF8.self).contains("private content"))
    }
    func testMissingOldMalformedOrMultipleAccountsNeverBecomeWrongTargets() throws {
        XCTAssertThrowsError(try ChatGPTPins.slots(from: snapshot([pin(UUID().uuidString)], version: "v1")))
        XCTAssertThrowsError(try ChatGPTPins.slots(from: snapshot([], accounts: 2)))
        XCTAssertThrowsError(try ChatGPTPins.slots(from: snapshot([], accounts: 0)))
        XCTAssertThrowsError(try ChatGPTPins.slots(from: Data("{}".utf8)))
        XCTAssertThrowsError(try ChatGPTPins.slots(from: Data(repeating: 32, count: ChatGPTPins.maximumBytes + 1)))
        XCTAssertThrowsError(try ChatGPTPins.slots(from: snapshot((0..<101).map { _ in pin(UUID().uuidString) })))
        XCTAssertTrue(try ChatGPTPins.slots(from: snapshot([])).allSatisfy { $0.threadID == nil })
    }
    func testFileReaderIsReadOnlyAndReflectsNewPins() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let first = try snapshot([pin(UUID().uuidString)])
        try first.write(to: url)
        let a = try ChatGPTPins.read(from: url)
        XCTAssertEqual(try Data(contentsOf: url), first)
        let second = try snapshot([pin(UUID().uuidString)])
        try second.write(to: url)
        XCTAssertNotEqual(try ChatGPTPins.read(from: url), a)
        XCTAssertEqual(try Data(contentsOf: url), second)
    }
    func testSourceLinksAreStrictAndNeverConfuseCodexWithChatGPT() {
        let id = UUID().uuidString.lowercased()
        let link = "https://chatgpt.com/c/\(id)"
        XCTAssertEqual(ChatSource.chatgpt.threadID(from: link), id)
        XCTAssertEqual(ChatSource.chatgpt.threadID(from: id.uppercased()), id)
        for bad in ["http://chatgpt.com/c/\(id)", "https://chatgpt.com.evil/c/\(id)",
                    "https://user@chatgpt.com/c/\(id)", link + "?token=secret", link + "#fragment",
                    "https://chatgpt.com:443/c/\(id)", link + "/", "https://chatgpt.com//c/\(id)",
                    "https://chatgpt.com/share/\(id)", "codex://threads/\(id)", "https://chatgpt.com/c/not-an-id"] {
            XCTAssertNil(ChatSource.chatgpt.threadID(from: bad), bad)
        }
        XCTAssertNil(ChatSource.codex.threadID(from: link))
        var slot = CodexSlot(1); slot.threadID = id
        XCTAssertEqual(ChatSource.chatgpt.url(for: slot)?.absoluteString, link)
        XCTAssertEqual(ChatSource.codex.url(for: slot), slot.url)
    }
    func testLegacySettingsAndActionValuesRemainCompatible() throws {
        let legacy = CodexSettings()
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
        for key in ["source", "chatgptSelection", "chatgptSlots"] { json.removeValue(forKey: key) }
        let restored = try JSONDecoder().decode(CodexSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.source, .codex)
        XCTAssertEqual(restored.selection, .recent)
        XCTAssertEqual(restored.chatgptSelection, .pinned)
        XCTAssertEqual(restored.slots, legacy.slots)
        XCTAssertEqual(ChatSource.chatgpt.selections, [.pinned, .fixed])
        var invalid = restored; invalid.chatgptSelection = .recent
        XCTAssertThrowsError(try invalid.validate())
        let action = try JSONDecoder().decode(MappingAction.self, from: Data(#"{"kind":"Open Codex chat slot","value":"1"}"#.utf8))
        XCTAssertEqual(action, MappingAction(.codexChat, "1"))
        XCTAssertEqual(action.kind.label, "Open chat slot")
    }
}
