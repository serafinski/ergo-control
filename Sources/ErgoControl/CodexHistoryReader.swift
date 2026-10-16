import AppKit
import ErgoCore

enum CodexHistoryIssue { case unavailable(String), pinnedUnavailable }

protocol CodexHistorySource: AnyObject {
    var onRecent: (([CodexSlot]) -> Void)? { get set }
    var onPinned: (([CodexSlot]) -> Void)? { get set }
    var onProblem: ((CodexHistoryIssue) -> Void)? { get set }
    func refresh()
    func stop()
}

/// A private metadata-only app-server client. It never attaches to/resumes a
/// thread or takes ownership of the desktop's live sessions. Hooks supply live
/// status; this connection supplies saved recency and section ordering only.
final class CodexHistoryReader: CodexHistorySource {
    var onRecent: (([CodexSlot]) -> Void)?
    var onPinned: (([CodexSlot]) -> Void)?
    var onProblem: ((CodexHistoryIssue) -> Void)?
    private enum Step { case initialize, recent(Int), sections, pinned(Int) }
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var pending: (Int, Step)?
    private var sequence = 0
    private var generation = UUID()
    private var initialized = false
    private var deadline: Timer?
    private var rows: [CodexThreadSummary] = []
    private var pinnedSection: String?
    private var retryAfter = Date.distantPast

    func refresh() {
        guard pending == nil, Date() >= retryAfter else { return }
        if process == nil { start(); return }
        guard initialized else { return }
        rows = []; send(.recent(nil), step: .recent(1))
    }
    private func start() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") else {
            fail("ChatGPT desktop could not be found."); return
        }
        let executable = app.appendingPathComponent("Contents/Resources/codex-cli/bin/codex")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            fail("This ChatGPT version does not expose its local history reader."); return
        }
        let token = UUID(); generation = token
        let task = Process(); let stdin = Pipe(); let stdout = Pipe()
        task.executableURL = executable; task.arguments = ["app-server", "--stdio"]
        task.standardInput = stdin; task.standardOutput = stdout; task.standardError = FileHandle.nullDevice
        let fd = stdout.fileHandleForReading.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        // Read on a pipe queue, then serialize every state change on main.
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            // Foundation's bounded read may wait to fill the requested size;
            // an interactive JSONL stream must consume only available bytes.
            var bytes = [UInt8](repeating: 0, count: 65_536)
            let count = read(fd, &bytes, bytes.count)
            if count < 0 && [EAGAIN, EINTR].contains(errno) { return }
            let data = count > 0 ? Data(bytes.prefix(count)) : Data()
            if data.isEmpty { handle.readabilityHandler = nil }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                if data.isEmpty { self.fail("ChatGPT history connection ended.") }
                else { self.receive(data) }
            }
        }
        task.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.fail("ChatGPT history connection ended.")
            }
        }
        process = task; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
        do { try task.run(); send(.initialize, step: .initialize) }
        catch { fail("Could not open ChatGPT history: \(error.localizedDescription)") }
    }
    private func send(_ request: CodexHistoryRequest, step: Step) {
        guard let input, pending == nil else { return }
        sequence += 1; pending = (sequence, step)
        do { try input.write(contentsOf: request.data(id: sequence)) }
        catch { fail("ChatGPT history connection is unavailable."); return }
        deadline?.invalidate()
        let timer = Timer(timeInterval: 8, repeats: false) { [weak self] _ in self?.fail("ChatGPT history request timed out. It will retry automatically.") }
        deadline = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func receive(_ data: Data) {
        guard buffer.count + data.count <= 4_194_304 else { fail("ChatGPT history response exceeded the size limit."); return }
        buffer.append(data)
        while let end = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = object["id"] as? Int, let (wanted, step) = pending, wanted == id else { continue }
            pending = nil; deadline?.invalidate(); deadline = nil
            if object["error"] != nil {
                if case .sections = step {
                    onPinned?((1...5).map(CodexSlot.init))
                    onProblem?(.pinnedUnavailable)
                } else { fail("ChatGPT could not list the requested chats. It will retry automatically.") }
                continue
            }
            guard let result = object["result"] as? [String: Any] else { fail("Unexpected ChatGPT history response."); return }
            handle(result, step: step)
        }
    }
    private func handle(_ result: [String: Any], step: Step) {
        do {
            switch step {
            case .initialize:
                guard let input else { return }
                try input.write(contentsOf: CodexHistoryRequest.initialized.data(id: 0))
                initialized = true; rows = []
                send(.recent(nil), step: .recent(1))
            case .recent(let page):
                let value = try CodexThreadSummary.list(from: JSONSerialization.data(withJSONObject: result))
                rows += value.threads
                if Set(rows.map(\.id)).count < 5, let cursor = value.cursor, page < 5 {
                    send(.recent(cursor), step: .recent(page + 1)); return
                }
                onRecent?(CodexThreadSummary.slots(rows)); rows = []
                send(.sections, step: .sections)
            case .sections:
                guard let sections = result["data"] as? [[String: Any]] else { throw CodexIntegrationError.invalidEvent }
                // Remember the identity if the user later renames the section.
                if !sections.contains(where: { $0["id"] as? String == pinnedSection }) {
                    let matches = sections.filter { $0["name"] as? String == "Pinned" }
                    pinnedSection = matches.count == 1 ? matches[0]["id"] as? String : nil
                }
                guard let pinnedSection else { onPinned?((1...5).map(CodexSlot.init)); return }
                rows = []; send(.pinned(section: pinnedSection, cursor: nil), step: .pinned(1))
            case .pinned(let page):
                let value = try CodexThreadSummary.list(from: JSONSerialization.data(withJSONObject: result))
                rows += value.threads
                if Set(rows.map(\.id)).count < 5, let cursor = value.cursor, let section = pinnedSection, page < 5 {
                    send(.pinned(section: section, cursor: cursor), step: .pinned(page + 1)); return
                }
                onPinned?(CodexThreadSummary.slots(rows)); rows = []
            }
        } catch { fail("ChatGPT returned an unsupported history format.") }
    }
    private func fail(_ message: String) {
        stop(); retryAfter = Date().addingTimeInterval(10)
        onProblem?(.unavailable(message))
    }
    func stop() {
        generation = UUID(); initialized = false; pending = nil
        deadline?.invalidate(); deadline = nil
        output?.readabilityHandler = nil
        try? input?.close(); try? output?.close(); input = nil; output = nil
        if let process, process.isRunning {
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        process = nil; buffer = Data(); rows = []
    }
    deinit { stop() }

    static func checkCommandLine() -> Never {
        let reader = CodexHistoryReader()
        var recent: [CodexSlot]?; var pinned: [CodexSlot]?; var failed = false
        reader.onRecent = { recent = $0 }
        reader.onPinned = { pinned = $0 }
        reader.onProblem = { issue in
            failed = true
            if case .unavailable(let message) = issue { print(message) }
            else { print("Pinned metadata is unavailable.") }
        }
        reader.refresh()
        let limit = Date().addingTimeInterval(12)
        while Date() < limit && !failed && (recent == nil || pinned == nil) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.025))
        }
        reader.stop()
        guard !failed, let recent, let pinned else { print("History metadata check failed; no chats changed."); exit(1) }
        print("Recent slots: \(recent.filter { $0.threadID != nil }.count); pinned slots: \(pinned.filter { $0.threadID != nil }.count). Metadata only; no chats started or resumed.")
        exit(0)
    }
}
