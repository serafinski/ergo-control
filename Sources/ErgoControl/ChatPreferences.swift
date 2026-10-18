import Foundation
import Combine
import ErgoCore

final class ChatPreferences: ObservableObject {
    @Published private(set) var provider: ChatProvider = .codex
    @Published private(set) var lightingMode: ChatLightingMode = .automatic
    @Published private(set) var error: String?
    private let file: URL
    init(file: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ErgoControl/chat-provider.json")) {
        self.file = file
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let data = try Data(contentsOf: file)
                if let legacy = try? JSONDecoder().decode(ChatProvider.self, from: data) { provider = legacy }
                else {
                    let saved = try JSONDecoder().decode(Saved.self, from: data)
                    provider = saved.provider; lightingMode = saved.lightingMode
                }
            }
            catch { self.error = "The saved chat provider could not be read. Codex remains selected." }
        }
    }
    @discardableResult func select(_ value: ChatProvider) -> Bool {
        save(provider: value, lightingMode: lightingMode)
    }
    @discardableResult func selectLighting(_ value: ChatLightingMode) -> Bool {
        save(provider: provider, lightingMode: value)
    }
    private struct Saved: Codable {
        let provider: ChatProvider
        let lightingMode: ChatLightingMode
    }
    private func save(provider: ChatProvider, lightingMode: ChatLightingMode) -> Bool {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(Saved(provider: provider, lightingMode: lightingMode)).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            self.provider = provider; self.lightingMode = lightingMode; error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
