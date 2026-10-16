import Foundation

public enum CodexActivity: String, Codable, CaseIterable {
    case unknown, idle, working, attention, finished
    public var label: String {
        switch self {
        case .unknown: return "No recent status"
        case .idle: return "Idle"
        case .working: return "Working"
        case .attention: return "Approval requested"
        case .finished: return "Turn ended"
        }
    }
    public var color: DialColor {
        switch self {
        case .unknown: return DialColor(red: 50, green: 50, blue: 50)
        case .idle: return DialColor(red: 140, green: 140, blue: 140)
        case .working: return DialColor(red: 0, green: 90, blue: 255)
        case .attention: return DialColor(red: 255, green: 140, blue: 0)
        case .finished: return DialColor(red: 0, green: 210, blue: 65)
        }
    }
    public static func priority(_ states: [Self]) -> Self {
        [.attention, .working, .finished, .idle].first(where: states.contains) ?? .unknown
    }
}

/// A bounded visual test; it never creates hook events or changes chat status.
public enum CodexLightingTestStage: Int, CaseIterable {
    case working, attention, finished, idle, restore
    public static let duration: TimeInterval = 20
    public static func at(elapsed: TimeInterval) -> Self? {
        guard elapsed.isFinite, elapsed >= 0, elapsed < duration else { return nil }
        return Self(rawValue: Int(elapsed / 4))
    }
    public var activity: CodexActivity? {
        switch self {
        case .working: return .working
        case .attention: return .attention
        case .finished: return .finished
        case .idle: return .idle
        case .restore: return nil
        }
    }
    public var label: String {
        switch self {
        case .working: return "Working · blue"
        case .attention: return "Approval requested · amber"
        case .finished: return "Turn ended · green"
        case .idle: return "Idle · white"
        case .restore: return "Restoring previous keyboard effect"
        }
    }
}

/// The only fields retained from a hook. Prompt, tool arguments/results, model,
/// transcript path, and full working directory never enter the event queue.
public struct CodexHookEvent: Codable, Equatable {
    public let sessionID: String
    public let turnID: String?
    public let event: String
    public let project: String
    public let time: Date
    public static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                                "PermissionRequest", "Stop", "Interrupt", "SessionEnd"]
    public init(input: Data, time: Date = Date()) throws {
        guard input.count <= 1_048_576,
              let json = try JSONSerialization.jsonObject(with: input) as? [String: Any],
              let id = json["session_id"] as? String, UUID(uuidString: id) != nil,
              let event = json["hook_event_name"] as? String, Self.events.contains(event),
              json["agent_id"] == nil, json["subagent_id"] == nil else { throw CodexIntegrationError.invalidEvent }
        sessionID = id.lowercased(); self.event = event; self.time = time
        turnID = (json["turn_id"] as? String).flatMap { $0.count <= 128 ? $0 : nil }
        let name = URL(fileURLWithPath: json["cwd"] as? String ?? "/").lastPathComponent
        project = String(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(80))
    }
    public var activity: CodexActivity {
        switch event {
        case "UserPromptSubmit", "PreToolUse", "PostToolUse": return .working
        case "PermissionRequest": return .attention
        case "Stop": return .finished
        default: return .idle
        }
    }
    public func validate(now: Date) -> Bool {
        UUID(uuidString: sessionID) != nil && Self.events.contains(event) && project.count <= 80
            && (turnID?.count ?? 0) <= 128 && time <= now.addingTimeInterval(5)
            && time >= now.addingTimeInterval(-300)
    }
}

public struct CodexSlot: Codable, Equatable, Identifiable {
    public let id: Int
    public var name: String
    public var threadID: String?
    public init(_ id: Int) { self.id = id; name = "Chat \(id)" }
    public var url: URL? { threadID.flatMap { UUID(uuidString: $0) != nil ? URL(string: "codex://threads/\($0)") : nil } }
    public static func threadID(from link: String) -> String? {
        let value = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = UUID(uuidString: value) { return id.uuidString.lowercased() }
        guard let url = URLComponents(string: value), url.scheme == "codex", url.host == "threads",
              url.query == nil, url.fragment == nil, url.user == nil, url.password == nil, url.port == nil else { return nil }
        let path = url.path.split(separator: "/")
        guard path.count == 1, let id = UUID(uuidString: String(path[0])) else { return nil }
        return id.uuidString.lowercased()
    }
}

public enum CodexSelectionMode: String, Codable, CaseIterable, Identifiable {
    case recent, pinned, fixed
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .recent: return "Recent Codex chats"
        case .pinned: return "Pinned Codex chats"
        case .fixed: return "Fixed Codex assignments"
        }
    }
}

public struct CodexSettings: Codable, Equatable {
    public var enabled = false
    public var lighting = false
    public var selection: CodexSelectionMode = .recent
    public var useUnmappedMacroKeys = true
    public var slots = (1...5).map(CodexSlot.init)
    public init() {}
    private enum CodingKeys: String, CodingKey { case enabled, lighting, slots, selection, useUnmappedMacroKeys }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        lighting = try c.decode(Bool.self, forKey: .lighting)
        slots = try c.decode([CodexSlot].self, forKey: .slots)
        selection = try c.decodeIfPresent(CodexSelectionMode.self, forKey: .selection) ?? .recent
        useUnmappedMacroKeys = try c.decodeIfPresent(Bool.self, forKey: .useUnmappedMacroKeys) ?? true
    }
    public func validate() throws {
        guard slots.map(\.id) == Array(1...5), slots.allSatisfy({
            $0.name.count <= 80 && ($0.threadID == nil || UUID(uuidString: $0.threadID!) != nil)
        }) else { throw CodexIntegrationError.invalidSettings }
        let assigned = slots.compactMap(\.threadID).map { $0.lowercased() }
        guard Set(assigned).count == assigned.count else { throw CodexIntegrationError.duplicateSlot }
    }
}

/// Decode only metadata used by the selector. The server's preview, turns,
/// full paths, and all other response fields are deliberately ignored.
public struct CodexThreadSummary: Decodable, Equatable {
    public let id: String
    public let name: String
    private enum CodingKeys: String, CodingKey { case id, name, ephemeral, parentThreadId }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        guard UUID(uuidString: id) != nil,
              try c.decodeIfPresent(Bool.self, forKey: .ephemeral) != true,
              try c.decodeIfPresent(String.self, forKey: .parentThreadId) == nil else { throw CodexIntegrationError.invalidEvent }
        self.id = id.lowercased()
        let name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled chat"
        self.name = String(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(160))
    }
    public static func list(from data: Data) throws -> (threads: [Self], cursor: String?) {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["data"] as? [[String: Any]], rows.count <= 100 else { throw CodexIntegrationError.invalidEvent }
        let decoder = JSONDecoder()
        let threads = rows.compactMap { row -> Self? in
            guard let raw = try? JSONSerialization.data(withJSONObject: row) else { return nil }
            return try? decoder.decode(Self.self, from: raw)
        }
        return (threads, root["nextCursor"] as? String)
    }
    public static func slots(_ threads: [Self]) -> [CodexSlot] {
        var seen = Set<String>()
        let unique = threads.filter { seen.insert($0.id).inserted }.prefix(5)
        var slots = (1...5).map(CodexSlot.init)
        for (index, chat) in unique.enumerated() { slots[index].threadID = chat.id; slots[index].name = chat.name }
        return slots
    }
}

/// This adapter can initialize and list metadata only. No thread/turn start,
/// resume, content read, approval response, or mutation method is available.
public enum CodexHistoryRequest {
    case initialize, initialized, sections, recent(String?), pinned(section: String, cursor: String?)
    public func data(id: Int) throws -> Data {
        var object: [String: Any]
        switch self {
        case .initialize:
            object = ["id": id, "method": "initialize", "params": ["clientInfo": ["name": "ergo_control_metadata", "version": "0.4.0"]]]
        case .initialized: object = ["method": "initialized", "params": [:]]
        case .sections: object = ["id": id, "method": "threadSection/list", "params": ["limit": 100]]
        case .recent(let cursor), .pinned(_, let cursor):
            var params: [String: Any] = ["limit": 20, "archived": false, "useStateDbOnly": true,
                                       "sourceKinds": ["cli", "vscode", "appServer", "unknown"]]
            if let cursor { params["cursor"] = cursor }
            if case .pinned(let section, _) = self {
                params["sectionId"] = section; params["sortKey"] = "section_position"; params["sortDirection"] = "asc"
            } else { params["sortKey"] = "recency_at"; params["sortDirection"] = "desc" }
            object = ["id": id, "method": "thread/list", "params": params]
        }
        return try JSONSerialization.data(withJSONObject: object) + Data([10])
    }
}

public struct CodexSessionStatus {
    public private(set) var latest: CodexHookEvent
    public init(_ event: CodexHookEvent) { latest = event }
    public mutating func receive(_ event: CodexHookEvent) {
        guard event.sessionID == latest.sessionID, event.time > latest.time else { return }
        // A delayed terminal event from an earlier turn must not finish a newer one.
        if ["Stop", "Interrupt"].contains(event.event), let turn = event.turnID,
           let current = latest.turnID, turn != current { return }
        latest = event
    }
    public func activity(now: Date) -> CodexActivity {
        now.timeIntervalSince(latest.time) < 1800 ? latest.activity : .unknown
    }
}

public enum CodexIntegrationError: LocalizedError {
    case invalidEvent, invalidSettings, duplicateSlot, message(String)
    public var errorDescription: String? {
        switch self {
        case .invalidEvent: return "Unsupported Codex event."
        case .invalidSettings: return "Invalid Codex slot settings; the saved file was preserved."
        case .duplicateSlot: return "This chat already has a slot. Choose a different chat."
        case .message(let message): return message
        }
    }
}

public enum CodexHookConfiguration {
    public static func command(executable: String) -> String {
        "'" + executable.replacingOccurrences(of: "'", with: "'\\''") + "' --ergo-codex-hook-v1"
    }
    /// Merge only our exact command; preserve every foreign field and handler.
    public static func updating(_ data: Data?, executable: String, install: Bool) throws -> Data {
        var root: [String: Any] = [:]
        if let data {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CodexIntegrationError.message("Existing hooks.json is not an object; it was preserved.")
            }
            root = object
        }
        if let value = root["hooks"], !(value is [String: Any]) {
            throw CodexIntegrationError.message("Existing hooks configuration was preserved because its format is unfamiliar.")
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let command = command(executable: executable)
        for event in CodexHookEvent.events {
            if let value = hooks[event], !(value is [[String: Any]]) { throw CodexIntegrationError.invalidSettings }
            var entries: [[String: Any]] = []
            for var entry in hooks[event] as? [[String: Any]] ?? [] {
                guard let handlers = entry["hooks"] as? [[String: Any]] else { throw CodexIntegrationError.invalidSettings }
                let remaining = handlers.filter { !($0["type"] as? String == "command" && $0["command"] as? String == command) }
                if remaining.count == handlers.count { entries.append(entry); continue }
                if !remaining.isEmpty { entry["hooks"] = remaining; entries.append(entry) }
            }
            if install { entries.append(["hooks": [["type": "command", "command": command, "timeout": 1]]]) }
            if entries.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = entries }
        }
        root["hooks"] = hooks
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
}
