import Foundation

/// Process launch and pipe I/O belong to this optional connection, never the
/// main run loop that starts and relays keyboard input. Each session has its own
/// queue so a slow launch cannot delay a later connection or keyboard startup.
final class CodexHistoryConnection {
    var onData: ((Data) -> Void)?
    var onFailure: ((String) -> Void)?
    private let queue = DispatchQueue(label: "dev.local.ergocontrol.codex-history", qos: .utility)
    private let task = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let launch: (Process) throws -> Void
    private let lock = NSLock()
    private var cancelled = false
    private var cleanedUp = false // Accessed only on the connection queue.

    init(executable: URL, launch: @escaping (Process) throws -> Void) {
        self.launch = launch
        task.executableURL = executable; task.arguments = ["app-server", "--stdio"]
        task.standardInput = input; task.standardOutput = output; task.standardError = FileHandle.nullDevice
    }
    private var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }
    func start() {
        queue.async { [self] in
            guard !isCancelled else { return }
            let fd = output.fileHandleForReading.fileDescriptor
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            output.fileHandleForReading.readabilityHandler = { [weak self] handle in
                var bytes = [UInt8](repeating: 0, count: 65_536)
                let count = read(fd, &bytes, bytes.count)
                if count < 0 && [EAGAIN, EINTR].contains(errno) { return }
                if count <= 0 {
                    handle.readabilityHandler = nil
                    self?.fail("Codex history connection ended.")
                } else {
                    let data = Data(bytes.prefix(count))
                    DispatchQueue.main.async { [weak self] in
                        guard let self, !self.isCancelled else { return }
                        self.onData?(data)
                    }
                }
            }
            task.terminationHandler = { [weak self] _ in self?.fail("Codex history connection ended.") }
            do {
                try launch(task)
                // Never block a background worker indefinitely on an unresponsive
                // child. Requests are small; a full pipe disconnects and retries.
                let writeFD = input.fileHandleForWriting.fileDescriptor
                _ = fcntl(writeFD, F_SETFL, fcntl(writeFD, F_GETFL) | O_NONBLOCK)
                if isCancelled { cleanup() }
            } catch { fail("Could not open Codex history: \(error.localizedDescription)") }
        }
    }
    func write(_ data: Data) {
        queue.async { [self] in
            guard !isCancelled else { return }
            do { try input.fileHandleForWriting.write(contentsOf: data) }
            catch { fail("Codex history connection is unavailable.") }
        }
    }
    private func fail(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isCancelled else { return }
            self.onFailure?(message)
        }
    }
    func stop() {
        lock.lock(); cancelled = true; lock.unlock()
        queue.async { [self] in cleanup() }
    }
    private func cleanup() {
        guard !cleanedUp else { return }
        cleanedUp = true
        output.fileHandleForReading.readabilityHandler = nil
        task.terminationHandler = nil
        if task.isRunning {
            task.terminate()
            let process = task
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        try? input.fileHandleForWriting.close()
        try? output.fileHandleForReading.close()
    }
}
