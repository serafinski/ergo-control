import Foundation
import Darwin
import ErgoCore

// Always fail open with an empty hook response. This bridge never approves,
// blocks, continues, or starts a Codex turn, including when Ergo Control is off.
defer { print("{}") }
let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("ErgoControl/Codex", isDirectory: true)
if CommandLine.arguments.dropFirst().first == "--ergo-codex-hook-v1",
   let receiver = try? String(contentsOf: folder.appendingPathComponent("receiver.pid"), encoding: .utf8),
   let pid = Int32(receiver), pid > 0, kill(pid, 0) == 0 {
    // Bounded read even for a tool hook containing very large tool output.
    let input = FileHandle.standardInput.readData(ofLength: 1_048_577)
    if let event = try? CodexHookEvent(input: input),
       let data = try? JSONEncoder().encode(event) {
        let queue = folder.appendingPathComponent("events", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: queue.path)) ?? []
        if files.count < 128 {
            let url = queue.appendingPathComponent(UUID().uuidString + ".json")
            do {
                try data.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch { /* A status indicator must never interrupt Codex. */ }
        }
    }
}
