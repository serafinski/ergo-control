import Foundation

public struct DialColor: Codable, Equatable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red; self.green = green; self.blue = blue
    }
    public static func defaultColor(for name: String) -> Self {
        switch name.lowercased() {
        case "keyboard brightness": return Self(red: 0, green: 255, blue: 0)
        case "zoom": return Self(red: 255, green: 0, blue: 0)
        case "switch applications": return Self(red: 0, green: 0, blue: 255)
        case "scroll", "vertical scrolling": return Self(red: 255, green: 0, blue: 255)
        case "browser tabs": return Self(red: 255, green: 128, blue: 0)
        default: return Self(red: 255, green: 255, blue: 255)
        }
    }
    public var bytes: Data { Data([red, green, blue]) }
}

/// Keep the order of turns at the limits: up then down at 100% ends at 95%.
/// Turns arriving during a Bluetooth exchange belong to the next batch.
public struct BrightnessSteps {
    private var steps: [Int] = []
    public init() {}
    public var isEmpty: Bool { steps.isEmpty }
    @discardableResult public mutating func append(_ direction: Int) -> Bool {
        guard direction == 1 || direction == -1, steps.count < 256 else { return false }
        steps.append(direction); return true
    }
    public mutating func takeTarget(from raw: UInt8) -> UInt8 {
        var percent = Int(ceil(Double(raw) / 255 * 100))
        for direction in steps { percent = min(100, max(0, percent + direction * 5)) }
        steps.removeAll()
        return UInt8(percent * 255 / 100)
    }
    public mutating func clear() { steps.removeAll() }
}

/// The physical mode light needs the backlight enabled. Waiting for a user
/// brightness change must not repeatedly probe RGB or force the backlight on.
public struct DialBacklightGate {
    private var waiting = false
    public init() {}
    public mutating func mayFlash(rawBrightness: UInt8) -> Bool {
        waiting = rawBrightness == 0
        return !waiting
    }
    public mutating func retryAfterBrightnessChange(rawBrightness: UInt8) -> Bool {
        guard waiting, rawBrightness > 0 else { return false }
        waiting = false; return true
    }
    public mutating func cancel() { waiting = false }
}

public extension Protocol30Request {
    static func readLightingRegions(transaction: UInt8) throws -> Self {
        try Self(transaction: transaction, commandClass: 16, commandID: 0x80, argument7: 1)
    }
    static func readKeyboardBrightness(transaction: UInt8, region: UInt8) throws -> Self {
        try Self(transaction: transaction, commandClass: 16, commandID: 0x85, argument6: 1, argument7: region)
    }
    static func keyboardBrightness(transaction: UInt8, raw: UInt8) throws -> Self {
        // Synapse's live brightness task uses profile 1, AllRegion (0).
        try Self(transaction: transaction, commandClass: 16, commandID: 5, argument6: 1, payload: Data([raw]))
    }
    static func readDialColor(transaction: UInt8, ledClass: UInt8 = 1, ledID: UInt8 = 39) throws -> Self {
        try Self(transaction: transaction, commandClass: 6, commandID: 0x84, argument6: ledClass, argument7: ledID)
    }
    static func readLEDList(transaction: UInt8) throws -> Self {
        try Self(transaction: transaction, commandClass: 6, commandID: 0x80)
    }
    static func readLEDType(transaction: UInt8, ledID: UInt8) throws -> Self {
        try Self(transaction: transaction, commandClass: 6, commandID: 0x81, argument7: ledID)
    }
    static func dialColor(transaction: UInt8, color: DialColor, brightness: UInt8 = 255) throws -> Self {
        // Correct the vendor's three-byte allocation: this command's template
        // and getter specify RGB plus a fourth brightness byte. Product LED = 39.
        try Self(transaction: transaction, commandClass: 6, commandID: 4, argument6: 1, argument7: 39,
                 payload: color.bytes + Data([brightness]))
    }
    static func readDialLightState(transaction: UInt8) throws -> Self {
        try Self(transaction: transaction, commandClass: 6, commandID: 0x82, argument6: 1, argument7: 39)
    }
    static func dialLightState(transaction: UInt8, on: Bool) throws -> Self {
        try Self(transaction: transaction, commandClass: 6, commandID: 2, argument6: 1, argument7: 39, payload: Data([on ? 1 : 0]))
    }
}
