import Foundation
import ErgoCore

/// Event-driven frames on the controller's existing acknowledged command queue.
/// Status waves share the existing controller timer and command queue.
final class MacroStatusRenderer {
    typealias Command = (BluetoothLightingLabCommand, UInt8, @escaping (Result<Data, Error>) -> Void) -> Void
    var desired: DialColor?
    private(set) var busy = false
    private var rendered: DialColor?
    private var desiredArea: CodexLightingArea = .macroColumn
    private var renderedArea: CodexLightingArea?
    private let uptime: () -> TimeInterval
    private var signalID: String?
    private var waveActivity: CodexActivity?
    private var waveSpeed: CodexWaveSpeed = .smooth
    private var completedIDs: [String] = []
    private var waveStarted: TimeInterval?
    private var waveIndex = 0
    private var nextWaveFrame: TimeInterval = 0
    private var pulseRevision = 0
    private var renderedPulseRevision = 0
    private var lastPixels: [DialColor]?
    private var partialFramesUnavailable = false
    private var darkBackground = false
    private var pulseEnabled = false
    private var desiredActivity: CodexActivity?
    private var pulseStarted: TimeInterval?
    private var renderedPulsePhase: Int?
    private var pulses: Bool {
        pulseEnabled && desiredActivity == .working && desiredArea == .macroColumn && desired != nil
            && (signalID == nil || completedIDs.contains(signalID!))
    }
    // One 2.8-second breath, including a fully dark macro-column frame.
    private static let pulseLevels = [100, 75, 40, 15, 0, 15, 40, 75]
    private var pulsePhase: Int {
        guard let pulseStarted else { return 0 }
        return Int(max(0, uptime() - pulseStarted) / 0.35) % Self.pulseLevels.count
    }
    private var selected = false
    private var failed = false
    private var retryAfter = Date.distantPast
    let command: Command
    let load: () -> SavedMacroLighting?
    let persist: (SavedMacroLighting?) throws -> Void
    let allowed: () -> Bool
    let message: (String) -> Void
    init(command: @escaping Command, load: @escaping () -> SavedMacroLighting?,
         persist: @escaping (SavedMacroLighting?) throws -> Void, allowed: @escaping () -> Bool,
         message: @escaping (String) -> Void, uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.uptime = uptime
        self.command = command; self.load = load; self.persist = persist
        self.allowed = allowed; self.message = message
    }
    func reset() {
        selected = false; rendered = nil; renderedArea = nil; failed = false; retryAfter = .distantPast
        waveStarted = nil; waveIndex = 0; nextWaveFrame = 0
        pulseStarted = nil; renderedPulsePhase = nil; lastPixels = nil
    }
    private func consumeSignal(_ id: String?) {
        guard let id, !completedIDs.contains(id) else { return }
        completedIDs.append(id)
        if completedIDs.count > 32 { completedIDs.removeFirst() }
    }
    func request(_ color: DialColor?, area: CodexLightingArea = .macroColumn,
                 signalID id: String? = nil, activity: CodexActivity? = nil, allowCompletionToFinish: Bool = false, speed: CodexWaveSpeed = .smooth, pulseWhileWorking: Bool = false, darkBackground: Bool = false) {
        // A chat becoming idle must not truncate an acknowledged return sweep.
        // Explicit disable/stop and new activity still supersede it immediately.
        if color == nil, allowCompletionToFinish, area == .completionWave,
           waveActivity == .finished, let signalID, !completedIDs.contains(signalID), !failed { return }
        if self.darkBackground != darkBackground || pulseEnabled != pulseWhileWorking || desiredActivity != activity || desired != color {
            pulseStarted = nil; renderedPulsePhase = nil
            pulseRevision &+= 1
        }
        self.darkBackground = darkBackground
        pulseEnabled = pulseWhileWorking; desiredActivity = activity
        let animate = color != nil && area == .completionWave && id != nil
            && activity.map { [.working, .attention, .finished].contains($0) } == true
        let nextID = animate ? id.map { "\($0):\(speed.rawValue)" } : nil
        let nextActivity = animate ? activity : nil
        if nextID != signalID || nextActivity != waveActivity {
            if waveActivity != .attention { consumeSignal(signalID) }
            waveStarted = nil; waveIndex = 0; nextWaveFrame = 0
            pulseStarted = nil; renderedPulsePhase = nil
        }
        if color == nil {
            if waveActivity != .attention { consumeSignal(signalID) }
            signalID = nil; waveActivity = nil; desired = nil; desiredArea = area; reset()
        } else if !failed {
            desiredArea = area; signalID = nextID; waveActivity = nextActivity; waveSpeed = speed
            let consumed = nextActivity != .attention && nextID.map { completedIDs.contains($0) } == true
            if consumed && nextActivity == .working {
                desiredArea = .macroColumn
                desired = color
            } else { desired = consumed ? nil : color }
        }
    }
    /// Static status colors need no periodic frame-pump wakeups. Keep polling
    /// only for animations or a restoration retry with its durable snapshot.
    var needsTimer: Bool {
        if busy || pulses { return true }
        if desired == nil || failed { return load() != nil }
        return signalID.map { !completedIDs.contains($0) } ?? false
    }
    var hasWork: Bool {
        guard !busy, Date() >= retryAfter else { return false }
        if (desired == nil || failed) && load() != nil { return true }
        guard desired != nil, !failed else { return false }
        if let signalID, !completedIDs.contains(signalID) { return uptime() >= nextWaveFrame }
        return desired != rendered || desiredArea != renderedArea || pulseRevision != renderedPulseRevision || (pulses && renderedPulsePhase != pulsePhase)
    }
    func pump() {
        guard hasWork, allowed() else { return }
        busy = true
        if waveActivity == .working, let start = waveStarted, uptime() - start >= CodexStatusWave.maximumDuration {
            finishWave()
        }
        if desired == nil || failed { restore { _ in }; return }
        if let saved = load() {
            if selected { frame(region: saved.region) }
            else { select(region: saved.region) }
            return
        }
        step(.readRegions, region: 0) { [weak self] data in
            guard let self else { return }
            guard data.map({ $0 & 63 }).contains(5) else { self.fail(LightingLabError.message("Keyboard backlight region 5 was not reported.")); return }
            self.step(.readEffect, region: 5) { [weak self] data in
                guard let self else { return }
                do {
                    let saved = try SavedMacroLighting(region: 5, effect: KeyboardEffect(payload: data))
                    try self.persist(saved) // Durable before the first write.
                    self.select(region: saved.region)
                } catch { self.fail(error) }
            }
        }
    }
    private func select(region: UInt8) {
        step(.selectCustom, region: region) { [weak self] _ in
            self?.selected = true
            self?.frame(region: region)
        }
    }
    private func frame(region: UInt8) {
        guard let color = desired else { busy = false; return }
        let area = desiredArea
        let wave = signalID.flatMap { completedIDs.contains($0) ? nil : $0 }
        let state = waveActivity
        if wave != nil && waveStarted == nil { waveStarted = uptime() }
        let revision = pulseRevision
        let pulsing = pulses
        if pulsing && pulseStarted == nil { pulseStarted = uptime() }
        let phase = pulsing ? pulsePhase : nil
        let pulseEpoch = pulseStarted
        var colors: [DialColor]
        if wave != nil, let state { colors = CodexStatusWave.frame(waveIndex, activity: state, speed: waveSpeed, darkBackground: darkBackground, color: color) }
        else {
            let level = phase.map { Self.pulseLevels[$0] } ?? 100
            let signal = DialColor(red: UInt8(Int(color.red) * level / 100),
                                   green: UInt8(Int(color.green) * level / 100),
                                   blue: UInt8(Int(color.blue) * level / 100))
            colors = MacroStatusFrame.colors(signal, area: area)
        }
        if darkBackground && area != .wholeKeyboard && wave == nil {
            for index in 1..<colors.count { colors[index] = DialColor(red: 0, green: 0, blue: 0) }
        }
        writeFrame(colors, region: region, preferMacro: pulsing) { [weak self] in
            guard let self else { return }
            self.rendered = color; self.renderedArea = area; self.busy = false
            self.renderedPulseRevision = revision
            if self.pulses == pulsing && self.pulseStarted == pulseEpoch { self.renderedPulsePhase = phase }
            if let wave, let state, wave == self.signalID, state == self.waveActivity {
                self.waveIndex += 1
                self.nextWaveFrame = self.uptime() + CodexStatusWave.minimumFrameInterval
                if self.waveIndex == CodexStatusWave.positions(for: state, speed: self.waveSpeed).count {
                    if state == .attention {
                        // The last frame is already at the macro-side endpoint.
                        // Advance toward the right immediately, without duplicating it.
                        self.waveIndex = 1; self.waveStarted = nil
                        self.message("Approval wave bounces while approval is pending")
                    } else {
                        self.finishWave()
                        self.message(state == .working ? "Starting wave finished · keeping macro keys in the working color" : "Status wave finished · restoring previous effect")
                    }
                } else { self.message(state == .finished ? "Completion wave · out and back" : "Status wave · macro column to the right") }
            } else {
                self.message(pulsing ? "Macro keys pulse in the working color" : area == .wholeKeyboard ? "Whole keyboard shows chat status" : "Macro column shows chat status · other keys dimmed")
            }
        }
    }

    private func writeFrame(_ colors: [DialColor], region: UInt8, preferMacro: Bool, completion: @escaping () -> Void) {
        guard allowed() else { busy = false; return }
        let partial = preferMacro && !partialFramesUnavailable && lastPixels?.dropFirst() == colors.dropFirst()
        let operation: BluetoothLightingLabCommand = partial ? .macroColor(colors[0]) : .frame(colors)
        command(operation, region) { [weak self] result in
            guard let self else { return }
            guard self.allowed() else { self.busy = false; return }
            switch result {
            case .success:
                self.lastPixels = colors
                completion()
            case .failure(let error):
                if partial {
                    // Unsupported short frames fall back once, preserving input
                    // and the original effect's existing recovery snapshot.
                    self.partialFramesUnavailable = true
                    self.writeFrame(colors, region: region, preferMacro: false, completion: completion)
                } else { self.fail(error) }
            }
        }
    }

    private func finishWave() {
        consumeSignal(signalID); waveStarted = nil
        if waveActivity == .working { desiredArea = .macroColumn }
        else { desired = nil }
    }

    private func step(_ operation: BluetoothLightingLabCommand, region: UInt8, completion: @escaping (Data) -> Void) {
        guard allowed() else { busy = false; return }
        command(operation, region) { [weak self] result in
            guard let self else { return }
            guard self.allowed() else { self.busy = false; return }
            switch result {
            case .success(let data): completion(data)
            case .failure(let error): self.fail(error)
            }
        }
    }
    private func fail(_ error: Error) {
        busy = false; failed = true; desired = nil
        message("Chat lighting unavailable: \(error.localizedDescription). Previous effect restoration will be retried if needed.")
    }
    /// Also used during mapping recovery, where ordinary new lighting is barred.
    /// The caller owns transport serialization and prioritizes normal-mode restore.
    func restore(completion: @escaping (Bool) -> Void) {
        guard let saved = load() else { busy = false; completion(true); return }
        let effect: KeyboardEffect
        do { effect = try saved.validatedEffect() }
        catch { busy = false; message("Saved lighting is invalid; recovery record retained."); completion(false); return }
        busy = true
        command(.restore(effect), saved.region) { [weak self] result in
            guard let self else { return }
            guard case .success = result else {
                self.busy = false; self.retryAfter = Date().addingTimeInterval(5)
                self.message("Previous lighting restoration is pending; keep PT Ergo connected.")
                completion(false); return
            }
            self.command(.readEffect, saved.region) { [weak self] result in
                guard let self else { return }
                self.busy = false
                guard case .success(let data) = result,
                      (try? KeyboardEffect(payload: data)) == effect else {
                    self.retryAfter = Date().addingTimeInterval(5)
                    self.message("Previous lighting readback did not match; recovery record retained.")
                    completion(false); return
                }
                do {
                    try self.persist(nil)
                    self.selected = false; self.rendered = nil; self.renderedArea = nil; self.lastPixels = nil
                    self.message("Previous keyboard lighting restored and verified")
                    completion(true)
                } catch { self.retryAfter = Date().addingTimeInterval(5); self.message("Could not update lighting recovery record; retained for retry."); completion(false) }
            }
        }
    }
}
