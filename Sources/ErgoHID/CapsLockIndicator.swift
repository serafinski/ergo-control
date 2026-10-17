import Foundation
import IOKit.hid

/// Only the standard Caps Lock LED on an already-open device. No raw reports,
/// vendor commands, device discovery, or changes to Num/Scroll Lock.
public enum CapsLockIndicator {
    public static func set(_ enabled: Bool, on device: IOHIDDevice) -> IOReturn {
        let matching = [kIOHIDElementUsagePageKey: 8, kIOHIDElementUsageKey: 2] as CFDictionary
        let elements = IOHIDDeviceCopyMatchingElements(device, matching, 0) as? [IOHIDElement] ?? []
        guard let element = elements.first(where: {
            IOHIDElementGetType($0) == kIOHIDElementTypeOutput &&
            IOHIDElementGetUsagePage($0) == 8 && IOHIDElementGetUsage($0) == 2
        }) else { return kIOReturnUnsupported }
        let value = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, element, 0, enabled ? 1 : 0)
        return IOHIDDeviceSetValue(device, element, value)
    }
}
