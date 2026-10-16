import AppKit
import Combine
import ErgoCore

final class CodexBridge: ObservableObject {
    @Published private(set) var settings = CodexSettings()
    @Published private(set) var sessions: [String: CodexSessionStatus] = [:]
    @Published private(set) var message = "Enable the connection, then install the Codex status hooks."
    var onLightingChange: ((DialColor?) -> Void)?
    private var timer: Timer?
    private var lastColor: DialColor?
    private var lastExpiryRefresh = Date.distantPast
    static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ErgoControl/Codex", isDirectory: true)
    }
    private let folder: URL
    private var queue: URL { folder.appendingPathComponent("events", isDirectory: true) }
    private var settingsURL: URL { folder.appendingPathComponent("settings.json") }
    private var receiverURL: URL { folder.appendingPathComponent("receiver.pid") }
    private var senderURL: URL { folder.appendingPathComponent("ErgoCodexHook") }
    private var codexHome: URL {
        ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }
    var hooksURL: URL { codexHome.appendingPathComponent("hooks.json") }

    init(folder: URL = CodexBridge.defaultFolder, startTimer: Bool = true) {
        self.folder = folder
        do {
            try FileManager.default.createDirectory(at: queue, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
            if FileManager.default.fileExists(atPath: settingsURL.path) {
                let saved = try JSONDecoder().decode(CodexSettings.self, from: Data(contentsOf: settingsURL))
                try saved.validate(); settings = saved
            }
            try updateReceiver()
        } catch { message = error.localizedDescription }
        if startTimer {
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
            self.timer = timer; RunLoop.main.add(timer, forMode: .common)
        }
    }

    func setEnabled(_ enabled: Bool) {
        var value = settings; value.enabled = enabled
        guard save(value) else { return }
        do { try updateReceiver() } catch { message = error.localizedDescription }
        if !enabled { sessions = [:]; updateLighting() }
        else { message = "Waiting for Codex events. Install hooks and review them in Codex; existing chats appear after new activity." }
    }
    func setLighting(_ enabled: Bool) {
        var value = settings; value.lighting = enabled
        if save(value) { updateLighting() }
    }
    func assign(_ index: Int, name: String, link: String) {
        guard settings.slots.indices.contains(index) else { return }
        let empty = link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard empty || CodexSlot.threadID(from: link) != nil else {
            message = "Use a codex://threads/… link or a chat UUID."; return
        }
        var value = settings
        value.slots[index].threadID = empty ? nil : CodexSlot.threadID(from: link)
        value.slots[index].name = String(name.prefix(80))
        if save(value) { message = "Slot saved. Empty slots fill from the next observed chats."; updateLighting() }
    }
    private func save(_ value: CodexSettings) -> Bool {
        do {
            try value.validate()
            try JSONEncoder().encode(value).write(to: settingsURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsURL.path)
            settings = value
            let assigned = Set(value.slots.compactMap(\.threadID).map { $0.lowercased() })
            sessions = sessions.filter { assigned.contains($0.key) }
            return true
        } catch { message = error.localizedDescription; return false }
    }
    private func updateReceiver() throws {
        if settings.enabled {
            try Data(String(ProcessInfo.processInfo.processIdentifier).utf8).write(to: receiverURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: receiverURL.path)
        } else { try? FileManager.default.removeItem(at: receiverURL) }
    }
    func shutdown() {
        timer?.invalidate(); timer = nil
        try? FileManager.default.removeItem(at: receiverURL)
        onLightingChange?(nil)
    }
    func activity(_ slot: CodexSlot) -> CodexActivity {
        slot.threadID.flatMap { sessions[$0.lowercased()]?.activity(now: Date()) } ?? .unknown
    }
    func poll() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: queue, includingPropertiesForKeys: nil) else { return }
        var events: [CodexHookEvent] = []
        for url in files.prefix(256) where url.pathExtension == "json" {
            defer { try? FileManager.default.removeItem(at: url) }
            guard settings.enabled,
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 4096,
                  let data = try? Data(contentsOf: url),
                  let event = try? JSONDecoder().decode(CodexHookEvent.self, from: data), event.validate(now: Date()) else { continue }
            events.append(event)
        }
        for event in events.sorted(by: { $0.time < $1.time }) {
            if var state = sessions[event.sessionID] { state.receive(event); sessions[event.sessionID] = state }
            else {
                // Keep only five assigned sessions: no transcript or growing history.
                if !settings.slots.contains(where: { $0.threadID?.lowercased() == event.sessionID }),
                   let index = settings.slots.firstIndex(where: { $0.threadID == nil }) {
                    var value = settings
                    value.slots[index].threadID = event.sessionID
                    value.slots[index].name = event.project.isEmpty ? "Chat \(index + 1)" : event.project
                    guard save(value) else { continue }
                }
                guard settings.slots.contains(where: { $0.threadID?.lowercased() == event.sessionID }) else { continue }
                sessions[event.sessionID] = CodexSessionStatus(event)
            }
            message = "Connected · latest event: \(event.event). Status is observed activity, not unread state."
        }
        if !events.isEmpty || Date().timeIntervalSince(lastExpiryRefresh) >= 30 {
            lastExpiryRefresh = Date(); objectWillChange.send()
        }
        // Also refresh time-based expiry when no new event has arrived.
        updateLighting()
    }
    private func updateLighting() {
        let state = CodexActivity.priority(settings.slots.map(activity))
        let color = settings.enabled && settings.lighting && state != .unknown ? state.color : nil
        if color != lastColor { lastColor = color; onLightingChange?(color) }
    }
    var lightingColor: DialColor? {
        let state = CodexActivity.priority(settings.slots.map(activity))
        return settings.enabled && settings.lighting && state != .unknown ? state.color : nil
    }
    func openSlot(_ number: Int) {
        guard settings.enabled else { message = "Enable the Codex connection first."; return }
        guard let slot = settings.slots.first(where: { $0.id == number }), let url = slot.url else {
            message = "M\(number) has no chat yet. Start a Codex turn or assign a chat link."; return
        }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") else {
            message = "Codex desktop could not be found."; return
        }
        let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration) { [weak self] _, error in
            if let error { DispatchQueue.main.async { self?.message = "Could not open chat: \(error.localizedDescription)" } }
        }
    }
    func installHooks(remove: Bool = false) {
        do {
            let fm = FileManager.default
            guard let bundled = Bundle.main.url(forResource: "ErgoCodexHook", withExtension: nil) else {
                throw CodexIntegrationError.message("The bundled Codex hook sender is missing. Rebuild Ergo Control.")
            }
            let existing = fm.fileExists(atPath: hooksURL.path) ? try Data(contentsOf: hooksURL) : nil
            let data = try CodexHookConfiguration.updating(existing, executable: senderURL.path, install: !remove)
            try fm.createDirectory(at: codexHome, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if let existing {
                let backup = codexHome.appendingPathComponent("hooks.json.ergo-backup-\(UUID().uuidString)")
                try existing.write(to: backup, options: .atomic)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
            }
            if !remove {
                try Data(contentsOf: bundled).write(to: senderURL, options: .atomic)
                try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: senderURL.path)
            }
            try data.write(to: hooksURL, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: hooksURL.path)
            message = remove ? "Ergo Control hooks removed; other hooks were preserved."
                : "Hooks installed. Review and trust ErgoCodexHook if ChatGPT asks, then start a desktop turn. If already accepted, no further review is needed."
        } catch { message = error.localizedDescription }
    }
}
