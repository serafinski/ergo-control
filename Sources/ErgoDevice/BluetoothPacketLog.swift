import Foundation

/// Packet diagnostics are not recovery state. Capture times at enqueue, then
/// format and write in order off the Bluetooth/input/UI thread.
final class BluetoothPacketLog {
    private let file: FileHandle
    private let queue: DispatchQueue
    private let formatter = ISO8601DateFormatter()
    private let onFailure: () -> Void
    private var reportedFailure = false // writer queue only

    init(file: FileHandle, queue: DispatchQueue = DispatchQueue(label: "dev.local.ergocontrol.bluetooth-log", qos: .utility),
         onFailure: @escaping () -> Void = {}) {
        self.file = file; self.queue = queue; self.onFailure = onFailure
    }
    static func normalized(_ fields: [String: Any]) -> [String: Any] {
        fields.mapValues { value in
            if let bytes = value as? Data { return bytes.map { String(format: "%02x", $0) }.joined() }
            return value
        }
    }
    func append(_ kind: String, fields: [String: Any], time: Date = Date(),
                uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        queue.async { [self] in
            var object = Self.normalized(fields)
            object["kind"] = kind
            object["time"] = formatter.string(from: time)
            object["uptime"] = uptime
            do {
                let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
                try file.write(contentsOf: data + Data([10]))
            } catch {
                if !reportedFailure {
                    reportedFailure = true
                    DispatchQueue.main.async(execute: onFailure)
                }
            }
        }
    }
    /// Only at termination after input restoration, or in tests.
    func flush() { queue.sync {} }
}
