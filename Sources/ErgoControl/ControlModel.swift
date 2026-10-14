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
    @Published var activeProfileName = "Default"
    @Published var dialName = "Zoom"
    @Published var lastControl = "No control pressed yet"
    @Published var error: String?
    @Published var dirty = false
    @Published var inputAccessMode: InputAccessMode?
    let bluetooth = BluetoothController()
    let fullControlHelper = FullControlHelper()
    private let relay = KeyboardRelay()
    private let engine = ActionEngine()
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
    private var consumer: UInt16 = 0
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
                guard saved.schema == 1, !saved.profiles.isEmpty,
                      Set(saved.profiles.map(\.id)).count == saved.profiles.count else { throw MappingValidationError.message("Unsupported settings format") }
                configuration = saved; selectedProfileID = saved.manualProfileID
            } catch { self.error = "Saved settings could not be loaded. The original file has been preserved." }
        }
        frontmostID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        bluetooth.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        fullControlHelper.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        $configuration.dropFirst().sink { [weak self] _ in
            self?.dirty = true
            DispatchQueue.main.async { self?.updateProfile() }
        }.store(in: &subscriptions)
        relay.onReport = { [weak self] id, bytes in self?.receive(id, bytes) }
        relay.onDisconnect = { [weak self] in self?.stop("PT Ergo disconnected. Reconnect it, then enable mappings again.") }
        relay.onFailure = { [weak self] message in self?.stop(message) }
        engine.onError = { [weak self] message in self?.error = message; self?.stop(message) }
        engine.onCycle = { [weak self] in self?.cycleDial() }
        engine.onBattery = { [weak self] in
            guard let self else { return }
            self.bluetooth.readBattery()
            self.status = self.bluetooth.batteryText
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.title == "Ergo Control" })?.makeKeyAndOrderFront(nil)
        }
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification).sink { [weak self] note in
            self?.frontmostID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            self?.updateProfile()
        }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification).sink { [weak self] _ in
            self?.stop("Mappings stopped for sleep. Enable them after waking PT Ergo.")
        }.store(in: &subscriptions)
        bluetooth.$driverModeVerified.removeDuplicates().sink { [weak self] verified in
            guard let self else { return }
            if verified && self.preparing && self.relayOpened {
                self.running = true; self.preparing = false
                self.status = self.inputAccessMode == .macroButtons
                    ? "Macro buttons active · M1–M5, AI, left click and battery. Dial and ordinary-key remaps are unavailable."
                    : "Mappings active · PT Ergo only"
            } else if !verified && self.running { self.stop("Keyboard mode changed. Mappings stopped safely.") }
        }.store(in: &subscriptions)
        updateProfile()
    }

    var accessibilityGranted: Bool { AXIsProcessTrusted() }
    var inputGranted: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent).rawValue == 0 }
    var profileIndex: Int { configuration.profiles.firstIndex(where: { $0.id == selectedProfileID }) ?? 0 }
    var activeProfile: MappingProfile { configuration.profile(for: frontmostID) }
    var layerActive: Bool { !layerKeys.isEmpty }

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
        for profile in configuration.profiles {
            for action in Array(profile.mappings.values) + Array(profile.alternate.values) + profile.dialModes.flatMap({ [$0.clockwise, $0.counterclockwise] }) {
                switch action.kind {
                case .shortcut: _ = try KeyChord(action.value)
                case .macro: _ = try MacroStep.parse(action.value)
                case .application, .toggleApplication: guard action.value.hasSuffix(".app") else { throw MappingValidationError.message("Choose an application for \(action.kind.rawValue)") }
                case .script: guard FileManager.default.fileExists(atPath: action.value) else { throw MappingValidationError.message("Choose an existing script") }
                case .text: guard action.value.utf16.count <= 4096 else { throw MappingValidationError.message("Text actions can contain up to 4096 characters") }
                default: break
                }
            }
        }
    }
    func addProfile() {
        let profile = MappingProfile(name: "New profile")
        configuration.profiles.append(profile); selectedProfileID = profile.id
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
        activeProfileName = activeProfile.name
        let modes = activeProfile.dialModes.filter(\.enabled)
        let index = modeIndices[activeProfile.id, default: 0]
        dialName = modes.isEmpty ? "No enabled dial modes" : modes[index % modes.count].name
    }
    private func cycleDial() {
        guard inputAccessMode != .macroButtons else { status = "Custom dial modes need full keyboard control, which macOS denied."; return }
        let id = activeProfile.id
        let count = activeProfile.dialModes.filter(\.enabled).count
        guard count > 0 else { return }
        let backwards = engine.physicalModifiers & 0x22 != 0
        modeIndices[id] = (modeIndices[id, default: 0] + (backwards ? count - 1 : 1)) % count
        updateProfile()
    }

    func start(testSeconds: TimeInterval? = nil) {
        guard !running, !preparing else { return }
        guard !fullControlHelper.checkingPermission else { status = "Wait for the helper permission check to finish."; return }
        error = nil
        fullControlHelper.refresh()
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
        extraDecoder = ExtraKeyDecoder(); ordinary.removeAll(); keyActions.removeAll(); extraActions.removeAll(); mediaActions.removeAll(); layerKeys.removeAll(); consumer = 0
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
        if Date().timeIntervalSince(stageStarted) > 30 { stop("Could not activate mappings. " + bluetooth.status); return }
        guard bluetooth.ready, !bluetooth.busy else { return }
        if bluetooth.canTryDriverMode, !activationStarted {
            if !batteryRequested { batteryRequested = true; bluetooth.readBattery(); return }
            activationStarted = true; relayOpened = true
            // Forward ordinary input immediately, including during the helper's asynchronous open.
            inputAccessMode = fullControlHelper.enabled ? .fullKeyboard : nil
            relay.start(usingHelper: fullControlHelper.enabled) { [weak self] result in
                guard let self, self.preparing, self.activationStarted else { return }
                switch result {
                case .success(let mode): self.inputAccessMode = mode; self.bluetooth.tryDriverMode()
                case .failure(let error): self.stop(error.localizedDescription)
                }
            }
        }
    }
    func stop(_ message: String = "Mappings off · normal keyboard mode restored when verified") {
        preparing = false; running = false; timer?.invalidate(); timer = nil
        sessionDeadline = nil
        relay.stop(); relayOpened = false; engine.stop()
        ordinary.removeAll(); keyActions.removeAll(); extraActions.removeAll(); mediaActions.removeAll(); layerKeys.removeAll()
        bluetooth.restore(); status = message
    }
    func terminate() -> NSApplication.TerminateReply { stop(); return bluetooth.requestTermination() }

    private func action(for control: String) -> MappingAction {
        let profile = activeProfile
        if layerActive, let action = profile.alternate[control], action.kind != .standard { return action }
        if let action = profile.mappings[control], action.kind != .standard { return action }
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
        if action.kind == .layer {
            engine.endAppSwitcher()
            if pressed { layerKeys.insert(control) } else { layerKeys.remove(control) }
        } else if pressed { engine.perform(action, fromDial: ["leftCW", "leftCCW", "rightCW", "rightCCW"].contains(control)) }
    }
    private func receive(_ id: UInt32, _ data: Data) {
        guard relay.accessMode.accepts(reportID: id) else { return }
        let bytes = Array(data)
        guard id <= 255, bytes.first == UInt8(id) else { stop("Unexpected keyboard packet; normal input has been returned."); return }
        if id == 1 {
            guard bytes.count == 12 else { stop("Unexpected keyboard packet size; mappings stopped."); return }
            guard let snapshot = KeyboardSnapshot(data) else { return }
            engine.physicalModifiers = snapshot.modifiers
            let current = snapshot.held
            guard current.allSatisfy({ MacKeys.codes[$0] != nil }) else {
                stop("This key needs support; PT Ergo has been returned to normal input."); return
            }
            let released = ordinary.subtracting(current).sorted()
            let pressed = current.subtracting(ordinary).sorted()
            if !released.isEmpty || !pressed.isEmpty { engine.endAppSwitcher() }
            for usage in released {
                guard relayOpened else { return }
                let action = keyActions.removeValue(forKey: usage) ?? MappingAction()
                if action.kind == .standard { engine.relay(usage, pressed: false) }
                else { execute(action, control: "key:\(usage)", pressed: false) }
            }
            for usage in pressed {
                guard relayOpened else { return }
                var mapping = running ? action(for: "key:\(usage)") : MappingAction()
                let profile = activeProfile
                if running, profile.gamingMode, engine.physicalModifiers & 0x88 != 0,
                   (usage == 20 && profile.blockQuit || usage == 43 && profile.blockAppSwitch || usage == 44 && profile.blockSpotlight) { mapping = MappingAction(.disabled) }
                keyActions[usage] = mapping
                if mapping.kind == .standard { engine.relay(usage, pressed: true) }
                else { execute(mapping, control: "key:\(usage)", pressed: true) }
            }
            ordinary = current
        } else if id == 5 {
            guard let events = extraDecoder.decode(reportID: id, bytes: data) else { stop("Unexpected extra-key packet; mappings stopped."); return }
            guard running || relayOpened && relay.accessMode == .fullKeyboard else { return }
            for event in events {
                guard relayOpened else { return }
                let control = "extra:\(event.key)"
                if event.pressed { lastControl = ControlCatalog.label(control); extraActions[event.key] = running ? action(for: control) : MappingAction() }
                let mapping = extraActions[event.key] ?? MappingAction()
                if mapping.kind == .standard, relay.accessMode == .fullKeyboard,
                   let usage = NativeExtraKeys.usage(for: event.key) {
                    engine.relay(usage, pressed: event.pressed, owner: control)
                } else { execute(mapping, control: control, pressed: event.pressed) }
                if !event.pressed { extraActions.removeValue(forKey: event.key) }
            }
        } else if id == 2 {
            guard bytes.count == 9, bytes[1] == 0, bytes[2] == 0, bytes.dropFirst(4).allSatisfy({ $0 == 0 }) else {
                stop("An unsupported pointer report arrived from PT Ergo; mappings stopped."); return
            }
            let steps = Int(Int8(bitPattern: bytes[3])); guard running, steps != 0 else { return }
            let control = steps > 0 ? "leftCW" : "leftCCW"
            lastControl = ControlCatalog.label(control)
            for _ in 0..<min(32, abs(steps)) { engine.perform(action(for: control), fromDial: true) }
        } else if id == 3 {
            guard bytes.count == 12, bytes.dropFirst(3).allSatisfy({ $0 == 0 }) else { stop("Unexpected media packet; mappings stopped."); return }
            let usage = UInt16(bytes[1]) | UInt16(bytes[2]) << 8
            guard usage != consumer else { return }
            let controls: [UInt16: String] = [0xe9:"rightCW",0xea:"rightCCW",0xe2:"rightClick",0xcd:"mediaSingle",0xb5:"mediaDouble",0xb6:"mediaTriple"]
            if consumer != 0 {
                let mapping = mediaActions.removeValue(forKey: consumer) ?? MappingAction()
                if mapping.kind == .standard { _ = engine.media(consumer, pressed: false) }
                else { execute(mapping, control: controls[consumer] ?? "media:\(consumer)", pressed: false) }
            }
            if usage != 0 {
                let control = controls[usage] ?? "media:\(usage)"
                let mapping = running ? action(for: control) : MappingAction()
                mediaActions[usage] = mapping; lastControl = ControlCatalog.label(control)
                if mapping.kind == .standard {
                    guard engine.media(usage, pressed: true) else { stop("This media key needs support (\(usage)); mappings stopped."); return }
                } else { execute(mapping, control: control, pressed: true) }
            }
            consumer = usage
        } else if id == 6 { return } // device notifications, not keyboard actions
        else { stop("This input report needs support (\(id)); mappings stopped.") }
    }
}
