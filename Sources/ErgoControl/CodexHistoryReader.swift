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
    private var connection: CodexHistoryConnection?
    private let desktopApp: () -> URL?
    private let launch: (Process) throws -> Void
    private var buffer = Data()
    private var pending: (Int, Step)?
    private var sequence = 0
    private var generation = UUID()
    private var initialized = false
    private var deadline: Timer?
    private var rows: [CodexThreadSummary] = []
    private var pinnedSection: String?
    private var retryAfter = Date.distantPast

    init(desktopApp: @escaping () -> URL? = {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.openai.codex" }?.bundleURL
    }, launch: @escaping (Process) throws -> Void = { try $0.run() }) {
        self.desktopApp = desktopApp
        self.launch = launch
    }

    func refresh() {
        // Codex is optional. Do not launch its metadata service at login when
        // the desktop is closed; the bridge retries as part of its own polling.
        guard let app = desktopApp() else {
            stop()
            onProblem?(.unavailable("Codex is closed. Chat features reconnect when it opens; keyboard mappings remain available."))
            return
        }
        guard pending == nil, Date() >= retryAfter else { return }
        if connection == nil { start(app); return }
        guard initialized else { return }
        rows = []; send(.recent(nil), step: .recent(1))
    }
    private func start(_ app: URL) {
        let executable = app.appendingPathComponent("Contents/Resources/codex-cli/bin/codex")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            fail("This Codex version does not expose its local history reader."); return
        }
        let token = UUID(); generation = token
        let connection = CodexHistoryConnection(executable: executable, launch: launch)
        connection.onData = { [weak self] data in
            guard let self, self.generation == token else { return }
            self.receive(data)
        }
        connection.onFailure = { [weak self] message in
            guard let self, self.generation == token else { return }
            self.fail(message)
        }
        self.connection = connection
        connection.start()
        send(.initialize, step: .initialize)
    }
    private func send(_ request: CodexHistoryRequest, step: Step) {
        guard let connection, pending == nil else { return }
        sequence += 1; pending = (sequence, step)
        do { connection.write(try request.data(id: sequence)) }
        catch { fail("Codex history request could not be encoded."); return }
        deadline?.invalidate()
        let timer = Timer(timeInterval: 8, repeats: false) { [weak self] _ in self?.fail("Codex history request timed out. It will retry automatically.") }
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
                guard let connection else { return }
                connection.write(try CodexHistoryRequest.initialized.data(id: 0))
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
        connection?.stop(); connection = nil
        buffer = Data(); rows = []
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
