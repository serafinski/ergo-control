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
    var onLightingChange: ((DialColor?) -> Void)?
    @Published private(set) var lightingTestStage: CodexLightingTestStage?
    private var lightingTestStarted: TimeInterval?
    private let uptime: () -> TimeInterval
    private let now: () -> Date
    private var timer: Timer?
    private var lastColor: DialColor?
    private var lastAllowsCompletionToFinish = false
    private var shuttingDown = false
    private var lastArea: CodexLightingArea = .macroColumn
    private var lastWaveSpeed: CodexWaveSpeed = .smooth
    private var lastPulseWhileWorking = false
    private var lastDarkStatusBackground = false
    private var lastSignalID: String?
    private var lastActivities: [CodexActivity] = []
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

    init(folder: URL = CodexBridge.defaultFolder, startTimer: Bool = true, history: CodexHistorySource? = nil, uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, now: @escaping () -> Date = Date.init) {
        self.now = now
        self.uptime = uptime
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
            guard let self, self.settings.enabled else { return }
            if self.recentSlots != slots { self.recentSlots = slots }
            if self.settings.selection == .recent && self.historyMessage != "Recent Codex chats synced." {
                self.historyMessage = "Recent Codex chats synced."
            }
            self.updateLighting()
        }
        self.history?.onPinned = { [weak self] slots in
            guard let self, self.settings.enabled else { return }
            if self.pinnedSlots != slots { self.pinnedSlots = slots }
            if self.settings.selection == .pinned && self.historyMessage != "Pinned Codex chats synced." {
                self.historyMessage = "Pinned Codex chats synced."
            }
            self.updateLighting()
        }
        self.history?.onProblem = { [weak self] issue in
            guard let self, self.settings.enabled else { return }
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
        if settings.enabled {
            message = "Connected to Codex. Status updates arrive from trusted hooks during desktop activity."
            if settings.selection != .fixed { refreshHistory() }
        }
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
            message = "Codex connection is off."
            cancelLightingTest()
            history?.stop(); sessions = [:]
            recentSlots = (1...5).map(CodexSlot.init); pinnedSlots = recentSlots
            updateLighting()
        } else {
            message = "Connected to Codex. Status updates arrive from trusted hooks during desktop activity."
            if settings.selection != .fixed { refreshHistory() }
        }
    }
    var displaySlots: [CodexSlot] {
        switch settings.selection {
        case .recent: return recentSlots
        case .pinned: return pinnedSlots
        case .fixed: return settings.slots
        }
    }
    var assignedSlotCount: Int { displaySlots.filter { $0.threadID != nil }.count }
    var emptySlotLabel: String {
        switch settings.selection {
        case .recent: return "No other recent Codex chat"
        case .pinned: return "No other pinned Codex chat"
        case .fixed: return "No Codex chat assigned"
        }
    }
    func setSelection(_ mode: CodexSelectionMode) {
        var value = settings; value.selection = mode
        guard save(value) else { return }
        if mode == .fixed { history?.stop() }
        else if settings.enabled { refreshHistory() }
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
        guard settings.enabled, settings.selection != .fixed else { return }
        nextHistoryRefresh = now().addingTimeInterval(10)
        history?.refresh()
    }
    func setLighting(_ enabled: Bool) {
        var value = settings; value.lighting = enabled
        if save(value) {
            if !enabled { cancelLightingTest() }
            updateLighting()
        }
    }
    func setLightingArea(_ area: CodexLightingArea) {
        var value = settings; value.lightingArea = area
        if save(value) { updateLighting() }
    }
    func setWaveSpeed(_ speed: CodexWaveSpeed) {
        var value = settings; value.waveSpeed = speed
        if save(value) { updateLighting() }
    }
    func setPulseWhileWorking(_ enabled: Bool) {
        var value = settings; value.pulseWhileWorking = enabled
        if save(value) { updateLighting() }
    }
    func setDarkStatusBackground(_ enabled: Bool) {
        var value = settings; value.darkStatusBackground = enabled
        if save(value) { updateLighting() }
    }
    func startLightingTest() {
        guard settings.enabled, settings.lighting else { return }
        lightingTestStarted = uptime(); lightingTestStage = .working
        updateLighting()
    }
    func cancelLightingTest() {
        guard lightingTestStarted != nil else { return }
        lightingTestStarted = nil; lightingTestStage = nil
        updateLighting()
    }
    private func advanceLightingTest() {
        guard let start = lightingTestStarted else { return }
        let stage = CodexLightingTestStage.at(elapsed: uptime() - start, completionWave: settings.lightingArea == .completionWave)
        if stage != lightingTestStage {
            lightingTestStage = stage
            if stage == nil { lightingTestStarted = nil }
            updateLighting()
        }
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
            pruneSessions()
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
        shuttingDown = true
        timer?.invalidate(); timer = nil
        lightingTestStarted = nil; lightingTestStage = nil
        history?.stop()
        try? FileManager.default.removeItem(at: receiverURL)
        onLightingChange?(nil)
    }
    func activity(_ slot: CodexSlot) -> CodexActivity {
        slot.threadID.flatMap { sessions[$0.lowercased()]?.activity(now: now(), completionDuration:
            settings.lightingArea == .completionWave ? CodexStatusWave.completionWindow : CodexSessionStatus.completionSignalDuration) } ?? .unknown
    }
    func poll() {
        advanceLightingTest()
        if settings.enabled, settings.selection != .fixed, now() >= nextHistoryRefresh { refreshHistory() }
        guard let files = try? FileManager.default.contentsOfDirectory(at: queue, includingPropertiesForKeys: nil) else { return }
        var events: [CodexHookEvent] = []
        for url in files.prefix(256) where url.pathExtension == "json" {
            defer { try? FileManager.default.removeItem(at: url) }
            guard settings.enabled,
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 4096,
                  let data = try? Data(contentsOf: url),
                  let event = try? JSONDecoder().decode(CodexHookEvent.self, from: data), event.validate(now: now()) else { continue }
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
                nextHistoryRefresh = min(nextHistoryRefresh, now().addingTimeInterval(1))
            }
            message = "Connected · latest event: \(event.event). Status is observed activity, not unread state."
        }
        if !events.isEmpty || now().timeIntervalSince(lastExpiryRefresh) >= 30 {
            lastExpiryRefresh = now(); objectWillChange.send()
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
        let activities = displaySlots.map(activity)
        if activities != lastActivities { lastActivities = activities; objectWillChange.send() }
        let color = lightingColor
        let signalID = lightingSignalID
        if settings.darkStatusBackground != lastDarkStatusBackground || settings.pulseWhileWorking != lastPulseWhileWorking || color != lastColor || settings.lightingArea != lastArea || settings.waveSpeed != lastWaveSpeed || allowsCompletionToFinish != lastAllowsCompletionToFinish
            || (color != nil && signalID != lastSignalID) {
            lastColor = color; lastArea = settings.lightingArea; lastSignalID = signalID
            lastAllowsCompletionToFinish = allowsCompletionToFinish
            lastWaveSpeed = settings.waveSpeed
            lastPulseWhileWorking = settings.pulseWhileWorking
            lastDarkStatusBackground = settings.darkStatusBackground
            onLightingChange?(color)
        }
    }
    var allowsCompletionToFinish: Bool {
        !shuttingDown && settings.enabled && settings.lighting && settings.lightingArea == .completionWave && lightingActivity == .idle
    }
    var lightingColor: DialColor? {
        guard settings.enabled, settings.lighting else { return nil }
        let state = lightingActivity
        switch state {
        case .working, .attention, .finished: return state.color
        case .idle, .unknown: return nil
        }
    }
    var lightingActivity: CodexActivity {
        if let stage = lightingTestStage { return stage.activity ?? .idle }
        return CodexActivity.priority(displaySlots.map(activity))
    }
    var lightingSignalID: String? {
        let state = lightingActivity
        guard settings.enabled, settings.lighting, settings.lightingArea == .completionWave,
              [.working, .attention, .finished].contains(state) else { return nil }
        if let start = lightingTestStarted { return "preview:\(start):\(state.rawValue)" }
        let states = displaySlots.filter { activity($0) == state }
            .compactMap { $0.threadID.flatMap { sessions[$0.lowercased()] } }
        if state == .working {
            // Repeated tool hooks keep the same phase; accepting approval starts a new one.
            let phases = states.map { "\($0.latest.sessionID):\($0.workingSince.timeIntervalSinceReferenceDate)" }.sorted()
            return "working:" + phases.joined(separator: "|")
        }
        let event = states.map(\.latest).max { $0.time < $1.time }
        return event.map { "\(state.rawValue):\($0.sessionID):\($0.turnID ?? String($0.time.timeIntervalSinceReferenceDate))" }
    }
    func openSlot(_ number: Int) {
        guard settings.enabled else { message = "Enable the Codex connection first."; return }
        guard let slot = displaySlots.first(where: { $0.id == number }), let url = slot.url else {
            message = "M\(number) has no chat in \(settings.selection.label)."; return
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
