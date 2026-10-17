import Foundation

public struct KeyboardDimming: Equatable, Codable {
    public var enabled: Bool
    public var seconds: UInt16
    public var percentage: UInt8
    public init(enabled: Bool, seconds: UInt16, percentage: UInt8 = 20) {
        self.enabled = enabled; self.seconds = seconds; self.percentage = percentage
    }
    public init(payload: Data) throws {
        let bytes = Array(payload)
        guard bytes.count == 4, bytes[0] <= 1, bytes[3] <= 100 else { throw LightingLabError.invalidPacket }
        self.init(enabled: bytes[0] == 1, seconds: UInt16(bytes[1]) | UInt16(bytes[2]) << 8, percentage: bytes[3])
    }
}
public struct KeyboardSleep: Equatable, Codable {
    public var enabled: Bool
    public var seconds: UInt16
    public init(enabled: Bool, seconds: UInt16) { self.enabled = enabled; self.seconds = seconds }
}
public struct KeyboardPowerSettings: Equatable, Codable {
    public var brightness: UInt8
    public var dimming: KeyboardDimming
    public var sleep: KeyboardSleep
    public init(brightness: UInt8, dimming: KeyboardDimming, sleep: KeyboardSleep) {
        self.brightness = brightness; self.dimming = dimming; self.sleep = sleep
    }
    public var brightnessPercent: Int { Int(ceil(Double(brightness) * 100 / 255)) }
}
public struct KeyboardPowerChanges {
    public var brightness: UInt8?
    public var dimming: KeyboardDimming?
    public var sleep: KeyboardSleep?
    public init(brightness: UInt8? = nil, dimming: KeyboardDimming? = nil, sleep: KeyboardSleep? = nil) {
        self.brightness = brightness; self.dimming = dimming; self.sleep = sleep
    }
}
public struct SavedKeyboardBrightness: Codable, Equatable {
    public let peripheral: UUID
    public var brightness: UInt8
    public init(peripheral: UUID, brightness: UInt8) { self.peripheral = peripheral; self.brightness = brightness }
}
public struct LightingOffPreferences: Equatable, Codable {
    public var whenDisplaySleeps = false
    public var whenIdle = false
    public var idleMinutes = 1
    public init() {}
    public func shouldTurnOff(displayAsleep: Bool, idleSeconds: TimeInterval) -> Bool {
        (whenDisplaySleeps && displayAsleep) || (whenIdle && idleSeconds.isFinite && idleSeconds >= Double(min(15, max(1, idleMinutes))) * 60)
    }
}
public extension Protocol30Request {
    static func keyboardDimming(transaction: UInt8, value: KeyboardDimming) throws -> Self {
        guard (60...900).contains(value.seconds), value.percentage <= 100 else { throw LightingLabError.invalidPattern }
        return try Self(transaction: transaction, commandClass: 5, commandID: 0x0a, argument7: 1,
                        payload: Data([value.enabled ? 1 : 0, UInt8(value.seconds & 255), UInt8(value.seconds >> 8), value.percentage]))
    }
    static func keyboardSleepTimer(transaction: UInt8, seconds: UInt16) throws -> Self {
        guard (60...3600).contains(seconds) else { throw LightingLabError.invalidPattern }
        return try Self(transaction: transaction, commandClass: 5, commandID: 4,
                        payload: Data([UInt8(seconds & 255), UInt8(seconds >> 8)]))
    }
    static func keyboardAutoSleep(transaction: UInt8, enabled: Bool) throws -> Self {
        try Self(transaction: transaction, commandClass: 5, commandID: 7, argument7: 1, payload: Data([enabled ? 1 : 0]))
    }
}
