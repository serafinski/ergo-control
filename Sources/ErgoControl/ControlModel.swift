import AppKit
import Combine
import ApplicationServices
import IOKit.hid
import ErgoCore
import ErgoDevice

final class ControlModel: ObservableObject {
    @Published var configuration = MappingConfiguration()
    @Published var selectedProfileID: UUID
    @Published var alternateEditing = false
    @Published var selectedControl = "extra:32"
    @Published var status = "Mappings are off. Configure your controls, then enable them."
    @Published var running = false
    @Published var preparing = false
    @Published private(set) var waitingForAutomaticStart = false
    @Published var activeProfileName = "Default"
    @Published var dialName = "Zoom"
    @Published var lastControl = "No control pressed yet"
    @Published var error: String?
    @Published var dirty = false
    @Published var focusedMediaPlayback = UserDefaults.standard.bool(forKey: "focusedMediaPlaybackEnabled") {
        didSet {
            UserDefaults.standard.set(focusedMediaPlayback, forKey: "focusedMediaPlaybackEnabled")
            configureMediaRouting()
        }
    }
    @Published private(set) var musicFallbackNotice: String?
    @Published var musicFallbackApplication = MusicFallbackApplication(savedValue: UserDefaults.standard.string(forKey: "musicFallbackApplication")) {
        didSet {
            musicFallbackNotice = nil
            UserDefaults.standard.set(musicFallbackApplication.rawValue, forKey: "musicFallbackApplication")
            configureMediaRouting()
        }
    }
    @Published var inputAccessMode: InputAccessMode?
    let bluetooth = BluetoothController(liveDiagnostics: false)
    let fullControlHelper = FullControlHelper()
    let codex = ChatBridge()
    let claude = ChatBridge(provider: .claude)
    let chatPreferences = ChatPreferences()
    private lazy var chatLighting = ChatLightingController(codex: codex, claude: claude)
    private var chatCompletionTimer: Timer?
    @Published private(set) var chatLightingStatus = "No active chat signal"
    var chat: ChatBridge { chatBridge(for: chatPreferences.provider) }
    func chatBridge(for provider: ChatProvider) -> ChatBridge { provider == .codex ? codex : claude }
    func macroAssignments(alternateLayer: Bool) -> [MacroKeyAssignment] {
        MappingResolver.macroKeys(profile: activeProfile, alternateLayer: alternateLayer, fallback: chat.defaultAction)
    }
    let startup = StartupSettings()
    lazy var lightingAutomation = LightingAutomation(device: bluetooth)
    let logs = AppLog()
    private var lastPointerNote: String?
    private var lastVendorNote: String?
    private var automaticStart = AutomaticMappingStart()
    private var reconnectPolicy = MappingReconnectPolicy()
    private var automaticStartTimer: Timer?
    private var resumeAfterWake = false
    private let relay = KeyboardRelay()
    private let engine = ActionEngine()
    private let mediaController = FocusedMediaController()
    private let musicFallback = MusicFallbackController()
    private let controlIndicator = ControlIndicator()
    private var batteryPopupTicket: UUID?
    private var batterySchedule = BatteryRefreshSchedule()
    private var batteryTimer: Timer?
    private var terminating = false
    private var subscriptions = Set<AnyCancellable>()
    private var timer: Timer?
    private var stageStarted = Date()
    private var activationStarted = false
    private var batteryRequested = false
    private var relayOpened = false
    private var ordinary: Set<UInt8> = []
    private var keyActions: [UInt8: MappingAction] = [:]
    private var extraActions: [UInt8: MappingAction] = [:]
    private var mediaActions: [UInt16: MappingAction] = [:]
    private var consumer = MediaInputState()
    private var mediaReleaseTimer: Timer?
    private var extraDecoder = ExtraKeyDecoder()
    private var layerKeys: Set<String> = []
    private var modeIndices: [UUID: Int] = [:]
    private var frontmostID: String?
    private var tick = 0
    private var sessionDeadline: Date?

    static var settingsURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ErgoControl/Settings/profiles.json")
    }

    init() {
        let defaults = MappingConfiguration()
        configuration = defaults
        selectedProfileID = defaults.profiles[0].id
        if let data = try? Data(contentsOf: Self.settingsURL) {
            do {
                let saved = try JSONDecoder().decode(MappingConfiguration.self, from: data)
                guard saved.schema == 2, !saved.profiles.isEmpty,
                      Set(saved.profiles.map(\.id)).count == saved.profiles.count else { throw MappingValidationError.message("Unsupported settings format") }
                configuration = saved; selectedProfileID = saved.manualProfileID
            } catch { self.error = "Saved settings could not be loaded. The original file has been preserved." }
        }
        frontmostID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        bluetooth.objectWillChange
            .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        fullControlHelper.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        claude.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        chatPreferences.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        codex.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        lightingAutomation.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        startup.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        startup.$automaticMappings.dropFirst().sink { [weak self] enabled in
            if !enabled { self?.cancelAutomaticStart() }
        }.store(in: &subscriptions)
        codex.onLightingChange = { [weak self] _ in
            self?.updateChatLighting()
        }
        claude.onLightingChange = { [weak self] _ in
            self?.updateChatLighting()
        }
        bluetooth.onMacroStatusCompletion = { [weak self] id in
            DispatchQueue.main.async {
                guard let self, self.running, self.chatLighting.completeWave(id) else { return }
                self.updateChatLighting()
            }
        }
        $configuration.dropFirst().sink { [weak self] _ in
            self?.dirty = true
            DispatchQueue.main.async { self?.updateProfile() }
        }.store(in: &subscriptions)
        relay.onReport = { [weak self] id, bytes in self?.receive(id, bytes) }
        relay.onDisconnect = { [weak self] in self?.keyboardDisconnected() }
        relay.onFailure = { [weak self] message in self?.stop(message, level: .error) }
        engine.onError = { [weak self] message in self?.error = message; self?.stop(message, level: .error) }
        engine.onNativeMedia = { [weak self] usage, pressed in
            guard pressed else { return }
            self?.logs.record("\(Self.mediaLabel(usage)) event posted to macOS.", category: "Media")
        }
        mediaController.onRoute = { [weak self] message in self?.logs.record(message, category: "Media") }
        mediaController.onNotice = { [weak self] message in
            self?.error = message; self?.logs.record(message, category: "Media", level: .warning)
        }
        mediaController.onSystemPlayback = { [weak self] command in
            let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
            self?.musicFallback.perform(command, stillCurrent: { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid })
        }
        musicFallback.onRoute = { [weak self] message in
            self?.musicFallbackNotice = nil; self?.logs.record(message, category: "Media")
        }
        musicFallback.onNotice = { [weak self] message in
            self?.musicFallbackNotice = message; self?.logs.record(message, category: "Media", level: .warning)
        }
        engine.onNotice = { [weak self] message in self?.error = message }
        engine.onCapsLockChange = { [weak self] enabled in
            self?.relay.setCapsLock(enabled) { [weak self] result in
                if result != 0 { self?.logs.record("Caps Lock indicator unavailable (\(result)); mappings remain active", category: "Keyboard", level: .warning) }
            }
        }
        engine.onCycle = { [weak self] in self?.cycleDial() }
        engine.onBrightness = { [weak self] direction in self?.bluetooth.adjustKeyboardBrightness(direction) }
        engine.onBattery = { [weak self] in self?.showBattery() }
        engine.onClaudeSlot = { [weak self] number in self?.claude.openSlot(number) }
        engine.onCodexSlot = { [weak self] number in self?.codex.openSlot(number) }
        bluetooth.$lightingStatus.removeDuplicates().sink { [weak self] message in
            guard !message.isEmpty else { return }
            self?.logs.record(message, category: "Lighting", level: message.contains("unavailable") ? .warning : .info)
        }.store(in: &subscriptions)
        bluetooth.$macroStatusLightingMessage.removeDuplicates().sink { [weak self] message in
            let value = message.lowercased()
            if ["unavailable", "pending", "invalid", "could not"].contains(where: value.contains) {
                self?.logs.record(message, category: "Chat lighting", level: .warning)
            }
        }.store(in: &subscriptions)
        bluetooth.$restoreOwed.removeDuplicates().dropFirst().sink { [weak self] pending in
            if !pending { self?.logs.record("Keyboard restoration completed and verified.", category: "Keyboard") }
        }.store(in: &subscriptions)
        codex.$settings.map(\.enabled).removeDuplicates().dropFirst().sink { [weak self] enabled in
            self?.logs.record(enabled ? "Codex connection enabled." : "Codex connection disabled.", category: "Codex")
        }.store(in: &subscriptions)
        bluetooth.$keyboardBrightnessPercent.dropFirst().sink { [weak self] percent in
            guard let self, self.running, let percent else { return }
            self.controlIndicator.showBrightness(percent)
        }.store(in: &subscriptions)
        bluetooth.$batteryReadState.sink { [weak self] state in
            guard let self, let ticket = self.batteryPopupTicket else { return }
            switch state {
            case .ready, .failed:
                self.controlIndicator.updateBattery(state, for: ticket)
                self.batteryPopupTicket = nil
            case .idle, .reading: break
            }
        }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification).sink { [weak self] note in
            self?.frontmostID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            self?.updateProfile()
            self?.mediaController.focusChanged()
        }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification).sink { [weak self] _ in
            guard let self else { return }
            self.resumeAfterWake = self.running || self.preparing || self.waitingForAutomaticStart
            self.stop("Mappings stopped for sleep.")
        }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification).sink { [weak self] _ in
            guard let self else { return }
            if self.resumeAfterWake && self.startup.automaticMappings { self.beginAutomaticStart() }
            self.resumeAfterWake = false
        }.store(in: &subscriptions)
        bluetooth.$driverModeVerified.removeDuplicates().sink { [weak self] verified in
            guard let self else { return }
            if verified && self.preparing && self.relayOpened {
                self.running = true; self.preparing = false
                self.reconnectPolicy.activated(timed: self.sessionDeadline != nil)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.running else { return }
                    self.updateProfile()
                    self.updateChatLighting()
                }
                self.status = self.inputAccessMode == .macroButtons
                    ? "Macro buttons active · M1–M5, AI, left click and battery. Dial and ordinary-key remaps are unavailable."
                    : "Mappings active · PT Ergo only"
                self.logs.record(self.status, category: "Keyboard")
            } else if !verified && self.running {
                if !self.bluetooth.ready { self.keyboardDisconnected() }
                else { self.stop("Keyboard driver mode could not be verified. Mappings stopped safely.", level: .warning) }
            }
        }.store(in: &subscriptions)
        updateProfile()
        logs.record("Ergo Control \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development") started.")
        let batteryTimer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.pollBattery() }
        self.batteryTimer = batteryTimer
        RunLoop.main.add(batteryTimer, forMode: .common)
        DispatchQueue.main.async { [weak self] in
            self?.pollBattery()
            if self?.startup.automaticMappings == true { self?.beginAutomaticStart() }
        }
    }

    private func cancelAutomaticStart() {
        waitingForAutomaticStart = false
        automaticStart.cancel()
        automaticStartTimer?.invalidate(); automaticStartTimer = nil
    }
    private func keyboardDisconnected() {
        switch reconnectPolicy.connectionLost(running: running, preparing: preparing,
                                               automatic: startup.automaticMappings, terminating: terminating) {
        case .ignore: return
        case .stop:
            stop("PT Ergo disconnected. Mappings stopped; enable them again when the keyboard is ready.", level: .warning)
        case .resume:
            stop("PT Ergo disconnected. Saved mappings will resume automatically after reconnection and restoration.", level: .warning)
            batterySchedule.refresh()
            beginAutomaticStart()
            pollBattery()
        }
    }
    private func beginAutomaticStart() {
        guard !terminating, !running, !preparing, error == nil else { return }
        cancelAutomaticStart()
        automaticStart.arm()
        waitingForAutomaticStart = true
        status = "Waiting for PT Ergo and input permissions to start saved mappings…"
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.advanceAutomaticStart() }
        automaticStartTimer = timer; RunLoop.main.add(timer, forMode: .common)
        advanceAutomaticStart()
    }
    private func advanceAutomaticStart() {
        guard !terminating, startup.automaticMappings else { cancelAutomaticStart(); return }
        if fullControlHelper.needsStartupRepair {
            cancelAutomaticStart(); status = fullControlHelper.status; return
        }
        let permissionsReady = accessibilityGranted && inputGranted
        switch automaticStart.next(ready: bluetooth.ready,
                                   permissions: permissionsReady,
                                   busy: bluetooth.busy || fullControlHelper.checkingPermission,
                                   restorationPending: bluetooth.restoreOwed || bluetooth.driverModeVerified) {
        case .wait:
            let message: String
            if !permissionsReady {
                message = "Waiting for Input Monitoring and Accessibility. Saved mappings will start when permissions and the keyboard are ready."
            } else if !bluetooth.ready {
                message = "Waiting for PT Ergo to connect. Saved mappings will start automatically; Stop mappings cancels."
            } else if bluetooth.restoreOwed || bluetooth.driverModeVerified {
                message = "Restoring the keyboard's saved mode before starting mappings…"
            } else if fullControlHelper.checkingPermission {
                message = "Waiting for the helper permission check before starting mappings…"
            } else {
                message = "Waiting for the keyboard's current operation to finish before starting mappings…"
            }
            if status != message { status = message; logs.record(message, category: "Startup") }
        case .start: cancelAutomaticStart(); start()
        }
    }

    var accessibilityGranted: Bool { AXIsProcessTrusted() }
    var inputGranted: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent).rawValue == 0 }
    var profileIndex: Int { configuration.profiles.firstIndex(where: { $0.id == selectedProfileID }) ?? 0 }
    var activeProfile: MappingProfile { configuration.profile(for: frontmostID) }
    var layerActive: Bool { !layerKeys.isEmpty }
    var menuBarBatteryLabel: String {
        guard bluetooth.ready, let percent = bluetooth.batteryPercent else { return "—%" }
        return "\(percent)%"
    }

    func refreshBattery() {
        batterySchedule.refresh()
        pollBattery()
    }
    private func showBattery() {
        batteryPopupTicket = controlIndicator.requestBattery()
        // Share an in-flight read. Otherwise request one as soon as the serial
        // configuration channel is idle, rather than dropping a busy-button press.
        if bluetooth.batteryReadState != .reading { refreshBattery() }
    }
    private func pollBattery() {
        guard !terminating else { return }
        switch batterySchedule.next(at: ProcessInfo.processInfo.systemUptime, ready: bluetooth.ready,
                                    busy: bluetooth.busy, preparingMappings: preparing,
                                    restorationOwed: bluetooth.restoreOwed, driverModeVerified: bluetooth.driverModeVerified,
                                    automaticStartPending: waitingForAutomaticStart) {
        case .connect: bluetooth.connect()
        case .read: bluetooth.readBattery()
        case nil: break
        }
    }

    func enableFullControl() {
        stop()
        do { try fullControlHelper.register(); inputAccessMode = nil; status = fullControlHelper.status }
        catch { self.error = "Could not enable the input helper: " + error.localizedDescription }
    }
    func removeFullControl() {
        stop()
        do { try fullControlHelper.unregister(); inputAccessMode = nil; status = fullControlHelper.status }
        catch { self.error = "Could not remove the input helper: " + error.localizedDescription }
    }

    func save() {
        do {
            try validate()
            let url = Self.settingsURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let old = try? Data(contentsOf: url) { try old.write(to: url.appendingPathExtension("backup"), options: .atomic) }
            try encoder.encode(configuration).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            let backup = url.appendingPathExtension("backup")
            if FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path) }
            dirty = false; error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func validate() throws {
        if configuration.functionKeys.dictation == .fluidVoice {
            _ = try DictationTrigger(configuration.functionKeys.fluidVoiceShortcut)
        }
        for profile in configuration.profiles {
            for action in Array(profile.mappings.values) + Array(profile.alternate.values) + profile.dialModes.flatMap({ [$0.clockwise, $0.counterclockwise] }) {
                switch action.kind {
                case .shortcut: _ = try KeyChord(action.value)
                case .macro: _ = try MacroStep.parse(action.value)
                case .application, .toggleApplication: guard action.value.hasSuffix(".app") else { throw MappingValidationError.message("Choose an application for \(action.kind.rawValue)") }
                case .script: guard FileManager.default.fileExists(atPath: action.value) else { throw MappingValidationError.message("Choose an existing script") }
                case .keyboardBrightness: guard action.value == "up" || action.value == "down" else { throw MappingValidationError.message("Choose Increase or Decrease for keyboard brightness") }
                case .text: guard action.value.utf16.count <= 4096 else { throw MappingValidationError.message("Text actions can contain up to 4096 characters") }
                case .codexChat, .claudeChat: guard let slot = Int(action.value), (1...5).contains(slot) else { throw MappingValidationError.message("Choose a chat slot from 1 to 5") }
                default: break
                }
            }
        }
    }
    func addProfile() {
        let profile = MappingProfile(name: "New profile")
        configuration.profiles.append(profile); selectedProfileID = profile.id
    }
    func setChatProvider(_ provider: ChatProvider) {
        guard provider != chatPreferences.provider else { return }
        _ = chatPreferences.select(provider)
    }
    func setChatLightingMode(_ mode: ChatLightingMode) {
        guard mode != chatPreferences.lightingMode else { return }
        codex.cancelLightingTest(); claude.cancelLightingTest()
        guard chatPreferences.selectLighting(mode) else { return }
        // Explicitly release the old provider before repainting, including a
        // one-shot completion that would otherwise be allowed to finish.
        bluetooth.setMacroStatusColor(nil)
        chatLighting.reset()
        updateChatLighting()
    }
    func startChatLightingTest(_ provider: ChatProvider) {
        guard running, chatPreferences.lightingMode.includes(provider) else { return }
        codex.cancelLightingTest(); claude.cancelLightingTest()
        chatBridge(for: provider).startLightingTest()
    }
    private func updateChatLighting() {
        chatCompletionTimer?.invalidate(); chatCompletionTimer = nil
        guard running else {
            chatLighting.reset(); chatLightingStatus = "Mappings are off"
            bluetooth.setMacroStatusColor(nil)
            return
        }
        let output = chatLighting.output(mode: chatPreferences.lightingMode)
        let status = output.provider.map { "\($0.name) · \(output.activity.label)" } ?? "No active chat signal"
        if chatLightingStatus != status { chatLightingStatus = status }
        bluetooth.setMacroStatusColor(output.color, area: output.area,
            signalID: output.signalID, activity: output.activity,
            allowCompletionToFinish: output.allowCompletionToFinish, speed: output.speed,
            pulseWhileWorking: output.pulseWhileWorking, darkBackground: output.darkBackground)
        if let delay = output.refreshAfter {
            let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.updateChatLighting() }
            chatCompletionTimer = timer; RunLoop.main.add(timer, forMode: .common)
        }
    }
    func createChatProfile(_ provider: ChatProvider) {
        if let existing = configuration.profiles.first(where: { p in
            (1...5).allSatisfy { p.mappings["extra:\($0 + 31)"] == MappingAction(provider.action, String($0)) }
        }) { selectedProfileID = existing.id; return }
        var profile = MappingProfile(name: "\(provider.name) chat keys")
        for slot in 1...5 { profile.mappings["extra:\(slot + 31)"] = MappingAction(provider.action, String(slot)) }
        configuration.profiles.append(profile)
        selectedProfileID = profile.id
        // A dedicated profile can open the selected chat source from anywhere. Existing profiles
        // remain untouched; selecting the new default is explicit in the UI.
        save()
    }
    func duplicateProfile() {
        var profile = configuration.profiles[profileIndex]; profile.id = UUID(); profile.name += " copy"
        profile.applicationIDs = []; configuration.profiles.append(profile); selectedProfileID = profile.id
    }
    func removeProfile() {
        guard configuration.profiles.count > 1 else { return }
        configuration.profiles.remove(at: profileIndex); selectedProfileID = configuration.profiles[0].id
        if !configuration.profiles.contains(where: { $0.id == configuration.manualProfileID }) { configuration.manualProfileID = selectedProfileID }
    }
    func useSelectedProfile() { configuration.manualProfileID = selectedProfileID; updateProfile() }
    func addApplication() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowedContentTypes = [.applicationBundle]
        if panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url), let id = bundle.bundleIdentifier {
            for i in configuration.profiles.indices { configuration.profiles[i].applicationIDs.removeAll { $0 == id } }
            configuration.profiles[profileIndex].applicationIDs.append(id)
        }
    }
    private func updateProfile() {
        engine.endAppSwitcher()
        engine.functionKeys = configuration.functionKeys
        activeProfileName = activeProfile.name
        let modes = activeProfile.dialModes.filter(\.enabled)
        let index = modeIndices[activeProfile.id, default: 0]
        let mode = modes.isEmpty ? nil : modes[index % modes.count]
        dialName = mode?.name ?? "No enabled dial modes"
    }
    private func cycleDial() {
        guard inputAccessMode != .macroButtons else { status = "Custom dial modes need full keyboard control, which macOS denied."; return }
        let id = activeProfile.id
        let count = activeProfile.dialModes.filter(\.enabled).count
        guard count > 0 else { return }
        let backwards = engine.physicalModifiers & 0x22 != 0
        modeIndices[id] = (modeIndices[id, default: 0] + (backwards ? count - 1 : 1)) % count
        updateProfile()
        logs.record("Command dial: \(dialName)", category: "Keyboard")
        controlIndicator.showDial(mode: dialName, profile: activeProfileName)
    }

    func start(testSeconds: TimeInterval? = nil) {
        cancelAutomaticStart()
        guard !running, !preparing else { return }
        guard !fullControlHelper.checkingPermission else { status = "Wait for the helper permission check to finish."; return }
        error = nil
        lastPointerNote = nil
        logs.record("Mapping activation requested.", category: "Keyboard")
        defer {
            if !preparing && !running { logs.record(error ?? status, category: "Keyboard", level: .warning) }
        }
        fullControlHelper.refresh()
        guard !fullControlHelper.needsStartupRepair else { status = fullControlHelper.status; return }
        guard accessibilityGranted, inputGranted else { status = "Enable Input Monitoring and Accessibility for Ergo Control, then try again."; return }
        let conflicts = NSWorkspace.shared.runningApplications.filter {
            ["dev.local.ergocontrol.probe", "dev.local.ergocontrol.bluetooth", "com.razer.synapse", "com.razer.appengine.app"].contains($0.bundleIdentifier ?? "")
        }
        guard conflicts.isEmpty else {
            status = "Quit \(conflicts.compactMap(\.localizedName).joined(separator: ", ")) before enabling mappings."
            return
        }
        do { try validate() } catch { self.error = error.localizedDescription; return }
        if dirty { save(); if error != nil { return } }
        preparing = true; stageStarted = Date(); activationStarted = false; batteryRequested = false
        sessionDeadline = testSeconds.map { Date().addingTimeInterval($0) }
        extraDecoder = ExtraKeyDecoder(); ordinary.removeAll(); keyActions.removeAll(); extraActions.removeAll(); mediaActions.removeAll(); layerKeys.removeAll(); consumer = MediaInputState()
        status = "Connecting to PT Ergo…"; bluetooth.connect()
        timer?.invalidate()
        timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.advance() }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    private func advance() {
        tick += 1
        if running {
            if let deadline = sessionDeadline, Date() >= deadline { stop("Test finished. Mappings stopped and normal-mode restoration requested."); return }
            if tick % 20 == 0 { bluetooth.renewMappingLease() }
            return
        }
        guard preparing else { return }
        if Date().timeIntervalSince(stageStarted) > 30 { stop("Could not activate mappings. " + bluetooth.status, level: .error); return }
        guard bluetooth.ready, !bluetooth.busy else { return }
        if bluetooth.canTryDriverMode, !activationStarted {
            if !batteryRequested { batteryRequested = true; bluetooth.readBattery(); return }
            activationStarted = true; relayOpened = true
            configureMediaRouting()
            // Forward ordinary input immediately, including during the helper's asynchronous open.
            inputAccessMode = fullControlHelper.enabled ? .fullKeyboard : nil
            relay.start(usingHelper: fullControlHelper.enabled) { [weak self] result in
                guard let self, self.preparing, self.activationStarted else { return }
                switch result {
                case .success(let mode):
                    self.inputAccessMode = mode; self.engine.synchronizeCapsLock(); self.bluetooth.tryDriverMode()
                case .failure(let error): self.stop(error.localizedDescription, level: .error)
                }
            }
        }
    }
    func stop(_ message: String = "Mappings off · normal keyboard mode restored when verified", level: AppLog.Level = .info) {
        logs.record(message, category: "Keyboard", level: level)
        cancelAutomaticStart()
        reconnectPolicy.cancel()
        bluetooth.setMacroStatusColor(nil)
        batteryPopupTicket = nil
        controlIndicator.dismiss()
        preparing = false; running = false; timer?.invalidate(); timer = nil
        chatCompletionTimer?.invalidate(); chatCompletionTimer = nil; chatLighting.reset()
        chatLightingStatus = "Mappings are off"
        codex.cancelLightingTest(); claude.cancelLightingTest()
        sessionDeadline = nil
        mediaController.stop()
        musicFallback.stop()
        relay.stop(); relayOpened = false; engine.stop()
        mediaReleaseTimer?.invalidate(); mediaReleaseTimer = nil; consumer = MediaInputState()
        ordinary.removeAll(); keyActions.removeAll(); extraActions.removeAll(); mediaActions.removeAll(); layerKeys.removeAll()
        bluetooth.restore(); status = message
    }
    func terminate() -> NSApplication.TerminateReply {
        terminating = true
        lightingAutomation.stop()
        codex.shutdown(); claude.shutdown()
        batteryTimer?.invalidate(); batteryTimer = nil
        stop()
        logs.flush()
        return bluetooth.requestTermination()
    }

    private func action(for control: String) -> MappingAction {
        let profile = activeProfile
        let resolved = MappingResolver.resolve(control, profile: profile, alternateLayer: layerActive,
                                               fallback: chat.defaultAction(for: control))
        if resolved.action.kind != .standard { return resolved.action }
        if control == "extra:96" { return MappingAction(.cycleDial) }
        if control == "extra:65" { return MappingAction(.battery) }
        if control == "leftCW" || control == "leftCCW" {
            let modes = profile.dialModes.filter(\.enabled)
            guard !modes.isEmpty else { return MappingAction(.disabled) }
            let mode = modes[modeIndices[profile.id, default: 0] % modes.count]
            return control == "leftCW" ? mode.clockwise : mode.counterclockwise
        }
        return MappingAction()
    }
    private func execute(_ action: MappingAction, control: String, pressed: Bool) {
        lightingAutomation.userActivity()
        if action.kind == .layer {
            engine.endAppSwitcher()
            if pressed != layerKeys.contains(control) { objectWillChange.send() }
            if pressed { layerKeys.insert(control) } else { layerKeys.remove(control) }
        } else if pressed { engine.perform(action, fromDial: ["leftCW", "leftCCW", "rightCW", "rightCCW"].contains(control)) }
    }
    private func receive(_ id: UInt32, _ data: Data) {
        guard relay.accessMode.accepts(reportID: id) else { return }
        let bytes = Array(data)
        guard id <= 255, bytes.first == UInt8(id) else { stop("Unexpected keyboard packet; normal input has been returned.", level: .error); return }
        if id == 1 {
            guard bytes.count == 12 else { stop("Unexpected keyboard packet size; mappings stopped.", level: .error); return }
            guard let snapshot = KeyboardSnapshot(data) else { return }
            let current = snapshot.held
            guard current.allSatisfy({ MacKeys.codes[$0] != nil }) else {
                stop("This key needs support; PT Ergo has been returned to normal input.", level: .error); return
            }
            let transitions = NativeKeyboardTransitions.changes(from: ordinary, to: current)
            if !transitions.isEmpty { lightingAutomation.userActivity(); engine.endAppSwitcher() }
            for transition in transitions {
                guard relayOpened else { return }
                let usage = transition.usage
                engine.physicalModifiers = transition.modifiers
                let mapping: MappingAction
                if transition.pressed {
                    if (58...69).contains(usage) { lastControl = ControlCatalog.label("key:\(usage)") }
                    mapping = running ? action(for: "key:\(usage)") : MappingAction()
                    keyActions[usage] = mapping
                } else { mapping = keyActions.removeValue(forKey: usage) ?? MappingAction() }
                if mapping.kind == .standard { engine.relay(usage, pressed: transition.pressed) }
                else { execute(mapping, control: "key:\(usage)", pressed: transition.pressed) }
            }
            engine.physicalModifiers = snapshot.modifiers
            ordinary = current
        } else if id == 5 {
            guard let events = extraDecoder.decode(reportID: id, bytes: data, at: ProcessInfo.processInfo.systemUptime) else { stop("Unexpected extra-key packet; mappings stopped.", level: .error); return }
            guard running || relayOpened && relay.accessMode == .fullKeyboard else { return }
            if !events.isEmpty { lightingAutomation.userActivity() }
            for event in events {
                guard relayOpened else { return }
                if DriverMediaControls.usage(forExtraKey: event.key) != nil, relay.accessMode == .fullKeyboard {
                    forwardExtraMedia([event]); continue
                }
                let control = "extra:\(event.key)"
                if event.pressed { lastControl = ControlCatalog.label(control); extraActions[event.key] = running ? action(for: control) : MappingAction() }
                let mapping = extraActions[event.key] ?? MappingAction()
                if mapping.kind == .standard, relay.accessMode == .fullKeyboard,
                   let usage = NativeExtraKeys.usage(for: event.key) {
                    engine.relay(usage, pressed: event.pressed, owner: control)
                } else { execute(mapping, control: control, pressed: event.pressed) }
                if !event.pressed { extraActions.removeValue(forKey: event.key) }
            }
            scheduleMediaRelease()
        } else if id == 2 {
            guard let pointer = KeyboardPointerReport(data) else {
                stop("Malformed PT Ergo pointer report (id \(id), \(bytes.count) bytes); mappings stopped.", level: .error); return
            }
            if pointer.hasAuxiliaryInput {
                let note = "Auxiliary PT Ergo pointer fields ignored; dial mapping continues (buttons \(pointer.buttons), movement \(pointer.deltaX != 0 || pointer.deltaY != 0))."
                if note != lastPointerNote { logs.record(note, category: "Keyboard"); lastPointerNote = note }
            }
            guard running else { return }
            let steps = pointer.horizontalPan
            if steps != 0 {
                lightingAutomation.userActivity()
                let control = steps > 0 ? "leftCW" : "leftCCW"
                lastControl = ControlCatalog.label(control)
                for _ in 0..<min(32, abs(steps)) { engine.perform(action(for: control), fromDial: true) }
            }
            if pointer.verticalWheel != 0 {
                let events = consumer.accept(DriverMediaControls.wheelEvents(pointer.verticalWheel), source: .wheel,
                                             at: ProcessInfo.processInfo.systemUptime)
                forwardMedia(events, source: "right-roller wheel")
            }
        } else if id == 3 {
            guard let events = consumer.decode(data, at: ProcessInfo.processInfo.systemUptime) else {
                stop("Unexpected media packet; mappings stopped.", level: .error); return
            }
            forwardMedia(events)
            scheduleMediaRelease()
        } else if id == 6 {
            // Report 6 multiplexes driver media records and notifications.
            // Only the strict logical-record-2 shape enters media delivery.
            guard DriverMediaRecord(data) != nil else {
                if bytes.count > 1, bytes[1] != 5 {
                    let note = "Unrecognized vendor input record \(bytes[1]) (\(bytes.count) bytes); no media command generated."
                    if note != lastVendorNote { logs.record(note, category: "Media", level: .warning); lastVendorNote = note }
                }
                return
            }
            guard let events = consumer.decode(data, at: ProcessInfo.processInfo.systemUptime) else { return }
            forwardMedia(events, source: "driver media record")
            scheduleMediaRelease()
        }
        else { stop("This input report needs support (\(id)); mappings stopped.", level: .error) }
    }

    private func forwardExtraMedia(_ events: [ExtraKeyEvent]) {
        let media = events.compactMap { event -> ConsumerKeyEvent? in
            DriverMediaControls.usage(forExtraKey: event.key).map { ConsumerKeyEvent($0, pressed: event.pressed) }
        }
        forwardMedia(consumer.accept(media, source: .extraKey, at: ProcessInfo.processInfo.systemUptime), source: "driver extra-key record")
    }

    private func configureMediaRouting() {
        mediaController.stop()
        musicFallback.stop()
        engine.onPlayback = nil
        guard relayOpened else { return }
        musicFallback.start(preferred: musicFallbackApplication)
        if focusedMediaPlayback {
            mediaController.start()
            engine.onPlayback = { [weak self] command in self?.mediaController.perform(command) }
        } else if musicFallbackApplication != .system {
            engine.onPlayback = { [weak self] command in self?.musicFallback.perform(command) }
        }
    }
    private static func mediaLabel(_ usage: UInt16) -> String {
        switch usage {
        case 0xe9: return "Volume up"
        case 0xea: return "Volume down"
        case 0xe2: return "Mute"
        case 0xcd: return "Play / pause"
        case 0xb5: return "Next track"
        case 0xb6: return "Previous track"
        case 0x6f: return "Display brightness up"
        case 0x70: return "Display brightness down"
        default: return "Media control \(usage)"
        }
    }

    private func forwardMedia(_ events: [ConsumerKeyEvent], source: String = "native consumer report") {
        let controls: [UInt16: String] = [0xe9:"rightCW",0xea:"rightCCW",0xe2:"rightClick",0xcd:"mediaSingle",0xb5:"mediaDouble",0xb6:"mediaTriple"]
        if !events.isEmpty { lightingAutomation.userActivity() }
        for event in events {
            guard relayOpened else { return }
            let control = controls[event.usage] ?? "media:\(event.usage)"
            let mapping: MappingAction
            if event.pressed {
                logs.record("\(Self.mediaLabel(event.usage)) received from PT Ergo (\(source)).", category: "Media")
                mapping = running ? action(for: control) : MappingAction()
                mediaActions[event.usage] = mapping; lastControl = ControlCatalog.label(control)
            } else { mapping = mediaActions.removeValue(forKey: event.usage) ?? MappingAction() }
            if mapping.kind == .standard {
                guard engine.media(event.usage, pressed: event.pressed) else {
                    stop("This media key needs support (\(event.usage)); mappings stopped."); return
                }
            } else { execute(mapping, control: control, pressed: event.pressed) }
        }
    }

    private func scheduleMediaRelease() {
        mediaReleaseTimer?.invalidate(); mediaReleaseTimer = nil
        guard relayOpened, let deadline = [consumer.releaseDeadline, extraDecoder.mediaReleaseDeadline].compactMap({ $0 }).min() else { return }
        let timer = Timer(timeInterval: max(0.001, deadline - ProcessInfo.processInfo.systemUptime), repeats: false) { [weak self] _ in
            guard let self, self.relayOpened else { return }
            let now = ProcessInfo.processInfo.systemUptime
            self.forwardMedia(self.consumer.releaseExpired(at: now))
            self.forwardExtraMedia(self.extraDecoder.releaseMediaExpired(at: now))
            self.scheduleMediaRelease()
        }
        mediaReleaseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}
