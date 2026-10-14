import Foundation
import CoreBluetooth
import IOKit.hid
import AppKit
import ErgoCore

struct SavedMode: Codable {
    let peripheral: UUID
    let mode: UInt8
    let parameter: UInt8
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
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
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
        complete(response.succeeded ? .success(response) : .failure(BluetoothFailure.message("Keyboard response status \(response.status)")))
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
            ready = false
            writeCharacteristic = nil
            if let target, target.state == .connected { central?.cancelPeripheralConnection(target) }
        }
        command.completion(result)
        if restoreRequested, pending == nil { restoreRequested = false; restore() }
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

    public var canTryDriverMode: Bool { ready && !busy && !restoreOwed && currentMode?.0 == 0 }

    public func readBattery() {
        guard ready, !busy, !restoreOwed || driverModeVerified else { return }
        batteryText = "Reading battery status…"
        guard let request = try? Protocol30Request.readBatteryList(transaction: transactions.next()) else { return }
        send(request) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let response):
                let ids = Array(response.payload)
                guard !ids.isEmpty, ids.count <= 16, Set(ids).count == ids.count else {
                    self.batteryText = "The keyboard returned an unexpected battery list"
                    return
                }
                self.log("battery_list", ["ids": ids])
                self.readBatteryLevels(ids, readings: [])
            case .failure(let error): self.batteryText = "Battery read failed: \(error.localizedDescription)"
            }
        }
    }

    private func readBatteryLevels(_ ids: [UInt8], readings: [String]) {
        guard let id = ids.first else {
            batteryText = readings.joined(separator: " · ")
            return
        }
        guard ready, !restoreOwed || driverModeVerified,
              let request = try? Protocol30Request.readBatteryLevel(transaction: transactions.next(), batteryID: id) else {
            batteryText = "Battery read interrupted; try again"
            return
        }
        send(request) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let response):
                guard let raw = response.payload.first else {
                    self.batteryText = "The keyboard returned an empty battery level"
                    return
                }
                let percent = Int(raw) * 100 / 255
                if id == 1 || readings.isEmpty { self.batteryPercent = percent }
                self.log("battery_level", ["batteryID": id, "raw": raw, "percent": percent])
                let label = ids.count == 1 && readings.isEmpty ? "Battery" : "Battery \(id)"
                self.readBatteryLevels(Array(ids.dropFirst()), readings: readings + ["\(label): \(percent)%"])
            case .failure(let error): self.batteryText = "Battery read failed: \(error.localizedDescription)"
            }
        }
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
        driverModeVerified = false
        guard restoreOwed, let original else { return }
        restoreTimer?.invalidate(); restoreTimer = nil
        secondsRemaining = 0
        leaseDeadline = nil
        if pending != nil { restoreRequested = true; return }
        guard ready, target?.identifier == original.peripheral else { connect(); scheduleRestoreRetry(); return }
        status = "Restoring the original keyboard mode…"
        guard let request = try? Protocol30Request.deviceMode(transaction: transactions.next(), mode: original.mode, parameter: original.parameter) else { return }
        send(request) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success: self.verifyRestoration(original)
            case .failure(let error):
                self.status = "Restoration not confirmed: \(error.localizedDescription). Keep the keyboard connected."
                self.scheduleRestoreRetry()
            }
        }
    }

    private func verifyRestoration(_ saved: SavedMode) {
        guard let request = try? Protocol30Request.readDeviceMode(transaction: transactions.next()) else { return }
        send(request) { [weak self] result in
            guard let self else { return }
            if case .success(let response) = result, response.payload == Data([saved.mode, saved.parameter]) {
                self.log("original_mode_restored", ["mode": saved.mode, "parameter": saved.parameter])
                self.driverModeVerified = false
                self.restoreOwed = false
                self.original = nil
                self.currentMode = (saved.mode, saved.parameter)
                self.modeText = "Original mode restored (\(saved.mode))"
                self.status = "Original keyboard mode restored and verified"
                self.retryTimer?.invalidate(); self.retryTimer = nil
                try? FileManager.default.removeItem(at: self.recoveryURL)
                if self.closing { NSApplication.shared.reply(toApplicationShouldTerminate: true) }
            } else {
                self.status = "Restoration has not been verified; retrying while PT Ergo is connected…"
                self.scheduleRestoreRetry()
            }
        }
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
