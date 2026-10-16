import Foundation
import Combine

/// Bounded local app events. Callers supply status/diagnostic messages, never
/// raw keyboard reports, macro text, chat titles, prompts or hook payloads.
final class AppLog: ObservableObject {
    enum Level: String, Codable, CaseIterable { case info, warning, error }
    struct Entry: Codable, Identifiable {
        var id = UUID()
        let time: Date
        let level: Level
        let category: String
        let message: String
    }
    static let limit = 300
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var storageError: String?
    private let writer = DispatchQueue(label: "dev.local.ergocontrol.app-log", qos: .utility)
    let file: URL
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ErgoControl/Logs", isDirectory: true)
    }
    init(folder: URL = AppLog.folder) {
        file = folder.appendingPathComponent("app-events.json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            if FileManager.default.fileExists(atPath: file.path) {
                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 2_097_152 else { storageError = "Saved app log is too large to load."; return }
                entries = Array(try JSONDecoder().decode([Entry].self, from: Data(contentsOf: file)).suffix(Self.limit))
            }
        } catch { storageError = "Could not read the saved app log." }
    }
    func record(_ message: String, category: String = "App", level: Level = .info, now: Date = Date()) {
        guard !message.isEmpty else { return }
        let text = String(message.prefix(800))
        if let last = entries.last, last.message == text, last.category == category,
           last.level == level, now.timeIntervalSince(last.time) < 1 { return }
        entries.append(Entry(time: now, level: level, category: category, message: text))
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
        persist()
    }
    func clear() { entries = []; persist() }
    private func persist() {
        let snapshot = entries, file = file
        writer.async { [weak self] in
            let issue: String?
            do {
                try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                issue = nil
            } catch { issue = "Could not save the app log. Current events remain visible." }
            DispatchQueue.main.async { [weak self] in
                if self?.storageError != issue { self?.storageError = issue }
            }
        }
    }
    /// Used after input capture has stopped at quit, and by persistence checks.
    func flush() { writer.sync {} }
    var text: String {
        let formatter = ISO8601DateFormatter()
        return entries.map { "\(formatter.string(from: $0.time)) [\($0.level.rawValue)] \($0.category): \($0.message)" }.joined(separator: "\n")
    }
}
