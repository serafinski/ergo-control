import Foundation
import ErgoCore

/// Event-driven frames on the controller's existing acknowledged command queue.
/// No second Bluetooth connection, timers, animation stream, or input capture.
final class MacroStatusRenderer {
    typealias Command = (BluetoothLightingLabCommand, UInt8, @escaping (Result<Data, Error>) -> Void) -> Void
    var desired: DialColor?
    private(set) var busy = false
    private var rendered: DialColor?
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
         message: @escaping (String) -> Void) {
        self.command = command; self.load = load; self.persist = persist
        self.allowed = allowed; self.message = message
    }
    func reset() { selected = false; rendered = nil; failed = false; retryAfter = .distantPast }
    func request(_ color: DialColor?) {
        if color == nil { desired = nil; reset() }
        else if !failed { desired = color }
    }
    var hasWork: Bool { !busy && Date() >= retryAfter && ((desired != nil && !failed && desired != rendered) || ((desired == nil || failed) && load() != nil)) }
    func pump() {
        guard hasWork, allowed() else { return }
        busy = true
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
        step(.frame(MacroStatusFrame.colors(color)), region: region) { [weak self] _ in
            self?.rendered = color; self?.busy = false
            self?.message("Macro column shows Codex status · other keys white")
        }
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
        message("Codex lighting unavailable: \(error.localizedDescription). Previous effect restoration will be retried if needed.")
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
                    self.selected = false; self.rendered = nil
                    self.message("Previous keyboard lighting restored and verified")
                    completion(true)
                } catch { self.retryAfter = Date().addingTimeInterval(5); self.message("Could not update lighting recovery record; retained for retry."); completion(false) }
            }
        }
    }
}
