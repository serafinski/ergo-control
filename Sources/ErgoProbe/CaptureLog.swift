import Foundation
import Combine
import ErgoCore

final class CaptureLog: ObservableObject {
    @Published var step: CaptureStep = .baseline
    @Published var rows: [String] = []
    @Published var eventRows: [String] = []
    @Published var reportCount = 0
    @Published var notificationCount = 0
    @Published var fileURL: URL?
    @Published var failure: String?
    private var file: FileHandle?
    private var decoder = InputReportDecoder()
    private let formatter = ISO8601DateFormatter()

    static var captureDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["ERGO_CAPTURE_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        } else {
            return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ErgoControl/Captures", isDirectory: true)
        }
    }

    func resetView() {
        guard file == nil else { return }
        rows = []; eventRows = []; reportCount = 0; notificationCount = 0
        decoder = InputReportDecoder()
        fileURL = nil; failure = nil
    }

    func begin() throws {
        guard file == nil else { return }
        resetView()
        let folder = Self.captureDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let url = folder.appendingPathComponent("\(step.fileKey)-\(UUID().uuidString).jsonl")
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
            let displayFields = fields.filter { $0.key != "descriptor" }
            let line = "\(kind): " + displayFields.keys.sorted().map { "\($0)=\(displayFields[$0]!)" }.joined(separator: " ")
            rows.append(line)
            if rows.count > 250 { rows.removeFirst(rows.count - 250) }
            if kind == "hid_report" {
                reportCount += 1
                let id = (fields["reportID"] as? UInt32) ?? 0
                let hex = fields["hex"] as? String ?? ""
                if let events = decoder.describe(reportID: id, hexadecimal: hex) {
                    eventRows.append(contentsOf: events)
                } else {
                    let name: String
                    switch id {
                    case 1: name = "Keyboard input"
                    case 2: name = "Dial or pointer input"
                    case 3: name = "Media input"
                    case 4: name = "System input"
                    default: name = "Extra input · report \(id)"
                    }
                    eventRows.append("\(reportCount). \(name)")
                }
            } else if kind == "ble_notification" {
                notificationCount += 1
                eventRows.append("Bluetooth notification \(notificationCount)")
            }
            if eventRows.count > 250 { eventRows.removeFirst(eventRows.count - 250) }
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
