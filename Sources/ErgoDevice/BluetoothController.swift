import Foundation
import CoreBluetooth
import IOKit.hid
import AppKit
import ErgoCore

struct SavedMode: Codable {
    let peripheral: UUID
    let mode: UInt8
    let parameter: UInt8
    var dialLight: SavedDialLight? = nil
}

struct SavedDialLight: Codable {
    let color: DialColor?
    let on: Bool
    var brightness: UInt8? = nil

    static func fallbackForUnsupportedRGB(state: UInt8, status: UInt8) -> Self? {
        guard state == 0, status == 5 || status == 7 else { return nil }
        return Self(color: nil, on: false)
    }
}

private final class PendingCommand {
    let request: Protocol30Request
    var exchange: Protocol30Exchange
    var nextWrite = 0
    let completion: (Result<Protocol30Response, Error>) -> Void

    init(_ request: Protocol30Request, completion: @escaping (Result<Protocol30Response, Error>) -> Void) throws {
        self.request = request
        self.exchange = try Protocol30Exchange(request: request)
        self.completion = completion
    }
}

enum BluetoothFailure: LocalizedError {
    case message(String)
    case rejected(UInt8)
    var requiresReconnect: Bool {
        if case .rejected = self { return false }
        return true
    }
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .rejected(5): return "Keyboard does not support this command (status 5)"
        case .rejected(7): return "Keyboard does not support this target (status 7)"
        case .rejected(let status): return "Keyboard response status \(status)"
        }
    }
}

public enum BatteryReadState: Equatable {
    case idle, reading, ready(Int), failed(String)
}

public final class BluetoothController: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published public var status = "Ready to read PT Ergo's current mode"
    @Published public var modeText = "Not read yet"
    @Published public var ready = false
    @Published public var busy = false
    @Published public var restoreOwed = false
    @Published public var secondsRemaining = 0
    @Published public var rows: [String] = []
    @Published public var logURL: URL?
    @Published public var driverModeVerified = false
    @Published public var batteryText = "Battery status has not been read"
    @Published public private(set) var batteryPercent: Int?
    @Published public private(set) var batteryReadState: BatteryReadState = .idle

    @Published public private(set) var lightingStatus = ""
    @Published public private(set) var keyboardBrightnessPercent: Int?
    @Published public private(set) var keyboardEffectIDs: [UInt8] = []
    @Published public private(set) var currentKeyboardEffect: KeyboardEffect?
    @Published public private(set) var keyboardEffectStatus = "Read the keyboard to choose a lighting effect."
    @Published public private(set) var keyboardEffectBusy = false
    public private(set) var keyboardEffectRequestSucceeded = false
    public var connectedDeviceIdentity: String? { targetID?.uuidString }
    private var effectRequests = KeyboardLightingRequests()
    private var brightnessSteps = BrightnessSteps()
    private var lightingRegion: UInt8?
    private var lightingTimer: Timer?
    private var lightingOperation = false
    private var requestedDialColor: DialColor?
    private var lastRequestedDialColor: DialColor?
    private var indicatorBacklight = DialBacklightGate()
    private var dialDeadline: TimeInterval?
    private var dialLightChanged = false
    private var indicatorUnavailable = false
    private var brightnessUnavailable = false

    private var central: CBCentralManager?
    private var target: CBPeripheral?
    private var targetID: UUID?
    private var writeCharacteristic: CBCharacteristic?
    private var pending: PendingCommand?
    private var transactions = TransactionSequence()
    private var commandTimeout: Timer?
    private var connectionTimeout: Timer?
    private var restoreTimer: Timer?
    private var leaseDeadline: TimeInterval?
    private var retryTimer: Timer?
    private var original: SavedMode?
    private var currentMode: (UInt8, UInt8)?
    private var restoreRequested = false
    private var restorationChain = false
    private var closing = false
    private var logfile: FileHandle?
    private let serviceUUID = CBUUID(string: ErgoTarget.service)
    private let writeUUID = CBUUID(string: "52401524-F97C-7F90-0E7F-6C6F4E36DB1C")
    private let notifyUUID = CBUUID(string: ErgoTarget.notify)
    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ErgoControl/Bluetooth", isDirectory: true)
    }
    private var recoveryURL: URL { Self.folder.appendingPathComponent("pending-restoration.json") }

    public override init() {
        super.init()
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let url = Self.folder.appendingPathComponent("bluetooth-\(UUID().uuidString).jsonl")
            guard FileManager.default.createFile(atPath: url.path, contents: nil,
                                                 attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
            logfile = try FileHandle(forWritingTo: url)
            logURL = url
        } catch { status = "Cannot create diagnostic log: \(error.localizedDescription)" }
        if let data = try? Data(contentsOf: recoveryURL), let saved = try? JSONDecoder().decode(SavedMode.self, from: data) {
            original = saved
            restoreOwed = true
            status = "A previous temporary change needs restoration. Connect the same PT Ergo to restore it."
        }
    }

    private func log(_ kind: String, _ fields: [String: Any] = [:]) {
        var object = fields
        object["kind"] = kind
        object["time"] = ISO8601DateFormatter().string(from: Date())
        object["uptime"] = ProcessInfo.processInfo.systemUptime
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            if let logfile { try logfile.write(contentsOf: data + Data([10])) }
            rows.append("\(kind): " + fields.keys.sorted().map { "\($0)=\(fields[$0]!)" }.joined(separator: " "))
            if rows.count > 150 { rows.removeFirst(rows.count - 150) }
        } catch { status = "Diagnostic log write failed: \(error.localizedDescription)" }
    }

    private func exactTargetID() -> UUID? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: ErgoTarget.vendorID,
            kIOHIDProductIDKey: ErgoTarget.productID, kIOHIDTransportKey: ErgoTarget.transport] as CFDictionary)
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        let eligible = devices.filter { device in
            let vid = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? NSNumber)?.intValue ?? 0
            let pid = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
            let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? ""
            return ErgoTarget.matches(vendor: vid, product: pid, transport: transport)
        }
        let ids = Set(eligible.compactMap {
            UUID(uuidString: IOHIDDeviceGetProperty($0, "PhysicalDeviceUniqueID" as CFString) as? String ?? "")
        })
        guard ids.count == 1 else { return nil }
        return ids.first
    }

    public func connect() {
        guard !busy else { return }
        guard let id = exactTargetID() else { status = "Wake PT Ergo and try again; its paired Bluetooth endpoint was not found."; return }
        if let original, original.peripheral != id {
            status = "Restoration belongs to a different PT Ergo. Reconnect that keyboard first."
            return
        }
        targetID = id
        status = "Connecting to PT Ergo's configuration service…"
        ready = false
        log("target_verified", ["vendor": ErgoTarget.vendorID, "product": ErgoTarget.productID, "transport": ErgoTarget.transport])
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main,
                                       options: [CBCentralManagerOptionShowPowerAlertKey: false])
        } else if central?.state == .poweredOn { connectKnownTarget() }
    }

    private func connectKnownTarget() {
        guard let central, let targetID else { return }
        connectionTimeout?.invalidate()
        guard let device = central.retrievePeripherals(withIdentifiers: [targetID]).first,
              device.identifier == targetID else { status = "Could not retrieve the paired PT Ergo endpoint"; scheduleRestoreRetry(); return }
        target = device
        device.delegate = self
        guard device.state != .disconnecting else { scheduleRestoreRetry(); return }
        if device.state == .connected { device.discoverServices([serviceUUID]) }
        else { central.connect(device, options: nil) }
        connectionTimeout = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.status = "Configuration connection timed out. Wake PT Ergo and retry."
            self.ready = false
            if let target = self.target { self.central?.cancelPeripheralConnection(target) }
            self.scheduleRestoreRetry()
        }
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log("bluetooth_state", ["state": central.state.rawValue])
        if central.state == .poweredOn { connectKnownTarget() }
        else {
            ready = false
            status = central.state == .unauthorized ? "Bluetooth access is required for Ergo Bluetooth in System Settings." : "Bluetooth is unavailable; enable it and retry."
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral == target else { return }
        log("connected")
        peripheral.discoverServices([serviceUUID])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionTimeout?.invalidate()
        ready = false
        status = error?.localizedDescription ?? "Could not connect to the keyboard configuration service"
        log("connection_failed", ["error": status])
        scheduleRestoreRetry()
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral == target else { return }
        ready = false
        driverModeVerified = false
        writeCharacteristic = nil
        cancelQueuedKeyboardEffect()
        lightingTimer?.invalidate(); lightingTimer = nil
        log("disconnected", ["error": error?.localizedDescription ?? "none"])
        if pending != nil { complete(.failure(BluetoothFailure.message("Keyboard configuration connection ended"))) }
        status = restoreOwed ? "Waiting for PT Ergo to reconnect so its original mode can be restored…" : "Configuration connection ended"
        scheduleRestoreRetry()
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral == target else { return }
        if let error { connectionFailed(error.localizedDescription); return }
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            connectionFailed("The expected Protocol 30 service was not exposed"); return
        }
        log("service", ["uuid": service.uuid.uuidString])
        peripheral.discoverCharacteristics([writeUUID, notifyUUID], for: service)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral == target else { return }
        if let error { connectionFailed(error.localizedDescription); return }
        let characteristics = service.characteristics ?? []
        for item in characteristics { log("characteristic", ["uuid": item.uuid.uuidString, "properties": item.properties.rawValue]) }
        guard let write = characteristics.first(where: { $0.uuid == writeUUID && $0.properties.contains(.write) }),
              let notify = characteristics.first(where: { $0.uuid == notifyUUID && $0.properties.contains(.notify) }) else {
            connectionFailed("Required acknowledged-write and notification characteristics are missing"); return
        }
        writeCharacteristic = write
        peripheral.setNotifyValue(true, for: notify)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == target, characteristic.uuid == notifyUUID else { return }
        if let error { connectionFailed(error.localizedDescription); return }
        guard characteristic.isNotifying else { connectionFailed("Response notifications are not enabled"); return }
        connectionTimeout?.invalidate()
        ready = true
        log("responses_enabled")
        if restoreOwed { restore() }
        else { readMode() }
    }

    private func connectionFailed(_ reason: String) {
        connectionTimeout?.invalidate()
        ready = false
        status = reason
        log("connection_error", ["error": reason])
        scheduleRestoreRetry()
    }

    private func send(_ request: Protocol30Request, completion: @escaping (Result<Protocol30Response, Error>) -> Void) {
        guard ready, target?.state == .connected, writeCharacteristic != nil, pending == nil else {
            completion(.failure(BluetoothFailure.message("Configuration connection is not ready or a command is already active")))
            return
        }
        do { pending = try PendingCommand(request, completion: completion) }
        catch { completion(.failure(error)); return }
        busy = true
        log("command", ["header": request.header.hex, "payload": request.payload.hex])
        commandTimeout = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            self?.complete(.failure(BluetoothFailure.message("The keyboard did not return a complete response within five seconds")))
        }
        writeNextChunk()
    }

    private func writeNextChunk() {
        guard let pending, let target, let writeCharacteristic else { return }
        guard let chunk = pending.exchange.nextWrite() else { return }
        pending.nextWrite += 1
        log("write", ["chunk": pending.nextWrite, "hex": chunk.hex])
        target.writeValue(chunk, for: writeCharacteristic, type: .withResponse)
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == target, characteristic.uuid == writeUUID, let pending else { return }
        if let error { complete(.failure(error)); return }
        do { try pending.exchange.acknowledgeWrite() }
        catch { complete(.failure(error)); return }
        writeNextChunk()
        finishIfReady()
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == target, characteristic.uuid == notifyUUID else { return }
        if let error { if pending != nil { complete(.failure(error)) }; return }
        guard let data = characteristic.value else { return }
        log("response_fragment", ["hex": data.hex])
        guard let pending else { return }
        do {
            try pending.exchange.receive(data)
            finishIfReady()
        } catch { complete(.failure(error)) }
    }

    private func finishIfReady() {
        guard let response = pending?.exchange.completedResponse else { return }
        complete(response.succeeded ? .success(response) : .failure(BluetoothFailure.rejected(response.status)))
    }

    private func complete(_ result: Result<Protocol30Response, Error>) {
        guard let command = pending else { return }
        pending = nil
        busy = false
        commandTimeout?.invalidate(); commandTimeout = nil
        if case .failure(let error) = result {
            log("command_failed", ["error": error.localizedDescription])
            // Do not let a late reply or write acknowledgement from a failed
            // exchange overlap restoration on the same connection.
            // A fully received negative acknowledgement leaves the stream in
            // sync. Optional lighting being unsupported must not stop mappings.
            if (error as? BluetoothFailure)?.requiresReconnect != false {
                ready = false
                writeCharacteristic = nil
                if let target, target.state == .connected { central?.cancelPeripheralConnection(target) }
            }
        }
        command.completion(result)
        if restoreRequested, pending == nil { restoreRequested = false; restore() }
        else { DispatchQueue.main.async { [weak self] in self?.pumpLighting() } }
    }

    public func readMode() {
        guard !restoreOwed else { restore(); return }
        guard ready, !busy else { return }
        status = "Reading current keyboard mode…"
        guard let request = try? Protocol30Request.readDeviceMode(transaction: transactions.next()) else { return }
        send(request) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let response):
                guard response.payload.count == 2 else {
                    self.currentMode = nil
                    self.status = "Mode response did not contain exactly two bytes; no mode change is allowed"
                    return
                }
                let data = Array(response.payload)
                self.currentMode = (data[0], data[1])
                self.modeText = data[0] == 0 ? "Normal mode (0), parameter \(data[1])" : data[0] == 3 ? "Driver mode (3), parameter \(data[1])" : "Mode \(data[0]), parameter \(data[1])"
                self.status = "Current mode read successfully"
                self.log("mode_read", ["mode": data[0], "parameter": data[1]])
            case .failure(let error): self.status = error.localizedDescription; self.currentMode = nil
            }
        }
    }

    public var canTryDriverMode: Bool { ready && !busy && !keyboardEffectBusy && !restoreOwed && currentMode?.0 == 0 }

    public var canEditKeyboardLighting: Bool {
        ready && !keyboardEffectBusy && !closing && !restoreRequested
            && !restorationChain && (!restoreOwed || driverModeVerified)
    }

    public func refreshKeyboardLighting() {
        guard canEditKeyboardLighting else { return }
        keyboardEffectRequestSucceeded = false
        keyboardEffectBusy = true
        keyboardEffectStatus = "Reading keyboard lighting…"
        effectRequests.enqueue(.read)
        startLightingTimer(); pumpLighting()
    }

    /// Fixed, opt-in research commands. Normal mappings never call this path.
    public func runLightingLabCommand(_ operation: BluetoothLightingLabCommand,
                                      region: UInt8 = 0,
                                      completion: @escaping (Result<Data, Error>) -> Void) {
        guard ready, !busy, !keyboardEffectBusy, !driverModeVerified, !restoreOwed,
              !closing, !restoreRequested, !restorationChain else {
            completion(.failure(BluetoothFailure.message("Stop mappings and finish pending operations before a Bluetooth lighting experiment.")))
            return
        }
        do {
            let request = try operation.request(transaction: transactions.next(), region: region)
            send(request) { result in completion(result.map(\.payload)) }
        } catch { completion(.failure(error)) }
    }

    private func beginKeyboardEffectRead() {
        effectCommand(try! .readKeyboardEffectIDs(transaction: transactions.next())) { [weak self] response in
            guard let self else { return }
            let ids = Array(response.payload)
            guard !ids.isEmpty, ids.count <= 64, Set(ids).count == ids.count else {
                self.finishKeyboardEffect("The keyboard returned an unexpected effect list."); return
            }
            self.keyboardEffectIDs = ids
            self.log("keyboard_effect_ids", ["ids": ids])
            self.readCurrentKeyboardEffect()
        }
    }

    public func applyKeyboardEffect(_ effect: KeyboardEffect) {
        guard canEditKeyboardLighting, !keyboardEffectIDs.isEmpty else { return }
        keyboardEffectRequestSucceeded = false
        do {
            // Only the five recovered firmware effects can be written. The
            // advertised list omits effects also seen in native state / Synapse;
            // an explicit user selection can try one, followed by readback.
            _ = try Protocol30Request.keyboardEffect(transaction: 1, effect: effect)
            keyboardEffectBusy = true
            keyboardEffectStatus = "Applying keyboard lighting…"
            effectRequests.enqueue(.apply(effect))
            startLightingTimer(); pumpLighting()
        } catch { keyboardEffectStatus = error.localizedDescription }
    }

    private func readCurrentKeyboardEffect(expected: KeyboardEffect? = nil) {
        effectCommand(try! .readKeyboardEffect(transaction: transactions.next())) { [weak self] response in
            guard let self else { return }
            do {
                let effect = try KeyboardEffect(payload: response.payload)
                self.currentKeyboardEffect = effect
                self.log("keyboard_effect_read", ["id": effect.id, "flags": effect.flags, "rate": effect.rate,
                                                   "colors": effect.colors.map { Array($0.bytes) }])
                if let expected, effect != expected {
                    self.finishKeyboardEffect("The keyboard reported different settings. Press Read keyboard to refresh.")
                } else {
                    self.finishKeyboardEffect("Current effect: \(effect.kind?.name ?? "Other effect")", succeeded: true)
                }
            } catch { self.finishKeyboardEffect(error.localizedDescription) }
        }
    }

    // Explicit lighting settings work in normal mode as well as driver mode.
    // Restoration takes priority over every next step in this serial chain.
    private func effectCommand(_ request: Protocol30Request, completion: @escaping (Protocol30Response) -> Void) {
        guard ready, !closing, !restoreRequested, !restorationChain, !restoreOwed || driverModeVerified else {
            finishKeyboardEffect("Lighting update interrupted. Read the keyboard and try again."); return
        }
        send(request) { [weak self] result in
            guard let self else { return }
            guard !self.closing, !self.restoreRequested, !self.restorationChain,
                  !self.restoreOwed || self.driverModeVerified else {
                self.finishKeyboardEffect("Lighting update interrupted. Read the keyboard and try again."); return
            }
            switch result {
            case .success(let response): completion(response)
            case .failure(let error): self.finishKeyboardEffect("Lighting unavailable: \(error.localizedDescription)")
            }
        }
    }

    private func finishKeyboardEffect(_ message: String, succeeded: Bool = false) {
        keyboardEffectRequestSucceeded = succeeded
        keyboardEffectBusy = false
        keyboardEffectStatus = message
    }

    private func cancelQueuedKeyboardEffect() {
        guard !effectRequests.isEmpty else { return }
        effectRequests.cancel()
        finishKeyboardEffect("Lighting update interrupted. Read the keyboard and try again.")
    }

    public func readBattery() {
        guard ready, !busy, !restoreOwed || driverModeVerified else { return }
        batteryText = "Reading battery status…"
        batteryReadState = .reading
        guard let request = try? Protocol30Request.readBatteryList(transaction: transactions.next()) else { return }
        send(request) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let response):
                let ids = Array(response.payload)
                guard !ids.isEmpty, ids.count <= 16, Set(ids).count == ids.count else {
                    self.batteryFailed("The keyboard returned an unexpected battery list")
                    return
                }
                self.log("battery_list", ["ids": ids])
                self.readBatteryLevels(ids, readings: [])
            case .failure(let error): self.batteryFailed("Battery read failed: \(error.localizedDescription)")
            }
        }
    }

    private func readBatteryLevels(_ ids: [UInt8], readings: [String]) {
        guard let id = ids.first else {
            batteryText = readings.joined(separator: " · ")
            if let percent = batteryPercent { batteryReadState = .ready(percent) }
            return
        }
        guard ready, !restoreOwed || driverModeVerified,
              let request = try? Protocol30Request.readBatteryLevel(transaction: transactions.next(), batteryID: id) else {
            batteryFailed("Battery read interrupted; try again")
            return
        }
        send(request) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let response):
                guard let raw = response.payload.first else {
                    self.batteryFailed("The keyboard returned an empty battery level")
                    return
                }
                let percent = Int(raw) * 100 / 255
                if id == 1 || readings.isEmpty { self.batteryPercent = percent }
                self.log("battery_level", ["batteryID": id, "raw": raw, "percent": percent])
                let label = ids.count == 1 && readings.isEmpty ? "Battery" : "Battery \(id)"
                self.readBatteryLevels(Array(ids.dropFirst()), readings: readings + ["\(label): \(percent)%"])
            case .failure(let error): self.batteryFailed("Battery read failed: \(error.localizedDescription)")
            }
        }
    }

    private func batteryFailed(_ message: String) {
        batteryText = message
        batteryReadState = .failed(message)
    }

    public func tryDriverMode() {
        guard canTryDriverMode, let targetID, exactTargetID() == targetID, let currentMode else { return }
        guard logfile != nil else { status = "A diagnostic log is required before changing the mode"; return }
        let saved = SavedMode(peripheral: targetID, mode: currentMode.0, parameter: currentMode.1)
        // Recovery is durable before sending any state-changing command.
        do {
            try JSONEncoder().encode(saved).write(to: recoveryURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recoveryURL.path)
            let recoveryFile = try FileHandle(forWritingTo: recoveryURL)
            try recoveryFile.synchronize()
            try recoveryFile.close()
        } catch { status = "Cannot save restoration state; the keyboard was not changed"; return }
        original = saved
        brightnessUnavailable = false
        // A rejected indicator API stays disabled for this app session.
        // Repeated mapping starts must not repeat known-unsupported probes.
        lightingStatus = ""; lightingOperation = false
        brightnessSteps.clear(); requestedDialColor = nil; dialDeadline = nil; dialLightChanged = false
        lightingRegion = nil
        restoreOwed = true
        secondsRemaining = 60
        leaseDeadline = ProcessInfo.processInfo.systemUptime + 60
        restoreTimer?.invalidate()
        restoreTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.secondsRemaining = max(0, Int(ceil((self.leaseDeadline ?? 0) - ProcessInfo.processInfo.systemUptime)))
            if self.secondsRemaining == 0 { self.restoreTimer?.invalidate(); self.restore() }
            else if self.secondsRemaining % 10 == 0 && self.ready && !self.busy {
                self.verifyDriverMode()
            }
        }
        if let restoreTimer { RunLoop.main.add(restoreTimer, forMode: .common) }
        guard let request = try? Protocol30Request.deviceMode(transaction: transactions.next(), mode: 3, parameter: 0) else { restore(); return }
        status = "Enabling temporary driver mode…"
        send(request) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.verifyDriverMode()
            case .failure(let error):
                self.status = "Mode command failed: \(error.localizedDescription). Restoring the saved mode…"
                self.restore()
            }
        }
    }

    private func verifyDriverMode() {
        guard let request = try? Protocol30Request.readDeviceMode(transaction: transactions.next()) else { restore(); return }
        send(request) { [weak self] result in
            guard let self else { return }
            if case .success(let response) = result, response.payload == Data([3, 0]) {
                self.driverModeVerified = true
                self.currentMode = (3, 0)
                self.modeText = "Temporary driver mode (3)"
                self.status = "Test M1 and AI in Ergo Probe now. Original mode will be restored automatically."
                self.log("temporary_driver_mode_verified")
            } else {
                self.status = "Temporary driver mode was not verified. Restoring the original mode…"
                self.restore()
            }
        }
    }

    // The mapping app renews this short lease only while its input relay is alive.
    public func renewMappingLease() {
        guard restoreOwed, driverModeVerified, ready, !closing else { return }
        secondsRemaining = 60
        leaseDeadline = ProcessInfo.processInfo.systemUptime + 60
    }

    public func restore() {
        cancelQueuedKeyboardEffect()
        lightingTimer?.invalidate(); lightingTimer = nil
        indicatorBacklight.cancel()
        brightnessSteps.clear(); requestedDialColor = nil; dialDeadline = nil
        driverModeVerified = false
        guard restoreOwed, let original, !restorationChain else { return }
        restoreTimer?.invalidate(); restoreTimer = nil
        secondsRemaining = 0
        leaseDeadline = nil
        if pending != nil { restoreRequested = true; return }
        guard ready, target?.identifier == original.peripheral else { connect(); scheduleRestoreRetry(); return }
        restorationChain = true
        restoreOriginalMode(original)
    }

    private func restoreOriginalMode(_ original: SavedMode) {
        status = "Restoring the original keyboard mode…"
        guard let request = try? Protocol30Request.deviceMode(transaction: transactions.next(), mode: original.mode, parameter: original.parameter) else { return }
        send(request) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success: self.verifyRestoration(original)
            case .failure(let error):
                self.restorationChain = false
                self.status = "Restoration not confirmed: \(error.localizedDescription). Keep the keyboard connected."
                self.scheduleRestoreRetry()
            }
        }
    }

    // Lighting shares the acknowledged, single-command transport with mode/battery
    // reads. Never continue a lighting chain once restoration has been requested.
    public func adjustKeyboardBrightness(_ direction: Int) {
        guard driverModeVerified, !brightnessUnavailable else { return }
        guard brightnessSteps.append(direction) else {
            lightingStatus = "Too many brightness turns; let the keyboard finish adjusting."; return
        }
        startLightingTimer(); pumpLighting()
    }

    public func flashDialIndicator(_ color: DialColor) {
        guard driverModeVerified, !indicatorUnavailable else { return }
        requestedDialColor = color
        lastRequestedDialColor = color
        startLightingTimer(); pumpLighting()
    }

    private func startLightingTimer() {
        guard lightingTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.pumpLighting() }
        lightingTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }

    private func pumpLighting() {
        guard ready, !restoreRequested, !closing, !restorationChain else { return }
        if let request = effectRequests.takeIfIdle(commandBusy: busy, dialLightingBusy: lightingOperation) {
            switch request {
            case .read: beginKeyboardEffectRead()
            case .apply(let effect):
                do {
                    let command = try Protocol30Request.keyboardEffect(transaction: transactions.next(), effect: effect)
                    effectCommand(command) { [weak self] _ in self?.readCurrentKeyboardEffect(expected: effect) }
                } catch { finishKeyboardEffect(error.localizedDescription) }
            }
            return
        }
        guard !keyboardEffectBusy else { return }
        guard driverModeVerified else {
            lightingTimer?.invalidate(); lightingTimer = nil
            return
        }
        guard !busy, !lightingOperation else { return }
        // Retire the previous flash before processing brightness. A newer mode
        // selection supersedes its timeout and is coalesced to the latest color.
        if requestedDialColor != nil, !indicatorUnavailable {
            lightingOperation = true
            checkDialBacklight()
        } else if dialLightChanged, let deadline = dialDeadline,
                  ProcessInfo.processInfo.systemUptime >= deadline, let light = original?.dialLight {
            lightingOperation = true
            restoreDialLight(light) { [weak self] success in
                self?.lightingOperation = false
                if success { self?.dialLightChanged = false; self?.dialDeadline = nil }
            }
        } else if !brightnessSteps.isEmpty, !brightnessUnavailable {
            lightingOperation = true
            ensureLightingRegion(brightness: true) { [weak self] in self?.changeBrightness() }
        } else if requestedDialColor == nil, brightnessSteps.isEmpty, !dialLightChanged {
            lightingTimer?.invalidate(); lightingTimer = nil
        }
    }

    private func ensureLightingRegion(brightness: Bool, completion: @escaping () -> Void) {
        if lightingRegion != nil { completion(); return }
        lightingCommand(try! .readLightingRegions(transaction: transactions.next()), brightness: brightness) { [weak self] response in
            guard let self else { return }
            let regions = response.payload.map { $0 & 63 }.filter { $0 != 0 }
            guard let region = regions.first else { self.lightingFailed("No keyboard lighting region was returned", brightness: brightness); return }
            self.lightingRegion = region; completion()
        }
    }

    private func checkDialBacklight() {
        ensureLightingRegion(brightness: false) { [weak self] in
            guard let self, let region = self.lightingRegion else { return }
            self.lightingCommand(try! .readKeyboardBrightness(transaction: self.transactions.next(), region: region)) { [weak self] response in
                guard let self else { return }
                guard response.payload.count == 1, let raw = response.payload.first else {
                    self.lightingFailed("Unexpected brightness response", brightness: false); return
                }
                self.log("dial_indicator_backlight_checked", ["raw": raw])
                guard self.indicatorBacklight.mayFlash(rawBrightness: raw) else {
                    self.requestedDialColor = nil; self.lightingOperation = false
                    self.lightingStatus = "Keyboard mode indicator needs the backlight above 0%"
                    return
                }
                self.probeRGBTargets()
            }
        }
    }

    private func lightingCommand(_ request: Protocol30Request, brightness: Bool = false,
                                 rejected: ((UInt8) -> Void)? = nil, completion: @escaping (Protocol30Response) -> Void) {
        guard driverModeVerified, !restoreRequested else { lightingOperation = false; return }
        send(request) { [weak self] result in
            guard let self else { return }
            guard self.driverModeVerified, !self.restoreRequested else { self.lightingOperation = false; return }
            switch result {
            case .success(let response): completion(response)
            case .failure(let error):
                if case .rejected(let status) = error as? BluetoothFailure, let rejected { rejected(status) }
                else { self.lightingFailed(error.localizedDescription, brightness: brightness) }
            }
        }
    }

    private func lightingFailed(_ message: String, brightness: Bool) {
        lightingOperation = false
        if brightness { brightnessUnavailable = true; brightnessSteps.clear() }
        else {
            indicatorUnavailable = true; requestedDialColor = nil
            if dialLightChanged { dialDeadline = ProcessInfo.processInfo.systemUptime }
        }
        lightingStatus = "\(brightness ? "Keyboard brightness" : "Dial indicator") unavailable: \(message)"
        log("lighting_failed", ["brightness": brightness, "error": message])
    }

    private func changeBrightness() {
        guard let region = lightingRegion else { lightingOperation = false; return }
        lightingCommand(try! .readKeyboardBrightness(transaction: transactions.next(), region: region), brightness: true) { [weak self] response in
            guard let self else { return }
            guard response.payload.count == 1, let raw = response.payload.first else {
                self.lightingFailed("Unexpected brightness response", brightness: true); return
            }
            let target = self.brightnessSteps.takeTarget(from: raw)
            if target == raw { self.brightnessFinished(raw); return }
            self.lightingCommand(try! .keyboardBrightness(transaction: self.transactions.next(), raw: target), brightness: true) { [weak self] _ in
                guard let self else { return }
                self.lightingCommand(try! .readKeyboardBrightness(transaction: self.transactions.next(), region: region), brightness: true) { [weak self] reply in
                    guard let self else { return }
                    guard reply.payload == Data([target]) else {
                        self.lightingFailed("Brightness read-back did not match", brightness: true); return
                    }
                    self.brightnessFinished(target)
                }
            }
        }
    }

    private func brightnessFinished(_ raw: UInt8) {
        lightingOperation = false
        let percent = Int(ceil(Double(raw) / 255 * 100))
        keyboardBrightnessPercent = percent
        lightingStatus = "Keyboard brightness: \(percent)%"
        log("keyboard_brightness_verified", ["percent": percent, "raw": raw])
        if indicatorBacklight.retryAfterBrightnessChange(rawBrightness: raw), let color = lastRequestedDialColor {
            indicatorUnavailable = false
            flashDialIndicator(color)
        }
    }

    private func probeRGBTargets() {
        // Get LED List returns opaque target bytes. Unlike the Chroma-region
        // getter, the vendor LED-list method does not mask their high bits.
        // Read these IDs literally; no inferred address is ever written.
        lightingOperation = true
        lightingCommand(try! .readLEDList(transaction: transactions.next()), rejected: { [weak self] status in
            self?.log("led_inventory_rejected", ["status": status])
            self?.finishIndicatorDiscovery()
        }) { [weak self] response in
            guard let self else { return }
            let ids = Array(Set(response.payload).sorted().prefix(16))
            self.log("led_raw_target_candidates", ["payload": response.payload.hex, "targets": ids])
            self.readLEDTargets(ids)
        }
    }

    private func readLEDTargets(_ targets: [UInt8]) {
        guard let target = targets.first else { finishIndicatorDiscovery(); return }
        lightingCommand(try! .readLEDType(transaction: transactions.next(), ledID: target), rejected: { [weak self] status in
            self?.log("led_type_rejected", ["target": target, "status": status])
            self?.readRGBTarget(target, remaining: Array(targets.dropFirst()))
        }) { [weak self] response in
            self?.log("led_type_response", ["target": target, "payload": response.payload.hex])
            self?.readRGBTarget(target, remaining: Array(targets.dropFirst()))
        }
    }

    private func readRGBTarget(_ target: UInt8, remaining: [UInt8]) {
        lightingCommand(try! .readDialColor(transaction: transactions.next(), ledID: target), rejected: { [weak self] status in
            self?.log("led_raw_rgb_rejected", ["target": target, "status": status])
            self?.readLEDTargets(remaining)
        }) { [weak self] response in
            self?.log("led_raw_rgb_response", ["target": target, "payload": response.payload.hex])
            // Even a successful read must be correlated with native dial-mode
            // changes before it can identify the physical indicator.
            self?.readLEDTargets(remaining)
        }
    }

    private func finishIndicatorDiscovery() {
        lightingOperation = false
        indicatorUnavailable = true
        requestedDialColor = nil
        lightingStatus = "Dial indicator under investigation · diagnostic reads recorded"
    }

    /// Research-only comparison in normal mode. No driver-mode, LED, or knob
    /// setters: the USB getter's Bluetooth equivalents are not yet established.
    public func inspectNativeDial(completion: @escaping ([String]) -> Void) {
        guard ready, !busy, !restoreOwed, currentMode?.0 == 0 else {
            completion(["Normal-mode Bluetooth connection is required."]); return
        }
        inspectNativeDialRequests([0x84, 0x93, 0x95], results: [], completion: completion)
    }

    private func inspectNativeDialRequests(_ ids: [UInt8], results: [String],
                                           completion: @escaping ([String]) -> Void) {
        guard let id = ids.first else { completion(results); return }
        guard ready, !busy, !restoreOwed, currentMode?.0 == 0 else {
            completion(results + ["Read-only comparison interrupted."]); return
        }
        // 84 is the original RGB baseline. 93 is the USB current-knob getter;
        // 95 tests the +2 offset used by the Bluetooth LED-state getter.
        let request = try! Protocol30Request(transaction: transactions.next(), commandClass: 6,
                                             commandID: id, argument6: 1, argument7: 39)
        send(request) { [weak self] result in
            guard let self else { return }
            let line: String
            switch result {
            case .success(let reply):
                let value = reply.payload.count <= 8 ? reply.payload.hex : "Unexpected reply length: \(reply.payload.count)"
                self.log("native_dial_candidate_response", ["commandID": id, "result": value])
                line = "06/\(String(id, radix: 16)): \(value)"
            case .failure(let error):
                self.log("native_dial_candidate_failed", ["commandID": id, "error": error.localizedDescription])
                line = "06/\(String(id, radix: 16)): \(error.localizedDescription)"
            }
            self.inspectNativeDialRequests(Array(ids.dropFirst()), results: results + [line], completion: completion)
        }
    }

    private func restoreLightCommand(_ request: Protocol30Request, failed: @escaping () -> Void,
                                     completion: @escaping (Protocol30Response) -> Void) {
        send(request) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let response): completion(response)
            case .failure:
                self.dialDeadline = ProcessInfo.processInfo.systemUptime + 5
                self.log("dial_light_restoration_unconfirmed"); failed()
            }
        }
    }

    private func restoreDialLight(_ light: SavedDialLight, completion: @escaping (Bool) -> Void) {
        guard let color = light.color else { restoreDialLightState(light, completion: completion); return }
        // First read: a rejected optional color write may have changed nothing.
        // Avoid making restoration depend on a setter the device rejected.
        restoreLightCommand(try! .readDialColor(transaction: transactions.next()), failed: { completion(false) }) { [weak self] response in
            guard let self else { return }
            guard (3...4).contains(response.payload.count) else {
                self.dialDeadline = ProcessInfo.processInfo.systemUptime + 5; completion(false); return
            }
            if Data(response.payload.prefix(3)) == color.bytes,
               light.brightness == nil || response.payload.count == 4 && response.payload[3] == light.brightness {
                self.restoreDialLightState(light, completion: completion)
            } else {
                self.restoreLightCommand(try! .dialColor(transaction: self.transactions.next(), color: color, brightness: light.brightness ?? 255), failed: { completion(false) }) { [weak self] _ in
                    guard let self else { return }
                    self.restoreLightCommand(try! .readDialColor(transaction: self.transactions.next()), failed: { completion(false) }) { [weak self] response in
                        guard let self else { return }
                        guard Data(response.payload.prefix(3)) == color.bytes,
                              light.brightness == nil || response.payload.count == 4 && response.payload[3] == light.brightness else {
                            self.dialDeadline = ProcessInfo.processInfo.systemUptime + 5; completion(false); return
                        }
                        self.restoreDialLightState(light, completion: completion)
                    }
                }
            }
        }
    }

    private func restoreDialLightState(_ light: SavedDialLight, completion: @escaping (Bool) -> Void) {
        let expected = Data([light.on ? UInt8(1) : 0])
        restoreLightCommand(try! .readDialLightState(transaction: transactions.next()), failed: { completion(false) }) { [weak self] response in
            guard let self else { return }
            if response.payload == expected { completion(true); return }
            guard response.payload.count == 1, response.payload[0] <= 1 else {
                self.dialDeadline = ProcessInfo.processInfo.systemUptime + 5; completion(false); return
            }
            self.restoreLightCommand(try! .dialLightState(transaction: self.transactions.next(), on: light.on), failed: { completion(false) }) { [weak self] _ in
                guard let self else { return }
                self.restoreLightCommand(try! .readDialLightState(transaction: self.transactions.next()), failed: { completion(false) }) { [weak self] response in
                    guard let self else { return }
                    let success = response.payload == expected
                    if !success { self.dialDeadline = ProcessInfo.processInfo.systemUptime + 5 }
                    completion(success)
                }
            }
        }
    }

    private func verifyRestoration(_ saved: SavedMode) {
        guard let request = try? Protocol30Request.readDeviceMode(transaction: transactions.next()) else { return }
        send(request) { [weak self] result in
            guard let self else { return }
            if case .success(let response) = result, response.payload == Data([saved.mode, saved.parameter]) {
                self.log("original_mode_restored", ["mode": saved.mode, "parameter": saved.parameter])
                if let light = saved.dialLight {
                    self.restoreDialLight(light) { [weak self] success in
                        guard let self else { return }
                        if success { self.finishRestoration(saved) }
                        else {
                            self.restorationChain = false
                            self.status = "Normal keyboard mode restored; dial light restoration is pending. Keep PT Ergo connected."
                            self.scheduleRestoreRetry()
                        }
                    }
                } else { self.finishRestoration(saved) }
            } else {
                self.restorationChain = false
                self.status = "Restoration has not been verified; retrying while PT Ergo is connected…"
                self.scheduleRestoreRetry()
            }
        }
    }

    private func finishRestoration(_ saved: SavedMode) {
        restorationChain = false; lightingOperation = false; dialLightChanged = false
        driverModeVerified = false; restoreOwed = false; original = nil
        currentMode = (saved.mode, saved.parameter)
        modeText = "Original mode restored (\(saved.mode))"
        status = "Original keyboard mode restored and verified"
        retryTimer?.invalidate(); retryTimer = nil
        try? FileManager.default.removeItem(at: recoveryURL)
        if closing { NSApplication.shared.reply(toApplicationShouldTerminate: true) }
    }

    private func scheduleRestoreRetry() {
        guard restoreOwed, retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.retryTimer = nil
            self.restore()
        }
    }

    public func requestTermination() -> NSApplication.TerminateReply {
        guard restoreOwed else { return .terminateNow }
        closing = true
        restore()
        return .terminateLater
    }
}

private extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
