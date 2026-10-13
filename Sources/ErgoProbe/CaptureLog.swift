import Foundation
import Combine
import ErgoCore

final class CaptureLog: ObservableObject {
    @Published var step: CaptureStep = .baseline
    @Published var rows: [String] = []
    @Published var fileURL: URL?
    @Published var failure: String?
    private var file: FileHandle?
    private let formatter = ISO8601DateFormatter()

    func begin() throws {
        guard file == nil else { return }
        let folder: URL
        if let override = ProcessInfo.processInfo.environment["ERGO_CAPTURE_DIR"] {
            folder = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ErgoControl/Captures", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let url = folder.appendingPathComponent("capture-\(UUID().uuidString).jsonl")
        guard FileManager.default.createFile(atPath: url.path, contents: nil,
                                             attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        file = try FileHandle(forWritingTo: url)
        fileURL = url
        record("session", ["vendor": ErgoTarget.vendorID, "product": ErgoTarget.productID,
                           "transport": ErgoTarget.transport, "schema": 1])
    }

    func record(_ kind: String, _ fields: [String: Any] = [:]) {
        var object = fields
        object["kind"] = kind
        object["time"] = formatter.string(from: Date())
        object["uptime"] = ProcessInfo.processInfo.systemUptime
        object["label"] = step.rawValue
        do {
            let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            if let file { try file.write(contentsOf: bytes + Data([10])) }
            let line = "\(kind): " + fields.keys.sorted().map { "\($0)=\(fields[$0]!)" }.joined(separator: " ")
            rows.append(line)
            if rows.count > 250 { rows.removeFirst(rows.count - 250) }
        } catch {
            failure = "Capture could not be saved: \(error.localizedDescription)"
        }
    }

    func mark() { record("marker", ["action": step.rawValue]) }

    func end() {
        guard let file else { return }
        record("session_end")
        do { try file.synchronize(); try file.close() }
        catch { failure = error.localizedDescription }
        self.file = nil
    }

    deinit { try? file?.close() }
}
