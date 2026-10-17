import Foundation

/// Claude's payload is reduced before it ever reaches disk. Desktop session
/// IDs are deliberately not inferred from the hook's engine session UUID.
public enum ClaudeHookEvent {
    public static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                                "PostToolUseFailure", "PermissionRequest", "Notification", "Stop", "StopFailure", "SessionEnd"]
    public static func parse(_ input: Data, time: Date = Date()) throws -> CodexHookEvent {
        guard input.count <= 1_048_576,
              let json = try JSONSerialization.jsonObject(with: input) as? [String: Any],
              let id = json["session_id"] as? String, UUID(uuidString: id) != nil,
              let name = json["hook_event_name"] as? String, events.contains(name),
              json["agent_id"] == nil, json["subagent_id"] == nil else { throw CodexIntegrationError.invalidEvent }
        let event: String
        switch name {
        case "Notification":
            switch json["notification_type"] as? String {
            case "permission_prompt": event = "PermissionRequest"
            case "idle_prompt": event = "IdleNotification"
            default: throw CodexIntegrationError.invalidEvent
            }
        case "PreToolUse" where json["tool_name"] as? String == "AskUserQuestion": event = "PermissionRequest"
        case "PostToolUseFailure": event = "PostToolUse"
        case "StopFailure": event = "Interrupt" // An API failure must not signal successful completion.
        default: event = name
        }
        let project = URL(fileURLWithPath: json["cwd"] as? String ?? "/").lastPathComponent
        return CodexHookEvent(sessionID: id.lowercased(),
                              turnID: (json["prompt_id"] as? String).flatMap { UUID(uuidString: $0)?.uuidString.lowercased() },
                              event: event,
                              project: String(project.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(80)),
                              time: time)
    }
}

/// A narrow projection of Claude Desktop's local catalog, not its transcript.
/// The catalog and continue link are version-sensitive desktop interfaces.
public struct ClaudeThreadSummary: Decodable, Equatable {
    public let id: String
    public let hookID: String?
    public let title: String
    public let lastActivity: Double
    public let starred: Bool
    private enum CodingKeys: String, CodingKey {
        case sessionId, cliSessionId, title, lastActivityAt, createdAt, isStarred, isArchived, parentSessionId, sessionType
        case remoteTarget, sshConfig
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .sessionId)
        guard ChatProvider.isClaudeDesktopID(id),
              try c.decodeIfPresent(Bool.self, forKey: .isArchived) != true,
              try c.decodeIfPresent(String.self, forKey: .parentSessionId) == nil,
              try (!c.contains(.remoteTarget) || c.decodeNil(forKey: .remoteTarget)),
              try (!c.contains(.sshConfig) || c.decodeNil(forKey: .sshConfig)) else { throw CodexIntegrationError.invalidEvent }
        if let type = try c.decodeIfPresent(String.self, forKey: .sessionType), type != "code" {
            throw CodexIntegrationError.invalidEvent
        }
        self.id = id.lowercased()
        hookID = try c.decodeIfPresent(String.self, forKey: .cliSessionId).flatMap { UUID(uuidString: $0)?.uuidString.lowercased() }
        let name = try c.decodeIfPresent(String.self, forKey: .title) ?? "Untitled chat"
        title = String(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(160))
        lastActivity = try c.decodeIfPresent(Double.self, forKey: .lastActivityAt)
            ?? c.decodeIfPresent(Double.self, forKey: .createdAt) ?? 0
        guard lastActivity.isFinite, lastActivity >= 0 else { throw CodexIntegrationError.invalidEvent }
        starred = try c.decodeIfPresent(Bool.self, forKey: .isStarred) ?? false
    }
    public static func slots(_ records: [Self], starredOnly: Bool = false) -> [CodexSlot] {
        var seen = Set<String>()
        let rows = records.filter { (!starredOnly || $0.starred) && seen.insert($0.id).inserted }
            .sorted { $0.lastActivity == $1.lastActivity ? $0.id < $1.id : $0.lastActivity > $1.lastActivity }.prefix(5)
        var slots = (1...5).map(CodexSlot.init)
        for (index, row) in rows.enumerated() { slots[index].threadID = row.id; slots[index].name = row.title }
        return slots
    }
}
