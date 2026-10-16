/// Firmware defaults for the separate split-key records in physical report 5.
/// Recovered from the PT Ergo product's default mapping table; these are HID usages.
public enum NativeExtraKeys {
    public static func usage(for key: UInt8) -> UInt8? {
        switch key {
        case 251: return 42 // Backspace
        case 252: return 5  // B
        case 253: return 44 // Space
        default: return nil
        }
    }
}

/// PT Ergo's printed F1/F2 actions while relaying the keyboard in driver mode.
/// Explicit shortcut/macro output bypasses this native-input default.
public enum NativeFunctionKeys {
    public static func consumerUsage(for usage: UInt8) -> UInt16? {
        switch usage {
        case 58: return 0x70 // Display brightness down
        case 59: return 0x6f // Display brightness up
        default: return nil
        }
    }
}

/// Two physical halves can hold the same native key. Only the first press and
/// last release should reach macOS, including when the reports arrive separately.
public struct NativeKeyOwners {
    private var owners: [String: UInt8] = [:]
    public init() {}

    public mutating func change(_ usage: UInt8, owner: String, pressed: Bool) -> Bool {
        if pressed {
            guard owners[owner] == nil else { return false }
            let alreadyHeld = owners.values.contains(usage)
            owners[owner] = usage
            return !alreadyHeld
        }
        guard owners[owner] == usage else { return false }
        owners.removeValue(forKey: owner)
        return !owners.values.contains(usage)
    }
}

public struct KeyboardOutput: Equatable {
    public let usage: UInt8
    public let pressed: Bool
    public let modifiers: UInt8
    public init(_ usage: UInt8, pressed: Bool, modifiers: UInt8) {
        self.usage = usage; self.pressed = pressed; self.modifiers = modifiers
    }
}

/// A dial's Command+Tab shortcut keeps Command down across turns so the native
/// application switcher remains visible. Button/macro shortcuts do not use this.
public struct DialAppSwitcher {
    public private(set) var isActive = false
    public init() {}

    public mutating func step(_ chord: KeyChord, physicalModifiers: UInt8) -> [KeyboardOutput]? {
        guard chord.usage == 43, chord.modifiers == 8 || chord.modifiers == 10 else { return nil }
        var events: [KeyboardOutput] = []
        if !isActive {
            events.append(KeyboardOutput(227, pressed: true, modifiers: physicalModifiers | 8))
        }
        isActive = true
        events.append(KeyboardOutput(43, pressed: true, modifiers: physicalModifiers | chord.modifiers))
        events.append(KeyboardOutput(43, pressed: false, modifiers: physicalModifiers | 8))
        return events
    }

    public mutating func finish(physicalModifiers: UInt8) -> [KeyboardOutput] {
        guard isActive else { return [] }
        isActive = false
        // A real held Command key remains owned by its physical input source.
        guard physicalModifiers & 0x88 == 0 else { return [] }
        return [KeyboardOutput(227, pressed: false, modifiers: physicalModifiers)]
    }
}
