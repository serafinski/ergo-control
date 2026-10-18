import Foundation

public enum ChatProvider: String, Codable, CaseIterable, Identifiable {
    case codex, claude
    public var id: String { rawValue }
    public var name: String { self == .codex ? "Codex" : "Claude Code" }
    public var directory: String { self == .codex ? "Codex" : "Claude" }
    public var executable: String { self == .codex ? "ErgoCodexHook" : "ErgoClaudeHook" }
    public var hookFlag: String { self == .codex ? "--ergo-codex-hook-v1" : "--ergo-claude-hook-v1" }
    public var bundleID: String { self == .codex ? "com.openai.codex" : "com.anthropic.claudefordesktop" }
    public var action: ActionKind { self == .codex ? .codexChat : .claudeChat }

    public func sessionID(from value: String) -> String? {
        if self == .codex { return CodexSlot.threadID(from: value) }
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.isClaudeDesktopID(value) { return value.lowercased() }
        guard let url = URLComponents(string: value), url.scheme == "claude", url.host == "code",
              url.path == "/continue", url.user == nil, url.password == nil, url.port == nil,
              url.fragment == nil, let items = url.queryItems,
              items.allSatisfy({ $0.name == "session" || $0.name == "source" }),
              items.filter({ $0.name == "session" }).count == 1,
              let id = items.first(where: { $0.name == "session" })?.value,
              Self.isClaudeDesktopID(id) else { return nil }
        return id.lowercased()
    }
    public static func isClaudeDesktopID(_ value: String) -> Bool {
        value.hasPrefix("local_") && value.count == 42 && UUID(uuidString: String(value.dropFirst(6))) != nil
    }
    public func url(for id: String?) -> URL? {
        guard let id, sessionID(from: id) == id.lowercased() else { return nil }
        if self == .codex { return URL(string: "codex://threads/\(id)") }
        var url = URLComponents(); url.scheme = "claude"; url.host = "code"; url.path = "/continue"
        url.queryItems = [URLQueryItem(name: "session", value: id)]
        return url.url
    }
}
