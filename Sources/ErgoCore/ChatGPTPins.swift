import Foundation

/// A read-only adapter for saved sidebar metadata, not a ChatGPT API.
/// Decode only pin IDs/titles; never retain prompts, credentials, or messages.
public enum ChatGPTPins {
    public static var defaultURL: URL {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        return home.appendingPathComponent(".codex-global-state.json")
    }
    public static let maximumBytes = 16 * 1024 * 1024
    private struct Root: Decodable {
        let state: State
        enum CodingKeys: String, CodingKey { case state = "electron-persisted-atom-state" }
    }
    private struct State: Decodable {
        let accounts: [String: Account]
        enum CodingKeys: String, CodingKey { case accounts = "chatgpt-sidebar-state-v2" }
    }
    private struct Account: Decodable { let pinnedConversations: [Pin] }
    private struct Pin: Decodable { let conversation: Conversation }
    private struct Conversation: Decodable { let id: String; let title: String? }

    public static func read(from url: URL) throws -> [CodexSlot] {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= maximumBytes else {
            throw CodexIntegrationError.message("Saved ChatGPT pins are unavailable. Open the ChatGPT pinned list, then refresh.")
        }
        return try slots(from: Data(contentsOf: url))
    }
    public static func slots(from data: Data) throws -> [CodexSlot] {
        guard data.count <= maximumBytes else { throw CodexIntegrationError.message("Saved ChatGPT sidebar is too large to read.") }
        let root: Root
        do { root = try JSONDecoder().decode(Root.self, from: data) }
        catch { throw CodexIntegrationError.message("Saved ChatGPT pins are unavailable or their format changed. Open the ChatGPT pinned list, then refresh.") }
        guard root.state.accounts.count == 1, let account = root.state.accounts.values.first else {
            throw CodexIntegrationError.message("ChatGPT pins need one saved account. Multiple accounts are not combined; use Fixed assignments instead.")
        }
        guard account.pinnedConversations.count <= 100 else {
            throw CodexIntegrationError.message("Saved ChatGPT pins exceed the supported limit.")
        }
        var slots = (1...5).map(CodexSlot.init)
        var seen = Set<String>(), index = 0
        for pin in account.pinnedConversations {
            guard let id = UUID(uuidString: pin.conversation.id)?.uuidString.lowercased(),
                  seen.insert(id).inserted else { continue }
            slots[index].threadID = id
            let title = String((pin.conversation.title ?? "Untitled chat").unicodeScalars
                .filter { !CharacterSet.controlCharacters.contains($0) }.prefix(80))
            slots[index].name = title.isEmpty ? "Untitled chat" : title
            index += 1
            if index == 5 { break }
        }
        return slots
    }
}
