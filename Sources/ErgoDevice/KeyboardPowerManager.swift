import Foundation
import ErgoCore

/// Shares the controller's single acknowledged transport. User settings are
/// persistent firmware choices; automatic blackout has its own durable recovery.
final class KeyboardPowerManager {
    typealias Send = (Protocol30Request, @escaping (Result<Data, Error>) -> Void) -> Void
    let send: Send
    let transaction: () -> UInt8
    let identity: () -> UUID?
    let load: () throws -> SavedKeyboardBrightness?
    let persist: (SavedKeyboardBrightness?) throws -> Void
    let changed: () -> Void
    private(set) var settings: KeyboardPowerSettings?
    private(set) var message = "Read the keyboard to load brightness and power settings."
    private(set) var busy = false
    private(set) var suppressed = false
    private(set) var saved: SavedKeyboardBrightness?
    private var observedSuppression = false
    private var pending: KeyboardPowerChanges?
    private var readPending = false
    private var retryAt = Date.distantPast
    private var invalidJournal = false
    private var quitting = false
    private var operationIdentity: UUID?
    var offVerified: Bool { suppressed && observedSuppression }
    var restorationOwed: Bool { saved != nil }
    var needsTimer: Bool { busy || (!invalidJournal && ((saved != nil && !suppressed) || suppressed != observedSuppression || pending != nil || readPending)) }
    var hasWork: Bool {
        !busy && Date() >= retryAt && !invalidJournal &&
        ((saved != nil && !suppressed) || suppressed != observedSuppression || pending != nil || readPending)
    }
    init(send: @escaping Send, transaction: @escaping () -> UInt8, identity: @escaping () -> UUID?,
         load: @escaping () throws -> SavedKeyboardBrightness?, persist: @escaping (SavedKeyboardBrightness?) throws -> Void,
         changed: @escaping () -> Void) {
        self.send = send; self.transaction = transaction; self.identity = identity
        self.load = load; self.persist = persist; self.changed = changed
        do { saved = try load() }
        catch { invalidJournal = true; message = "Saved brightness recovery is invalid; its file was preserved." }
    }
    func report(_ text: String) { message = text; changed() }
    func requestRead() { readPending = true; changed() }
    func apply(_ value: KeyboardPowerChanges) {
        do {
            if let dim = value.dimming { _ = try Protocol30Request.keyboardDimming(transaction: 1, value: dim) }
            if let sleep = value.sleep { _ = try Protocol30Request.keyboardSleepTimer(transaction: 1, seconds: sleep.seconds) }
            pending = value; changed()
        } catch { message = error.localizedDescription; changed() }
    }
    func setSuppressed(_ value: Bool) { guard value != suppressed else { return }; suppressed = value; retryAt = .distantPast; changed() }
    func prepareToQuit() { quitting = true; pending = nil; readPending = false; setSuppressed(false) }
    func pump() {
        guard hasWork, let id = identity() else { return }
        busy = true; operationIdentity = id
        if let saved, saved.peripheral != id { finish("Brightness recovery belongs to another keyboard.", retry: true); return }
        if let saved, !suppressed {
            writeBrightness(saved.brightness) { [weak self] result in
                guard let self else { return }
                do {
                    try result.get(); try self.persist(nil); self.saved = nil; self.observedSuppression = false
                    if var settings = self.settings { settings.brightness = saved.brightness; self.settings = settings }
                    self.finish("Previous keyboard brightness restored and verified.")
                } catch { self.finish("Brightness restoration pending: \(error.localizedDescription)", retry: true) }
            }
        } else if !suppressed && observedSuppression {
            observedSuppression = false; finish("Keyboard lighting follows your saved brightness.")
        } else if suppressed != observedSuppression {
            readBrightness { [weak self] result in
                guard let self else { return }
                do {
                    let raw = try result.get()
                    guard self.suppressed else { self.finish("Automatic lighting-off cancelled."); return }
                    // If already off, there is no brightness change for us to undo.
                    if raw == 0 { self.observedSuppression = true; self.finish("Lighting is off until activity or display wake."); return }
                    let saved = self.saved ?? SavedKeyboardBrightness(peripheral: id, brightness: raw)
                    try self.persist(saved); self.saved = saved // Durable before setting zero.
                    self.writeBrightness(0) { [weak self] result in
                        guard let self else { return }
                        switch result {
                        case .success: self.observedSuppression = true; self.finish("Lighting is off until activity or display wake.")
                        case .failure(let error): self.finish("Automatic lighting-off pending: \(error.localizedDescription)", retry: true)
                        }
                    }
                } catch { self.finish("Could not turn lighting off: \(error.localizedDescription)", retry: true) }
            }
        } else if let changes = pending {
            pending = nil
            applyChanges(changes)
        } else {
            readPending = false
            readSettings { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let settings): self.settings = settings; self.finish("Keyboard brightness and power settings read.")
                case .failure(let error): self.settings = nil; self.finish("Power settings unavailable: \(error.localizedDescription)")
                }
            }
        }
    }
    private func read(_ request: Protocol30Request, _ done: @escaping (Result<Data, Error>) -> Void) {
        guard identity() == operationIdentity else { done(.failure(LightingLabError.message("Keyboard identity changed; update stopped."))); return }
        send(request, done)
    }
    private func readBrightness(_ done: @escaping (Result<UInt8, Error>) -> Void) {
        read(try! .readKeyboardBrightness(transaction: transaction(), region: 5)) { result in
            done(result.flatMap { bytes in
                guard bytes.count == 1, let raw = bytes.first else { return .failure(LightingLabError.invalidPacket) }
                return .success(raw)
            })
        }
    }
    private func writeBrightness(_ raw: UInt8, done: @escaping (Result<Void, Error>) -> Void) {
        read(try! .keyboardBrightness(transaction: transaction(), raw: raw)) { [weak self] result in
            guard let self else { return }
            guard case .success = result else { done(result.map { _ in () }); return }
            self.readBrightness { result in
                done(result.flatMap { observed in observed == raw ? .success(()) : .failure(LightingLabError.message("Brightness readback did not match.")) })
            }
        }
    }
    private func readSettings(_ done: @escaping (Result<KeyboardPowerSettings, Error>) -> Void) {
        readBrightness { [weak self] result in
            guard let self else { return }
            let raw: UInt8
            do { raw = try result.get() } catch { done(.failure(error)); return }
            self.read(try! KeyboardPowerQuery.idleDimming.request(transaction: self.transaction())) { result in
                do {
                    let dimming = try KeyboardDimming(payload: result.get())
                    self.read(try! KeyboardPowerQuery.sleepTimer.request(transaction: self.transaction())) { result in
                        do {
                            let bytes = Array(try result.get())
                            guard bytes.count == 2 else { throw LightingLabError.invalidPacket }
                            let seconds = UInt16(bytes[0]) | UInt16(bytes[1]) << 8
                            self.read(try! KeyboardPowerQuery.automaticSleep.request(transaction: self.transaction())) { result in
                                do {
                                    let value = try result.get()
                                    guard value.count == 1, value[0] <= 1 else { throw LightingLabError.invalidPacket }
                                    done(.success(KeyboardPowerSettings(brightness: self.saved?.brightness ?? raw, dimming: dimming,
                                        sleep: KeyboardSleep(enabled: value[0] == 1, seconds: seconds))))
                                } catch { done(.failure(error)) }
                            }
                        } catch { done(.failure(error)) }
                    }
                } catch { done(.failure(error)) }
            }
        }
    }
    private func applyChanges(_ changes: KeyboardPowerChanges) {
        readSettings { [weak self] result in
            guard let self else { return }
            do {
                let current = try result.get()
                var expected = current
                var writes: [Protocol30Request] = []
                if let raw = changes.brightness, raw != current.brightness {
                    expected.brightness = raw
                    if var saved = self.saved {
                        saved.brightness = raw; try self.persist(saved); self.saved = saved
                    } else { writes.append(try .keyboardBrightness(transaction: self.transaction(), raw: raw)) }
                }
                if let dim = changes.dimming, dim != current.dimming {
                    expected.dimming = dim; writes.append(try .keyboardDimming(transaction: self.transaction(), value: dim))
                }
                if let sleep = changes.sleep, sleep != current.sleep {
                    expected.sleep = sleep
                    // Set the timer before enabling it, or disable before changing it.
                    if !sleep.enabled { writes.append(try .keyboardAutoSleep(transaction: self.transaction(), enabled: false)) }
                    writes.append(try .keyboardSleepTimer(transaction: self.transaction(), seconds: sleep.seconds))
                    if sleep.enabled { writes.append(try .keyboardAutoSleep(transaction: self.transaction(), enabled: true)) }
                }
                self.writeAll(writes[...]) { result in
                    guard case .success = result else { self.settings = nil; self.finish("Power update incomplete: \(result.failureDescription). Read keyboard to refresh."); return }
                    self.readSettings { result in
                        switch result {
                        case .success(let observed):
                            self.settings = observed
                            self.finish(observed == expected ? "Keyboard settings applied and verified." : "Keyboard reported different settings. Read keyboard to refresh.")
                        case .failure(let error): self.settings = nil; self.finish("Could not verify settings: \(error.localizedDescription)")
                        }
                    }
                }
            } catch { self.finish("Power update failed: \(error.localizedDescription)") }
        }
    }
    func noteBrightness(_ raw: UInt8) {
        if var settings { settings.brightness = saved?.brightness ?? raw; self.settings = settings; changed() }
    }
    private func writeAll(_ writes: ArraySlice<Protocol30Request>, done: @escaping (Result<Void, Error>) -> Void) {
        guard !quitting else { done(.failure(LightingLabError.message("Update stopped while quitting."))); return }
        guard let first = writes.first else { done(.success(())); return }
        read(first) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success: self.writeAll(writes.dropFirst(), done: done)
            case .failure(let error): done(.failure(error))
            }
        }
    }
    private func finish(_ text: String, retry: Bool = false) {
        busy = false; message = text
        if retry { retryAt = Date().addingTimeInterval(5) }
        changed()
    }
}
private extension Result {
    var failureDescription: String { if case .failure(let error) = self { return error.localizedDescription }; return "" }
}
