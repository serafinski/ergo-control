import Foundation
import ErgoCore

/// Reads one account/organization catalog on a utility queue. No transcript
/// files, credentials, web APIs, CLI subprocesses or desktop mutations.
final class ClaudeHistoryReader: CodexHistorySource {
    var onRecent: (([CodexSlot]) -> Void)?
    var onPinned: (([CodexSlot]) -> Void)?
    var onProblem: ((CodexHistoryIssue) -> Void)?
    var onRecords: (([ClaudeThreadSummary]) -> Void)?
    var catalogFolder: URL?
    private let root: URL
    private let queue = DispatchQueue(label: "dev.local.ergocontrol.claude-history", qos: .utility)
    private var generation = UUID()
    private var reading = false

    init(root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Claude/claude-code-sessions", isDirectory: true)) { self.root = root }

    func refresh() {
        guard !reading else { return }
        reading = true
        let token = generation, root = root, folder = catalogFolder
        queue.async { [weak self] in
            let result = Result { try Self.readCatalog(root: root, selected: folder) }
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.reading = false
                switch result {
                case .success(let records):
                    self.onRecords?(records)
                    self.onRecent?(ClaudeThreadSummary.slots(records))
                    self.onPinned?(ClaudeThreadSummary.slots(records, starredOnly: true))
                case .failure(let error):
                    self.onRecords?([])
                    self.onProblem?(.unavailable(error.localizedDescription))
                }
            }
        }
    }
    func stop() { generation = UUID(); reading = false }

    static func readCatalog(root: URL, selected: URL? = nil) throws -> [ClaudeThreadSummary] {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]
        func children(_ folder: URL) throws -> [URL] {
            let values = try folder.resourceValues(forKeys: keys)
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw CodexIntegrationError.message("Choose a Claude account/organization catalog folder, not a link.")
            }
            return try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        }
        let folder: URL
        if let selected { folder = selected }
        else {
            guard fm.fileExists(atPath: root.path) else {
                throw CodexIntegrationError.message("No Claude desktop catalog yet. Start a local session in Claude Code, then refresh.")
            }
            let accounts = try children(root)
            guard accounts.count <= 32 else { throw CodexIntegrationError.message("Choose the Claude account/organization catalog folder.") }
            var scopes: [URL] = []
            for account in accounts {
                let value = try account.resourceValues(forKeys: keys)
                guard value.isDirectory == true, value.isSymbolicLink != true else { continue }
                let organizations = try children(account)
                guard organizations.count <= 32 else { throw CodexIntegrationError.message("Choose the Claude account/organization catalog folder.") }
                for org in organizations {
                    let value = try org.resourceValues(forKeys: keys)
                    if value.isDirectory == true, value.isSymbolicLink != true { scopes.append(org) }
                }
            }
            guard scopes.count == 1 else {
                throw CodexIntegrationError.message(scopes.isEmpty
                    ? "No Claude desktop sessions yet. Start a local Code session, then refresh."
                    : "Multiple Claude accounts or organizations found. Choose the catalog folder for the one you use.")
            }
            folder = scopes[0]
        }
        let files = try children(folder)
        guard files.count <= 4096 else { throw CodexIntegrationError.message("Claude catalog exceeds the file limit; no partial list was used.") }
        var records: [ClaudeThreadSummary] = []
        var bytes = 0
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        for file in files where file.pathExtension == "json" && file.lastPathComponent.hasPrefix("local_") {
            guard ChatProvider.isClaudeDesktopID(file.deletingPathExtension().lastPathComponent) else {
                throw CodexIntegrationError.message("This Claude catalog uses an unsupported session ID format.")
            }
            let values = try file.resourceValues(forKeys: keys)
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size <= 1_048_576,
                  bytes + size <= 33_554_432, ProcessInfo.processInfo.systemUptime < deadline else {
                throw CodexIntegrationError.message("Claude catalog exceeds safe read limits; no partial list was used.")
            }
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: 1_048_577) ?? Data()
            guard data.count <= 1_048_576, bytes + data.count <= 33_554_432 else {
                throw CodexIntegrationError.message("Claude catalog exceeds safe read limits; no partial list was used.")
            }
            bytes += data.count
            // Parse the envelope first: a malformed file must not silently reorder keys.
            guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = envelope["sessionId"] as? String,
                  id.lowercased() == file.deletingPathExtension().lastPathComponent.lowercased() else {
                throw CodexIntegrationError.message("Claude returned an unfamiliar catalog format. Chat keys were cleared.")
            }
            let excluded = ["parentSessionId", "remoteTarget", "sshConfig"].contains { key in
                envelope[key] != nil && !(envelope[key] is NSNull)
            }
            if envelope["isArchived"] as? Bool == true || excluded { continue }
            if let type = envelope["sessionType"] as? String, type != "code" { continue }
            records.append(try JSONDecoder().decode(ClaudeThreadSummary.self, from: data))
        }
        return records
    }
}
