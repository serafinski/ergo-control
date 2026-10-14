import Foundation
import IOKit
import IOKit.hid
import ErgoCore

// Only the documented Pro Type Ergo USB configuration interface. No input
// callbacks, exclusive access, device-mode changes, or configuration setters.
func number(_ device: IOHIDDevice, _ key: String) -> Int? {
    (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
}

func interfaceNumber(_ device: IOHIDDevice) -> Int? {
    let service = IOHIDDeviceGetService(device)
    guard service != 0 else { return nil }
    let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
    return (IORegistryEntrySearchCFProperty(service, kIOServicePlane, "bInterfaceNumber" as CFString,
                                          kCFAllocatorDefault, options) as? NSNumber)?.intValue
}

func read(_ operation: USBKnobRead, device: IOHIDDevice, transaction: UInt8) throws -> USBKnobReadResponse {
    let request = try operation.request(transaction: transaction)
    let sent = request.withUnsafeBytes { buffer in
        IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0,
                            buffer.bindMemory(to: UInt8.self).baseAddress!, request.count)
    }
    guard sent == kIOReturnSuccess else { throw InspectorError.io("Read-request transfer failed", sent) }
    let deadline = ProcessInfo.processInfo.systemUptime + 3
    repeat {
        Thread.sleep(forTimeInterval: 0.08)
        var bytes = [UInt8](repeating: 0, count: 90)
        var count = bytes.count
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0, &bytes, &count)
        guard result == kIOReturnSuccess else { throw InspectorError.io("Reply transfer failed", result) }
        let response = try operation.response(Data(bytes.prefix(count)), transaction: transaction)
        if response.status != 1 && response.status != 3 { return response }
    } while ProcessInfo.processInfo.systemUptime < deadline
    throw InspectorError.timeout
}

enum InspectorError: Error {
    case io(String, IOReturn), timeout
}

public enum USBInspector {
    public static func run(_ args: [String]) -> Int32 {
        guard args == ["--list"] || args == ["--read"] else {
            print("Usage: ErgoUSBInspector --list | --read")
            print("Reads only Pro Type Ergo USB interface 3, LED class 1 / ID 39.")
            return 2
        }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching = [kIOHIDVendorIDKey: 0x1532, kIOHIDProductIDKey: 0x02c4] as CFDictionary
        IOHIDManagerSetDeviceMatching(manager, matching)
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        let matches = devices.filter {
            number($0, kIOHIDVendorIDKey) == 0x1532 && number($0, kIOHIDProductIDKey) == 0x02c4 &&
            (IOHIDDeviceGetProperty($0, kIOHIDTransportKey as CFString) as? String) == "USB" &&
            interfaceNumber($0) == 3 && (number($0, kIOHIDMaxFeatureReportSizeKey) ?? 0) >= 90
        }
        print("PT Ergo USB configuration interfaces: \(matches.count)")
        guard args == ["--read"] else { return 0 }
        guard matches.count == 1, let device = matches.first else {
            print("Connect PT Ergo through a USB data cable and select its wired connection.")
            return 1
        }
        let recovery = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ErgoControl/Bluetooth/pending-restoration.json")
        guard !FileManager.default.fileExists(atPath: recovery.path) else {
            print("Turn mappings off and let Ergo Control finish restoring the keyboard before inspecting USB.")
            return 1
        }
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { print("USB interface could not be opened: \(result)"); return 1 }
        defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        do {
            for (index, operation) in USBKnobRead.allCases.enumerated() {
                let reply = try read(operation, device: device, transaction: UInt8(index + 1))
                print("\(operation): status \(reply.status)")
                guard reply.status == 2 else { continue }
                let bytes = Array(reply.payload)
                switch operation {
                case .currentMode:
                    print("disabled=\(bytes[2]) stage=\(bytes[3]) mode=\(bytes[4]) RGB=\(bytes[5]),\(bytes[6]),\(bytes[7])")
                case .configuration:
                    for start in stride(from: 2, to: 50, by: 6) {
                        print("stage=\(bytes[start+1]) disabled=\(bytes[start]) mode=\(bytes[start+2]) RGB=\(bytes[start+3]),\(bytes[start+4]),\(bytes[start+5])")
                    }
                case .indicatorState:
                    print("indicator on=\(bytes[2])")
                case .indicatorRGB:
                    print("indicator RGB=\(bytes[2]),\(bytes[3]),\(bytes[4])")
                }
            }
            return 0
        } catch {
            print("USB inspection stopped: \(error)")
            return 1
        }
    }

}
