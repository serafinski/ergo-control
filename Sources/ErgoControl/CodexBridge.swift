import AppKit
import Combine
import ErgoCore

final class CodexBridge: ObservableObject {
    @Published private(set) var settings = CodexSettings()
    @Published private(set) var sessions: [String: CodexSessionStatus] = [:]
    @Published private(set) var message = "Enable the connection, then install the Codex status hooks."
    @Published private(set) var historyMessage = ""
    @Published private(set) var recentSlots = (1...5).map(CodexSlot.init)
    @Published private(set) var pinnedSlots = (1...5).map(CodexSlot.init)
    @Published private(set) var chatgptPinnedSlots = (1...5).map(CodexSlot.init)
    private let chatgptPins: () throws -> [CodexSlot]
    var onLightingChange: ((DialColor?) -> Void)?
    private var timer: Timer?
    private var lastColor: DialColor?
    private var lastExpiryRefresh = Date.distantPast
    private var nextHistoryRefresh = Date.distantPast
    private let history: CodexHistorySource?
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

    init(folder: URL = CodexBridge.defaultFolder, startTimer: Bool = true, history: CodexHistorySource? = nil, chatgptPins: (() throws -> [CodexSlot])? = nil) {
        self.chatgptPins = chatgptPins ?? { try ChatGPTPins.read(from: ChatGPTPins.defaultURL) }
        self.folder = folder
        self.history = history ?? (startTimer ? CodexHistoryReader() : nil)
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
        self.history?.onRecent = { [weak self] slots in
            guard let self, self.settings.enabled, self.settings.source == .codex else { return }
            if self.recentSlots != slots { self.recentSlots = slots }
            if self.settings.selection == .recent && self.historyMessage != "Recent Codex chats synced." {
                self.historyMessage = "Recent Codex chats synced."
            }
            self.updateLighting()
        }
        self.history?.onPinned = { [weak self] slots in
            guard let self, self.settings.enabled, self.settings.source == .codex else { return }
            if self.pinnedSlots != slots { self.pinnedSlots = slots }
            if self.settings.selection == .pinned && self.historyMessage != "Pinned Codex chats synced." {
                self.historyMessage = "Pinned Codex chats synced."
            }
            self.updateLighting()
        }
        self.history?.onProblem = { [weak self] issue in
            guard let self, self.settings.enabled, self.settings.source == .codex else { return }
            switch issue {
            case .unavailable(let message):
                self.recentSlots = (1...5).map(CodexSlot.init); self.pinnedSlots = self.recentSlots
                self.historyMessage = message
            case .pinnedUnavailable:
                self.pinnedSlots = (1...5).map(CodexSlot.init)
                self.historyMessage = "Recent chats synced; pinned selection is unavailable in this ChatGPT version."
            }
            self.updateLighting()
        }
        if settings.enabled { message = connectionMessage; refreshHistory() }
        if startTimer {
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
            self.timer = timer; RunLoop.main.add(timer, forMode: .common)
        }
    }

    func setEnabled(_ enabled: Bool) {
        var value = settings; value.enabled = enabled
        guard save(value) else { return }
        do { try updateReceiver() } catch { message = error.localizedDescription }
        if !enabled {
            history?.stop(); sessions = [:]
            recentSlots = (1...5).map(CodexSlot.init); pinnedSlots = recentSlots
            chatgptPinnedSlots = recentSlots
            updateLighting()
        } else {
            message = connectionMessage
            if settings.activeSelection != .fixed { refreshHistory() }
        }
    }
    var displaySlots: [CodexSlot] {
        if settings.source == .chatgpt {
            return settings.activeSelection == .fixed ? settings.chatgptSlots : chatgptPinnedSlots
        }
        switch settings.selection {
        case .recent: return recentSlots
        case .pinned: return pinnedSlots
        case .fixed: return settings.slots
        }
    }
    var assignedSlotCount: Int { displaySlots.filter { $0.threadID != nil }.count }
    var emptySlotLabel: String {
        switch settings.activeSelection {
        case .recent: return "No other recent chat"
        case .pinned: return "No other pinned chat"
        case .fixed: return "No chat assigned"
        }
    }
    func setSelection(_ mode: CodexSelectionMode) {
        guard settings.source.selections.contains(mode) else { return }
        var value = settings
        if value.source == .codex { value.selection = mode } else { value.chatgptSelection = mode }
        guard save(value) else { return }
        if mode == .fixed { history?.stop() }
        else if settings.enabled { refreshHistory() }
        updateLighting()
    }
    var selectionLabel: String {
        switch settings.activeSelection {
        case .recent: return "Recent \(settings.source.label) chats"
        case .pinned: return "Pinned \(settings.source.label) chats"
        case .fixed: return "Fixed \(settings.source.label) assignments"
        }
    }
    private var connectionMessage: String {
        settings.source == .codex ? "Connected to Codex. Status updates arrive from trusted hooks during desktop activity."
            : "ChatGPT chat keys enabled. Recent chats and live status are not available for this source."
    }
    func slotURL(_ slot: CodexSlot) -> URL? { settings.source.url(for: slot) }
    func statusLabel(_ slot: CodexSlot) -> String {
        settings.source == .codex ? activity(slot).label : "Status unavailable"
    }
    func setSource(_ source: ChatSource) {
        guard source != settings.source else { return }
        var value = settings; value.source = source
        guard save(value) else { return }
        history?.stop(); sessions = [:]; historyMessage = ""
        // Events queued for the previous source must never cross the boundary.
        if let files = try? FileManager.default.contentsOfDirectory(at: queue, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "json" { try? FileManager.default.removeItem(at: file) }
        }
        do { try updateReceiver() } catch { message = error.localizedDescription }
        if settings.enabled { message = connectionMessage; refreshHistory() }
        updateLighting()
    }
    func setUseUnmappedMacroKeys(_ enabled: Bool) {
        var value = settings; value.useUnmappedMacroKeys = enabled
        _ = save(value)
    }
    func defaultAction(for control: String) -> MappingAction? {
        guard settings.enabled, settings.useUnmappedMacroKeys,
              control.hasPrefix("extra:"), let key = Int(control.dropFirst(6)), (32...36).contains(key) else { return nil }
        return MappingAction(.codexChat, String(key - 31))
    }
    func refreshHistory() {
        guard settings.enabled, settings.activeSelection != .fixed else { return }
        nextHistoryRefresh = Date().addingTimeInterval(10)
        if settings.source == .chatgpt {
            do {
                let slots = try chatgptPins()
                if chatgptPinnedSlots != slots { chatgptPinnedSlots = slots }
                let message = "Saved ChatGPT pins synced. The first five follow their pinned order."
                if historyMessage != message { historyMessage = message }
            } catch {
                chatgptPinnedSlots = (1...5).map(CodexSlot.init)
                if historyMessage != error.localizedDescription { historyMessage = error.localizedDescription }
            }
        } else { history?.refresh() }
    }
    func setLighting(_ enabled: Bool) {
        var value = settings; value.lighting = enabled
        if save(value) { updateLighting() }
    }
    func assign(_ index: Int, name: String, link: String) {
        guard settings.fixedSlots.indices.contains(index) else { return }
        let empty = link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard empty || settings.source.threadID(from: link) != nil else {
            message = "Use a \(settings.source.linkPlaceholder) link or a chat UUID."; return
        }
        var value = settings
        var assignments = value.fixedSlots
        assignments[index].threadID = empty ? nil : settings.source.threadID(from: link)
        assignments[index].name = String(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(80))
        if value.source == .codex { value.slots = assignments } else { value.chatgptSlots = assignments }
        if save(value) { message = "Slot saved."; updateLighting() }
    }
    private func save(_ value: CodexSettings) -> Bool {
        do {
            try value.validate()
            try JSONEncoder().encode(value).write(to: settingsURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsURL.path)
            settings = value
            pruneSessions()
            return true
        } catch { message = error.localizedDescription; return false }
    }
    private func updateReceiver() throws {
        if settings.enabled && settings.source == .codex {
            try Data(String(ProcessInfo.processInfo.processIdentifier).utf8).write(to: receiverURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: receiverURL.path)
        } else { try? FileManager.default.removeItem(at: receiverURL) }
    }
    func shutdown() {
        timer?.invalidate(); timer = nil
        history?.stop()
        try? FileManager.default.removeItem(at: receiverURL)
        onLightingChange?(nil)
    }
    func activity(_ slot: CodexSlot) -> CodexActivity {
        guard settings.source == .codex else { return .unknown }
        return slot.threadID.flatMap { sessions[$0.lowercased()]?.activity(now: Date()) } ?? .unknown
    }
    func poll() {
        if settings.enabled, settings.activeSelection != .fixed, Date() >= nextHistoryRefresh { refreshHistory() }
        guard let files = try? FileManager.default.contentsOfDirectory(at: queue, includingPropertiesForKeys: nil) else { return }
        var events: [CodexHookEvent] = []
        for url in files.prefix(256) where url.pathExtension == "json" {
            defer { try? FileManager.default.removeItem(at: url) }
            guard settings.enabled, settings.source == .codex,
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 4096,
                  let data = try? Data(contentsOf: url),
                  let event = try? JSONDecoder().decode(CodexHookEvent.self, from: data), event.validate(now: Date()) else { continue }
            events.append(event)
        }
        for event in events.sorted(by: { $0.time < $1.time }) {
            if var state = sessions[event.sessionID] { state.receive(event); sessions[event.sessionID] = state }
            else {
                if settings.selection == .fixed,
                   !settings.slots.contains(where: { $0.threadID?.lowercased() == event.sessionID }),
                   let index = settings.slots.firstIndex(where: { $0.threadID == nil }) {
                    var value = settings
                    value.slots[index].threadID = event.sessionID
                    value.slots[index].name = event.project.isEmpty ? "Chat \(index + 1)" : event.project
                    guard save(value) else { continue }
                }
                if settings.selection == .fixed && !settings.slots.contains(where: { $0.threadID?.lowercased() == event.sessionID }) { continue }
                sessions[event.sessionID] = CodexSessionStatus(event)
            }
            if ["UserPromptSubmit", "Stop", "SessionEnd"].contains(event.event) {
                nextHistoryRefresh = min(nextHistoryRefresh, Date().addingTimeInterval(1))
            }
            message = "Connected · latest event: \(event.event). Status is observed activity, not unread state."
        }
        if !events.isEmpty || Date().timeIntervalSince(lastExpiryRefresh) >= 30 {
            lastExpiryRefresh = Date(); objectWillChange.send()
        }
        // Also refresh time-based expiry when no new event has arrived.
        updateLighting()
        pruneSessions()
    }
    private func pruneSessions() {
        // Bounded transient state allows a recent chat to become a pinned slot
        // without losing its already observed status. Never persist activity.
        if settings.selection == .fixed {
            let fixed = Set(settings.slots.compactMap(\.threadID))
            let retained = sessions.filter { fixed.contains($0.key) }
            if retained.count != sessions.count { sessions = retained }
        } else if sessions.count > 100 {
            let keep = Set(sessions.sorted { $0.value.latest.time > $1.value.latest.time }.prefix(100).map(\.key))
            sessions = sessions.filter { keep.contains($0.key) }
        }
    }
    private func updateLighting() {
        let state = CodexActivity.priority(displaySlots.map(activity))
        let color = settings.enabled && settings.source == .codex && settings.lighting && state != .unknown ? state.color : nil
        if color != lastColor { lastColor = color; onLightingChange?(color) }
    }
    var lightingColor: DialColor? {
        let state = CodexActivity.priority(displaySlots.map(activity))
        return settings.enabled && settings.source == .codex && settings.lighting && state != .unknown ? state.color : nil
    }
    func openSlot(_ number: Int) {
        guard settings.enabled else { message = "Enable the chat connection first."; return }
        guard let slot = displaySlots.first(where: { $0.id == number }), let url = slotURL(slot) else {
            message = "M\(number) has no chat in \(selectionLabel)."; return
        }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") else {
            message = "The ChatGPT desktop app could not be found."; return
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
