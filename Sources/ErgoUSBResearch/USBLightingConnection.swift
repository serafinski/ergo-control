import Foundation
import CryptoKit
import IOKit
import IOKit.hid
import ErgoCore

/// Opt-in lighting experiments only. The existing USBInspector remains read-only.
public final class USBLightingConnection {
    private let manager: IOHIDManager
    private let device: IOHIDDevice
    private var transaction: UInt8 = 0
    public let identity: String

    public init() throws {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x1532,
                                               kIOHIDProductIDKey: 0x02c4] as CFDictionary)
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        let matches = devices.filter {
            number($0, kIOHIDVendorIDKey) == 0x1532 && number($0, kIOHIDProductIDKey) == 0x02c4 &&
            (IOHIDDeviceGetProperty($0, kIOHIDTransportKey as CFString) as? String) == "USB" &&
            interfaceNumber($0) == 3 && (number($0, kIOHIDMaxFeatureReportSizeKey) ?? 0) >= 90
        }
        guard matches.count == 1, let found = matches.first else {
            throw LightingLabError.message("No single PT Ergo USB interface found. Connect a USB data cable and select wired mode on the keyboard. Bluetooth and receiver zone writes are not tested here.")
        }
        device = found
        // Hash a stable device identifier; never print it or a serial number.
        let serial = IOHIDDeviceGetProperty(found, kIOHIDSerialNumberKey as CFString) as? String
        let physical = IOHIDDeviceGetProperty(found, "PhysicalDeviceUniqueID" as CFString) as? String
        guard let unique = [serial, physical].compactMap({ $0 }).first(where: { !$0.isEmpty }) else {
            throw LightingLabError.message("USB device has no stable identity for recovery; no lighting writes were made.")
        }
        identity = SHA256.hash(data: Data(("1532:02c4:" + unique).utf8)).map { String(format: "%02x", $0) }.joined()
        let result = IOHIDDeviceOpen(found, 0)
        guard result == kIOReturnSuccess else {
            throw LightingLabError.message("Cannot open PT Ergo USB configuration interface (\(result)).")
        }
    }

    deinit { IOHIDDeviceClose(device, 0) }

    public func exchange(_ command: USBLightingCommand) throws -> Data {
        transaction = transaction % 31 + 1
        let packet = try command.request(transaction: transaction)
        let sent = packet.withUnsafeBytes {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0,
                                $0.bindMemory(to: UInt8.self).baseAddress!, packet.count)
        }
        guard sent == kIOReturnSuccess else {
            throw LightingLabError.message("USB lighting transfer failed (\(sent)).")
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        repeat {
            Thread.sleep(forTimeInterval: 0.08)
            var bytes = [UInt8](repeating: 0, count: 90)
            var count = bytes.count
            let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0, &bytes, &count)
            guard result == kIOReturnSuccess else {
                throw LightingLabError.message("USB lighting readback failed (\(result)).")
            }
            let reply = try command.response(Data(bytes.prefix(count)), transaction: transaction)
            if reply.status == 1 || reply.status == 3 { continue }
            guard reply.status == 2 else {
                throw LightingLabError.message("USB lighting command \(command.commandID) rejected (status \(reply.status)).")
            }
            return reply.payload
        } while ProcessInfo.processInfo.systemUptime < deadline
        throw LightingLabError.message("USB lighting reply timed out.")
    }

    public func readEffect() throws -> KeyboardEffect {
        try USBLightingCommand.decodeEffect(exchange(.readEffect))
    }

    public func setEffect(_ effect: KeyboardEffect) throws {
        _ = try exchange(.effect(effect))
        guard try readEffect() == effect else {
            throw LightingLabError.message("USB effect readback differs from requested settings.")
        }
    }
}
