import Foundation
import IOKit.hid
import ErgoCore

private func number(_ device: IOHIDDevice, _ key: String) -> Int {
    (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
}

private func string(_ device: IOHIDDevice, _ key: String) -> String {
    IOHIDDeviceGetProperty(device, key as CFString) as? String ?? ""
}

final class HIDEndpoint {
    let device: IOHIDDevice
    let log: CaptureLog
    let buffer: UnsafeMutablePointer<UInt8>
    let capacity: Int
    let endpointID: String
    var opened = false

    init(device: IOHIDDevice, log: CaptureLog) {
        self.device = device
        self.log = log
        capacity = max(64, min(65536, number(device, kIOHIDMaxInputReportSizeKey)))
        buffer = .allocate(capacity: capacity)
        buffer.initialize(repeating: 0, count: capacity)
        var identifier: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &identifier)
        endpointID = String(identifier)
    }

    func start() {
        // No seize flag: the keyboard continues delivering input to macOS.
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        log.record("hid_open", ["endpoint": endpointID, "result": Int(result)])
        guard result == kIOReturnSuccess else { return }
        opened = true
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, capacity, { context, result, _, type, id, bytes, count in
            guard let context, result == kIOReturnSuccess else { return }
            let endpoint = Unmanaged<HIDEndpoint>.fromOpaque(context).takeUnretainedValue()
            endpoint.log.record("hid_report", ["endpoint": endpoint.endpointID, "reportID": id,
                "reportType": type.rawValue, "hex": Data(bytes: bytes, count: count).map { String(format: "%02x", $0) }.joined()])
        }, context)
        IOHIDDeviceRegisterInputValueCallback(device, { context, result, _, value in
            guard let context, result == kIOReturnSuccess else { return }
            let endpoint = Unmanaged<HIDEndpoint>.fromOpaque(context).takeUnretainedValue()
            let element = IOHIDValueGetElement(value)
            endpoint.log.record("hid_value", ["endpoint": endpoint.endpointID,
                "reportID": IOHIDElementGetReportID(element), "page": IOHIDElementGetUsagePage(element),
                "usage": IOHIDElementGetUsage(element), "value": IOHIDValueGetIntegerValue(value),
                "timestamp": IOHIDValueGetTimeStamp(value)])
        }, context)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    func stop() {
        guard opened else { return }
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, capacity, nil, nil)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        opened = false
    }

    deinit { stop(); buffer.deallocate() }
}

final class HIDProbe: ObservableObject {
    @Published var status = "Ready — capture is stopped"
    @Published var running = false
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var endpoints: [HIDEndpoint] = []
    private let log: CaptureLog

    init(log: CaptureLog) {
        self.log = log
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: ErgoTarget.vendorID,
            kIOHIDProductIDKey: ErgoTarget.productID, kIOHIDTransportKey: ErgoTarget.transport] as CFDictionary)
    }

    func devices() -> [IOHIDDevice] {
        (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []).filter {
            ErgoTarget.matches(vendor: number($0, kIOHIDVendorIDKey), product: number($0, kIOHIDProductIDKey),
                               transport: string($0, kIOHIDTransportKey))
        }
    }

    func inventory() -> [[String: Any]] {
        devices().map { device in
            var row: [String: Any] = ["vendor": number(device, kIOHIDVendorIDKey),
                "product": number(device, kIOHIDProductIDKey), "name": string(device, kIOHIDProductKey),
                "transport": string(device, kIOHIDTransportKey), "maxInputReport": number(device, kIOHIDMaxInputReportSizeKey),
                "primaryPage": number(device, kIOHIDPrimaryUsagePageKey), "primaryUsage": number(device, kIOHIDPrimaryUsageKey)]
            if let data = IOHIDDeviceGetProperty(device, kIOHIDReportDescriptorKey as CFString) as? Data {
                row["descriptor"] = data.map { String(format: "%02x", $0) }.joined()
            }
            return row
        }
    }

    // CoreBluetooth's stable peripheral identifier is taken from this exact HID device.
    func peripheralIDs() -> [UUID] {
        devices().compactMap { UUID(uuidString: string($0, "PhysicalDeviceUniqueID")) }
    }

    func start() {
        guard !running else { return }
        do { try log.begin() } catch { status = error.localizedDescription; return }
        log.record("input_access", ["status": IOHIDCheckAccess(kIOHIDRequestTypeListenEvent).rawValue])
        let matched = devices()
        guard !matched.isEmpty else { status = "PT Ergo is not connected over Bluetooth"; log.end(); return }
        inventory().forEach { log.record("hid_inventory", $0) }
        endpoints = matched.map { HIDEndpoint(device: $0, log: log) }
        endpoints.forEach { $0.start() }
        running = endpoints.contains { $0.opened }
        status = running ? "Listening to PT Ergo only" : "Input access unavailable — check Input Monitoring in System Settings"
        if !running { endpoints.removeAll(); log.end() }
    }

    func stop() {
        endpoints.forEach { $0.stop() }
        endpoints.removeAll()
        running = false
        status = "Capture stopped"
    }
}
