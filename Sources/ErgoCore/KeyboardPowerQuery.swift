import Foundation

/// Fixed read-only power queries recovered from this model's Bluetooth middleware.
/// Payload units/capabilities must be confirmed before adding setters.
public enum KeyboardPowerQuery: UInt8, CaseIterable {
    case sleepTimer = 0x84, charging = 0x85, automaticSleep = 0x87, idleDimming = 0x8a
    public var name: String {
        switch self {
        case .sleepTimer: return "Sleep timer"
        case .charging: return "Charging status"
        case .automaticSleep: return "Automatic sleep enabled"
        case .idleDimming: return "Idle dimming"
        }
    }
    public func request(transaction: UInt8) throws -> Protocol30Request {
        try Protocol30Request(transaction: transaction, commandClass: 5, commandID: rawValue, argument7: 1)
    }
}
