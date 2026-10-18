import AppKit
import Combine
import ErgoCore

final class ChatBridge: ObservableObject {
    let provider: ChatProvider
    private var hookIDs: [String: String] = [:]
    @Published private(set) var catalogSlots: [CodexSlot] = []
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
    private var lastLightingActivity: CodexActivity = .unknown
    private var lastAllowsCompletionToFinish = false
    private var shuttingDown = false
    private var statusResetAt = Date.distantPast
    private var lastArea: CodexLightingArea = .macroColumn
    private var lastWaveSpeed: CodexWaveSpeed = .smooth
    private var lastPulseWhileWorking = false
    private var lastDarkStatusBackground = false
    private var lastSignalID: String?
    private var lastActivities: [CodexActivity] = []
    private var lastLightingCandidates: [ChatLightingCandidate] = []
    private var lastExpiryRefresh = Date.distantPast
    private var nextHistoryRefresh = Date.distantPast
    private let history: CodexHistorySource?
    static func defaultFolder(for provider: ChatProvider) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ErgoControl/\(provider.directory)", isDirectory: true)
    }
    private let folder: URL
    private var queue: URL { folder.appendingPathComponent("events", isDirectory: true) }
    private var settingsURL: URL { folder.appendingPathComponent("settings.json") }
    private var receiverURL: URL { folder.appendingPathComponent("receiver.pid") }
    private var senderURL: URL { folder.appendingPathComponent(provider.executable) }
    private var hooksHome: URL {
        let key = provider == .codex ? "CODEX_HOME" : "CLAUDE_CONFIG_DIR"
        return ProcessInfo.processInfo.environment[key].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(provider == .codex ? ".codex" : ".claude", isDirectory: true)
    }
    var hooksURL: URL { hooksHome.appendingPathComponent(provider == .codex ? "hooks.json" : "settings.json") }
    var needsCatalog: Bool { provider == .claude || settings.selection != .fixed }
    var selectionLabel: String {
        switch settings.selection {
        case .recent: return "Recent \(provider.name) chats"
        case .pinned: return provider == .claude ? "Starred Claude Code chats" : "Pinned Codex chats"
        case .fixed: return "Fixed \(provider.name) assignments"
        }
    }
    func url(for slot: CodexSlot) -> URL? { provider.url(for: slot.threadID) }
    private func statusID(_ slot: CodexSlot) -> String? {
        guard let id = slot.threadID?.lowercased() else { return nil }
        return provider == .codex ? id : hookIDs[id]
    }

    init(provider: ChatProvider = .codex, folder: URL? = nil, startTimer: Bool = true, history: CodexHistorySource? = nil, uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, now: @escaping () -> Date = Date.init) {
        self.provider = provider
        self.now = now
        self.uptime = uptime
        self.folder = folder ?? Self.defaultFolder(for: provider)
        if let history { self.history = history }
        else if startTimer { self.history = provider == .codex ? CodexHistoryReader() as CodexHistorySource : ClaudeHistoryReader() }
        else { self.history = nil }
        message = "Enable the connection, then install the \(provider.name) status hooks."
        do {
            try FileManager.default.createDirectory(at: queue, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: self.folder.path)
            if FileManager.default.fileExists(atPath: settingsURL.path) {
                let saved = try JSONDecoder().decode(CodexSettings.self, from: Data(contentsOf: settingsURL))
                try saved.validate(provider: provider); settings = saved
            }
            try updateReceiver()
        } catch { message = error.localizedDescription }
        if let claude = self.history as? ClaudeHistoryReader {
            claude.catalogFolder = settings.catalogPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
            claude.onRecords = { [weak self] records in self?.receiveClaudeRecords(records) }
        }
        self.history?.onRecent = { [weak self] slots in
            guard let self, self.settings.enabled else { return }
            if self.recentSlots != slots { self.recentSlots = slots }
            if self.settings.selection == .recent && self.historyMessage != "Recent \(self.provider.name) chats synced." {
                self.historyMessage = "Recent \(self.provider.name) chats synced."
            }
            self.updateLighting()
        }
        self.history?.onPinned = { [weak self] slots in
            guard let self, self.settings.enabled else { return }
            if self.pinnedSlots != slots { self.pinnedSlots = slots }
            if self.settings.selection == .pinned {
                self.historyMessage = self.provider == .claude ? "Starred Claude Code chats synced, newest first." : "Pinned Codex chats synced."
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
            message = "Connected to \(provider.name). Status updates arrive from hooks during local desktop activity."
            if needsCatalog { refreshHistory() }
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
            message = "\(provider.name) connection is off."
            cancelLightingTest()
            history?.stop(); sessions = [:]; hookIDs = [:]; catalogSlots = []
            recentSlots = (1...5).map(CodexSlot.init); pinnedSlots = recentSlots
            updateLighting()
        } else {
            message = "Connected to \(provider.name). Status updates arrive from hooks during local desktop activity."
            if needsCatalog { refreshHistory() }
        }
    }
    var displaySlots: [CodexSlot] {
        switch settings.selection {
        case .recent: return recentSlots
        case .pinned: return pinnedSlots
        case .fixed: return settings.slots
        }
    }
    var availableSlotCount: Int { displaySlots.filter { $0.threadID != nil }.count }
    var emptySlotLabel: String {
        switch settings.selection {
        case .recent: return "No other recent \(provider.name) chat"
        case .pinned: return provider == .claude ? "No other starred Claude Code chat" : "No other pinned Codex chat"
        case .fixed: return "No \(provider.name) chat assigned"
        }
    }
    func setSelection(_ mode: CodexSelectionMode) {
        var value = settings; value.selection = mode
        guard save(value) else { return }
        if !needsCatalog { history?.stop() }
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
        return MappingAction(provider.action, String(key - 31))
    }
    func refreshHistory() {
        guard settings.enabled, needsCatalog else { return }
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
    var statusColors: ChatStatusColors { settings.statusColors ?? .defaults(for: provider) }
    func setStatusColor(_ color: DialColor, for activity: CodexActivity) {
        guard [.working, .attention, .finished].contains(activity) else { return }
        var colors = statusColors; colors.set(color, for: activity)
        var value = settings; value.statusColors = colors
        if save(value) { updateLighting() }
    }
    func resetStatusColors() {
        var value = settings; value.statusColors = nil
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
        guard empty || provider.sessionID(from: link) != nil else {
            message = provider == .codex ? "Use a codex://threads/… link or a chat UUID." : "Use a Claude desktop continue link or a local_… desktop session ID."; return
        }
        var value = settings
        value.slots[index].threadID = empty ? nil : provider.sessionID(from: link)
        value.slots[index].name = String(name.prefix(80))
        if save(value) { message = "Slot saved. Empty slots fill from the next observed chats."; updateLighting() }
    }
    func setCatalogFolder(_ folder: URL?) {
        guard provider == .claude else { return }
        var value = settings; value.catalogPath = folder?.path
        guard save(value) else { return }
        history?.stop(); hookIDs = [:]; catalogSlots = []
        recentSlots = (1...5).map(CodexSlot.init); pinnedSlots = recentSlots
        (history as? ClaudeHistoryReader)?.catalogFolder = folder
        updateLighting(); refreshHistory()
    }
    func receiveClaudeRecords(_ records: [ClaudeThreadSummary]) {
        guard provider == .claude, settings.enabled else { return }
        let groups = Dictionary(grouping: records, by: \.id)
        let engineCounts = Dictionary(grouping: records.compactMap(\.hookID), by: { $0 }).mapValues(\.count)
        hookIDs = groups.compactMapValues { rows in
            guard rows.count == 1, let id = rows[0].hookID, engineCounts[id] == 1 else { return nil }
            return id
        }
        catalogSlots = records.sorted {
            $0.lastActivity == $1.lastActivity ? $0.id < $1.id : $0.lastActivity > $1.lastActivity
        }.prefix(100).enumerated().map { index, record in
            var slot = CodexSlot(index + 1); slot.threadID = record.id; slot.name = record.title; return slot
        }
        updateLighting()
    }
    func resetStatus() {
        statusResetAt = now()
        sessions = [:]; cancelLightingTest(); updateLighting()
        message = "Observed status cleared. New hook events will update it again."
    }
    private func save(_ value: CodexSettings) -> Bool {
        do {
            try value.validate(provider: provider)
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
        statusID(slot).flatMap { sessions[$0]?.activity(now: now(), completionDuration:
            settings.lightingArea == .completionWave ? CodexStatusWave.completionWindow : CodexSessionStatus.completionSignalDuration) } ?? .unknown
    }
    func poll() {
        advanceLightingTest()
        if settings.enabled, needsCatalog, now() >= nextHistoryRefresh { refreshHistory() }
        guard let files = try? FileManager.default.contentsOfDirectory(at: queue, includingPropertiesForKeys: nil) else { return }
        var events: [CodexHookEvent] = []
        for url in files.prefix(256) where url.pathExtension == "json" {
            defer { try? FileManager.default.removeItem(at: url) }
            guard settings.enabled,
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 4096,
                  let data = try? Data(contentsOf: url),
                  let event = try? JSONDecoder().decode(CodexHookEvent.self, from: data), event.validate(now: now()),
                  event.time > statusResetAt, provider == .claude || event.event != "IdleNotification" else { continue }
            events.append(event)
        }
        for event in events.sorted(by: { $0.time < $1.time }) {
            if var state = sessions[event.sessionID] { state.receive(event); sessions[event.sessionID] = state }
            else {
                let desktopID = provider == .codex ? event.sessionID : hookIDs.keys.sorted().first { hookIDs[$0] == event.sessionID }
                if settings.selection == .fixed, let desktopID,
                   !settings.slots.contains(where: { $0.threadID?.lowercased() == desktopID }),
                   let index = settings.slots.firstIndex(where: { $0.threadID == nil }) {
                    var value = settings
                    value.slots[index].threadID = desktopID
                    value.slots[index].name = event.project.isEmpty ? "Chat \(index + 1)" : event.project
                    guard save(value) else { continue }
                }
                if settings.selection == .fixed && !settings.slots.contains(where: { statusID($0) == event.sessionID }) { continue }
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
            let fixed = Set(settings.slots.compactMap(statusID))
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
        let state = lightingActivity
        let candidates = lightingCandidates
        if candidates != lastLightingCandidates || (color != nil && state != lastLightingActivity) || settings.darkStatusBackground != lastDarkStatusBackground || settings.pulseWhileWorking != lastPulseWhileWorking || color != lastColor || settings.lightingArea != lastArea || settings.waveSpeed != lastWaveSpeed || allowsCompletionToFinish != lastAllowsCompletionToFinish
            || (color != nil && signalID != lastSignalID) {
            lastColor = color; lastArea = settings.lightingArea; lastSignalID = signalID
            lastLightingActivity = state
            lastAllowsCompletionToFinish = allowsCompletionToFinish
            lastWaveSpeed = settings.waveSpeed
            lastPulseWhileWorking = settings.pulseWhileWorking
            lastDarkStatusBackground = settings.darkStatusBackground
            lastLightingCandidates = candidates
            onLightingChange?(color)
        }
    }
    var lightingCandidates: [ChatLightingCandidate] {
        guard !shuttingDown, settings.enabled, settings.lighting else { return [] }
        let ids = Set(displaySlots.compactMap(statusID))
        return ids.sorted().compactMap { id in
            sessions[id].flatMap { ChatLightingCandidate(provider: provider, session: $0, now: now(),
                completionDuration: settings.lightingArea == .completionWave
                    ? CodexStatusWave.completionWindow : CodexSessionStatus.completionSignalDuration) }
        }
    }
    var lightingChatIDs: Set<String> {
        guard !shuttingDown, settings.enabled, settings.lighting else { return [] }
        return Set(displaySlots.compactMap(statusID).map { "\(provider.rawValue):\($0)" })
    }
    var allowsCompletionToFinish: Bool {
        !shuttingDown && settings.enabled && settings.lighting && settings.lightingArea == .completionWave && lightingActivity == .idle
    }
    var lightingColor: DialColor? {
        guard !shuttingDown, settings.enabled, settings.lighting else { return nil }
        let state = lightingActivity
        switch state {
        case .working, .attention, .finished: return statusColors.color(for: state)
        case .idle, .unknown: return nil
        }
    }
    var lightingActivity: CodexActivity {
        if let stage = lightingTestStage { return stage.activity ?? .idle }
        return CodexActivity.priority(displaySlots.map(activity))
    }
    var lightingSignalID: String? {
        let state = lightingActivity
        guard !shuttingDown, settings.enabled, settings.lighting, settings.lightingArea == .completionWave,
              [.working, .attention, .finished].contains(state) else { return nil }
        if let start = lightingTestStarted { return "preview:\(start):\(state.rawValue)" }
        let states = displaySlots.filter { activity($0) == state }
            .compactMap { statusID($0).flatMap { sessions[$0] } }
        if state == .working {
            // Repeated tool hooks keep the same phase; accepting approval starts a new one.
            let phases = states.map { "\($0.latest.sessionID):\($0.workingSince.timeIntervalSinceReferenceDate)" }.sorted()
            return "working:" + phases.joined(separator: "|")
        }
        let event = states.map(\.latest).max { $0.time < $1.time }
        return event.map { "\(state.rawValue):\($0.sessionID):\($0.turnID ?? String($0.time.timeIntervalSinceReferenceDate))" }
    }
    func openSlot(_ number: Int) {
        guard settings.enabled else { message = "Enable the \(provider.name) connection first."; return }
        guard let slot = displaySlots.first(where: { $0.id == number }), let url = url(for: slot) else {
            message = "Slot \(number) has no chat in \(selectionLabel)."; return
        }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: provider.bundleID) else {
            message = "\(provider.name) desktop could not be found."; return
        }
        let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration) { [weak self] _, error in
            if let error { DispatchQueue.main.async { self?.message = "Could not open chat: \(error.localizedDescription)" } }
        }
    }
    func installHooks(remove: Bool = false) {
        do {
            let fm = FileManager.default
            guard let bundled = Bundle.main.url(forResource: provider.executable, withExtension: nil) else {
                throw CodexIntegrationError.message("The bundled \(provider.name) hook sender is missing. Rebuild Ergo Control.")
            }
            let existing = fm.fileExists(atPath: hooksURL.path) ? try Data(contentsOf: hooksURL) : nil
            let data = try CodexHookConfiguration.updating(existing, executable: senderURL.path, install: !remove, provider: provider)
            try fm.createDirectory(at: hooksHome, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if let existing {
                let backup = hooksHome.appendingPathComponent("\(hooksURL.lastPathComponent).ergo-backup-\(UUID().uuidString)")
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
                : provider == .codex ? "Hooks installed. Review and trust ErgoCodexHook if ChatGPT asks, then start a desktop turn. If already accepted, no further review is needed."
                    : "Hooks installed. Start a new local Claude Code session to load them. Your existing hooks and permission rules were preserved."
        } catch { message = error.localizedDescription }
    }
}
