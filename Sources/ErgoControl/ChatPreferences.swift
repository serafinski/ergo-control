import Foundation
import Combine
import ErgoCore

final class ChatPreferences: ObservableObject {
    @Published private(set) var provider: ChatProvider = .codex
    @Published private(set) var error: String?
    private let file: URL
    init(file: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ErgoControl/chat-provider.json")) {
        self.file = file
        if FileManager.default.fileExists(atPath: file.path) {
            do { provider = try JSONDecoder().decode(ChatProvider.self, from: Data(contentsOf: file)) }
            catch { self.error = "The saved chat provider could not be read. Codex remains selected." }
        }
    }
    @discardableResult func select(_ value: ChatProvider) -> Bool {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(value).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            provider = value; error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
