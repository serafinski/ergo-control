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
        case 82: return "Right roller click"
        case 83: return "Media double press"
        case 84: return "Media triple press"
        case 85: return "Media single press"
        case 251: return "Split Backspace · extra key"
        case 252: return "Split B · extra key"
        case 253: return "Right space"
        default: return "Extra key \(key)"
        }
    }
}

/// PT Ergo physical report 5 contains logical record 4, followed by a key set.
/// Confirmed against separate driver-mode captures for M1–M5, AI, left click, and battery.
/// A valid all-zero key set releases held keys; unrelated/malformed reports do not.
public struct ExtraKeyDecoder {
    private var held: Set<UInt8> = []
    private var mediaDeadlines: [UInt8: TimeInterval] = [:]
    public var mediaReleaseDeadline: TimeInterval? { mediaDeadlines.values.min() }
    public init() {}

    public mutating func decode(reportID: UInt32, bytes: Data, at now: TimeInterval? = nil) -> [ExtraKeyEvent]? {
        let values = Array(bytes)
        guard reportID == 5, values.count == 12, values[0] == 5, values[1] == 4 else { return nil }
        let expired = now.map { releaseMediaExpired(at: $0) } ?? []
        let current = Set(values.dropFirst(2).filter { $0 != 0 })
        let releases = held.subtracting(current).sorted().map { ExtraKeyEvent(key: $0, pressed: false) }
        let presses = current.subtracting(held).sorted().map { ExtraKeyEvent(key: $0, pressed: true) }
        held = current
        for event in releases { mediaDeadlines.removeValue(forKey: event.key) }
        if let now {
            for event in presses where (83...85).contains(event.key) {
                mediaDeadlines[event.key] = now + ConsumerKeyState.pulseReleaseTimeout
            }
        }
        return expired + releases + presses
    }
    public mutating func releaseMediaExpired(at now: TimeInterval) -> [ExtraKeyEvent] {
        let keys = mediaDeadlines.filter { now >= $0.value }.map(\.key).sorted()
        for key in keys { held.remove(key); mediaDeadlines.removeValue(forKey: key) }
        return keys.map { ExtraKeyEvent(key: $0, pressed: false) }
    }

}
