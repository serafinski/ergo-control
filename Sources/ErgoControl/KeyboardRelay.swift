import Foundation
import IOKit.hid
import ErgoCore
import ErgoHID

final class KeyboardRelay {
    var onReport: ((UInt32, Data) -> Void)?
    var onDisconnect: (() -> Void)?
    var onFailure: ((String) -> Void)?
    private var helper: HelperInputClient?
    private var device: IOHIDDevice?
    private var buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private var opened = false
    private(set) var accessMode = InputAccessMode.fullKeyboard
    init() { buffer.initialize(repeating: 0, count: 64) }
    func start(usingHelper: Bool, completion: @escaping (Result<InputAccessMode, Error>) -> Void) {
        stop()
        if usingHelper {
            accessMode = .fullKeyboard
            let client = HelperInputClient(); helper = client
            client.onReport = { [weak self] id, bytes in self?.onReport?(id, bytes) }
            client.onFailure = { [weak self] message in self?.onFailure?(message) }
            client.start { [weak self, weak client] result in
                guard let self, let client, self.helper === client else { return }
                switch result {
                case .success: self.recordOpen(kIOReturnSuccess, mode: .fullKeyboard); completion(.success(.fullKeyboard))
                case .failure(let error): completion(.failure(error))
                }
            }
        } else {
            do { try startLocal(); completion(.success(accessMode)) }
            catch { completion(.failure(error)) }
        }
    }
    private func startLocal() throws {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: ErgoTarget.vendorID,
            kIOHIDProductIDKey: ErgoTarget.productID, kIOHIDTransportKey: ErgoTarget.transport] as CFDictionary)
        let matched = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []).filter {
            let vid = (IOHIDDeviceGetProperty($0, kIOHIDVendorIDKey as CFString) as? NSNumber)?.intValue ?? 0
            let pid = (IOHIDDeviceGetProperty($0, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
            let transport = IOHIDDeviceGetProperty($0, kIOHIDTransportKey as CFString) as? String ?? ""
            return ErgoTarget.matches(vendor: vid, product: pid, transport: transport)
        }
        guard matched.count == 1, let device = matched.first else { throw MappingValidationError.message("Connect exactly one PT Ergo over Bluetooth") }
        var result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        accessMode = .fullKeyboard
        recordOpen(result, mode: .fullKeyboard)
        if result == kIOReturnNotPrivileged {
            // Extra keys need observation only. Do not relay native key/dial input.
            result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            accessMode = .macroButtons
            recordOpen(result, mode: .macroButtons)
        }
        guard result == kIOReturnSuccess else {
            if result == kIOReturnNotPermitted {
                throw MappingValidationError.message("Input access was denied. Refresh Ergo Control’s Input Monitoring entry for this build, then reopen it.")
            }
            throw MappingValidationError.message("PT Ergo could not be opened (\(result)). Close the diagnostic apps and retry.")
        }
        self.device = device; opened = true
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { context, result, _, _, id, bytes, count in
            guard let context else { return }
            let relay = Unmanaged<KeyboardRelay>.fromOpaque(context).takeUnretainedValue()
            guard result == kIOReturnSuccess else { relay.onDisconnect?(); return }
            guard relay.accessMode.accepts(reportID: id) else { return }
            relay.onReport?(id, Data(bytes: bytes, count: count))
        }, context)
        IOHIDDeviceRegisterRemovalCallback(device, { context, _, _ in
            guard let context else { return }
            Unmanaged<KeyboardRelay>.fromOpaque(context).takeUnretainedValue().onDisconnect?()
        }, context)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }
    private func recordOpen(_ result: IOReturn, mode: InputAccessMode) {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ErgoControl/Settings")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = folder.appendingPathComponent("input-status.json")
        let fields: [String: Any] = ["result": Int(result), "mode": mode.rawValue, "time": ISO8601DateFormatter().string(from: Date())]
        if let data = try? JSONSerialization.data(withJSONObject: fields, options: .sortedKeys) {
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
    func setCapsLock(_ enabled: Bool, completion: @escaping (Int32) -> Void) {
        guard accessMode == .fullKeyboard else { return }
        if let helper { helper.setCapsLock(enabled, completion: completion) }
        else if opened, let device { completion(CapsLockIndicator.set(enabled, on: device)) }
    }
    func stop() {
        helper?.stop(); helper = nil
        guard opened, let device else { return }
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDDeviceRegisterRemovalCallback(device, nil, nil)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, nil, nil)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        self.device = nil; opened = false
    }
    deinit { stop(); buffer.deallocate() }
}
