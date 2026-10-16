import Foundation
import IOKit
import IOKit.hid
import ErgoCore

struct PairedKeyboardSnapshot {
    let matchingServices: Int
    let endpointIDs: Set<UUID>
    let missingIdentity: Bool
    let lookupResult: Int32
    var uniqueID: UUID? { !missingIdentity && endpointIDs.count == 1 ? endpointIDs.first : nil }

    func connectionTarget(recoveryID: UUID?) -> UUID? {
        guard lookupResult == KERN_SUCCESS else { return nil }
        guard let recoveryID else { return uniqueID }
        // Recovery already names a previously validated paired endpoint. It can
        // be reconnected before macOS publishes its live HID node after login.
        // A present conflicting/ambiguous keyboard must never be substituted.
        guard matchingServices == 0 || uniqueID == recoveryID else { return nil }
        return recoveryID
    }

    init(properties: [[String: Any]], lookupResult: Int32 = KERN_SUCCESS) {
        self.lookupResult = lookupResult
        let matches = properties.filter {
            ErgoTarget.matches(vendor: ($0[kIOHIDVendorIDKey] as? NSNumber)?.intValue ?? 0,
                               product: ($0[kIOHIDProductIDKey] as? NSNumber)?.intValue ?? 0,
                               transport: $0[kIOHIDTransportKey] as? String ?? "")
        }
        let identities = matches.compactMap { ($0["PhysicalDeviceUniqueID"] as? String).flatMap(UUID.init(uuidString:)) }
        matchingServices = matches.count
        endpointIDs = Set(identities)
        missingIdentity = identities.count != matches.count
    }
}

/// Observe registry metadata, without opening/seizing HID devices or subscribing
/// to keyboard reports. Arrival notifications bypass the battery polling delay.
public final class PairedKeyboardDiscovery {
    private var port: IONotificationPortRef?
    private var arrivals: io_iterator_t = 0
    private var removals: io_iterator_t = 0
    private var onChange: (() -> Void)?
    private static var matching: CFDictionary {
        [kIOProviderClassKey: "IOHIDDevice", kIOPropertyMatchKey: [
            kIOHIDVendorIDKey: ErgoTarget.vendorID, kIOHIDProductIDKey: ErgoTarget.productID,
            kIOHIDTransportKey: ErgoTarget.transport
        ]] as CFDictionary
    }
    static func snapshot() -> PairedKeyboardSnapshot {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else {
            return PairedKeyboardSnapshot(properties: [], lookupResult: result)
        }
        defer { IOObjectRelease(iterator) }
        var properties: [[String: Any]] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            var value: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &value, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let row = value?.takeRetainedValue() as? [String: Any] { properties.append(row) }
            IOObjectRelease(service)
        }
        return PairedKeyboardSnapshot(properties: properties)
    }
    func start(onChange: @escaping () -> Void, onFailure: @escaping (Int32) -> Void) {
        stop()
        self.onChange = onChange
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { onFailure(-1); return }
        self.port = port
        IONotificationPortSetDispatchQueue(port, .main)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { context, iterator in
            guard let context else { return }
            let observer = Unmanaged<PairedKeyboardDiscovery>.fromOpaque(context).takeUnretainedValue()
            observer.drain(iterator, notify: true)
        }
        let first = IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, Self.matching, callback, context, &arrivals)
        if first == KERN_SUCCESS { drain(arrivals, notify: false) }
        let last = IOServiceAddMatchingNotification(port, kIOTerminatedNotification, Self.matching, callback, context, &removals)
        if last == KERN_SUCCESS { drain(removals, notify: false) }
        if first != KERN_SUCCESS || last != KERN_SUCCESS {
            let result = first != KERN_SUCCESS ? first : last
            stop(); onFailure(result)
        }
    }
    private func drain(_ iterator: io_iterator_t, notify: Bool) {
        var changed = false
        while case let service = IOIteratorNext(iterator), service != 0 {
            changed = true; IOObjectRelease(service)
        }
        // Draining to exhaustion is required to rearm IOKit's notification.
        if notify && changed { onChange?() }
    }
    func stop() {
        onChange = nil
        if arrivals != 0 { IOObjectRelease(arrivals); arrivals = 0 }
        if removals != 0 { IOObjectRelease(removals); removals = 0 }
        if let port {
            IONotificationPortSetDispatchQueue(port, nil)
            IONotificationPortDestroy(port)
        }
        port = nil
    }
    deinit { stop() }

    public static func checkCommandLine() -> Never {
        let monitor = PairedKeyboardDiscovery()
        var failed = false
        monitor.start(onChange: { print("PT Ergo registry arrival/removal observed.") }, onFailure: {
            failed = true; print("Registry observer failed: \($0)")
        })
        let value = snapshot()
        print("PT Ergo services: \(value.matchingServices); unique Bluetooth endpoint: \(value.uniqueID != nil); registry notifications: \(!failed)")
        monitor.stop()
        exit(failed || value.uniqueID == nil ? 1 : 0)
    }
}
