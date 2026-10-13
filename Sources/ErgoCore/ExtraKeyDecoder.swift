import Foundation

public struct ExtraKeyEvent: Equatable {
    public let key: UInt8
    public let pressed: Bool

    public var name: String {
        switch key {
        case 32...36: return "M\(key - 31)"
        case 247: return "AI button"
        case 96: return "Left dial click"
        case 65: return "Battery button"
        default: return "Extra key \(key)"
        }
    }
}

/// PT Ergo physical report 5 contains logical record 4, followed by a key set.
/// Confirmed against separate driver-mode captures for M1–M5, AI, left click, and battery.
/// A valid all-zero key set releases held keys; unrelated/malformed reports do not.
public struct ExtraKeyDecoder {
    private var held: Set<UInt8> = []
    public init() {}

    public mutating func decode(reportID: UInt32, bytes: Data) -> [ExtraKeyEvent]? {
        let values = Array(bytes)
        guard reportID == 5, values.count == 12, values[0] == 5, values[1] == 4 else { return nil }
        let current = Set(values.dropFirst(2).filter { $0 != 0 })
        let releases = held.subtracting(current).sorted().map { ExtraKeyEvent(key: $0, pressed: false) }
        let presses = current.subtracting(held).sorted().map { ExtraKeyEvent(key: $0, pressed: true) }
        held = current
        return releases + presses
    }
}
