import Foundation
import IOKit.hid
import ErgoCore

final class KeyboardRelay {
    var onReport: ((UInt32, Data) -> Void)?
    var onDisconnect: (() -> Void)?
    private var device: IOHIDDevice?
    private var buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private var opened = false
    init() { buffer.initialize(repeating: 0, count: 64) }
    func start() throws {
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
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard result == kIOReturnSuccess else { throw MappingValidationError.message("PT Ergo could not be opened exclusively (\(result)). Close the diagnostic apps and check Input Monitoring.") }
        self.device = device; opened = true
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { context, result, _, _, id, bytes, count in
            guard let context else { return }
            let relay = Unmanaged<KeyboardRelay>.fromOpaque(context).takeUnretainedValue()
            guard result == kIOReturnSuccess else { relay.onDisconnect?(); return }
            relay.onReport?(id, Data(bytes: bytes, count: count))
        }, context)
        IOHIDDeviceRegisterRemovalCallback(device, { context, _, _ in
            guard let context else { return }
            Unmanaged<KeyboardRelay>.fromOpaque(context).takeUnretainedValue().onDisconnect?()
        }, context)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }
    func stop() {
        guard opened, let device else { return }
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDDeviceRegisterRemovalCallback(device, nil, nil)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, nil, nil)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        self.device = nil; opened = false
    }
    deinit { stop(); buffer.deallocate() }
}
