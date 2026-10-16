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

public struct CodexSettings: Codable, Equatable {
    public var enabled = false
    public var lighting = false
    public var slots = (1...5).map(CodexSlot.init)
    public init() {}
    public func validate() throws {
        guard slots.map(\.id) == Array(1...5), slots.allSatisfy({
            $0.name.count <= 80 && ($0.threadID == nil || UUID(uuidString: $0.threadID!) != nil)
        }) else { throw CodexIntegrationError.invalidSettings }
        let assigned = slots.compactMap(\.threadID).map { $0.lowercased() }
        guard Set(assigned).count == assigned.count else { throw CodexIntegrationError.duplicateSlot }
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
