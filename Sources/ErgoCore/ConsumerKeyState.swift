import Foundation

public struct ConsumerKeyEvent: Equatable {
    public let usage: UInt16
    public let pressed: Bool
    public init(_ usage: UInt16, pressed: Bool) { self.usage = usage; self.pressed = pressed }
}

/// PT Ergo's single/double/triple media gestures produce short consumer pulses.
/// A lost neutral report must not leave one held until a volume/mute event.
/// Volume, brightness, and genuine held seek keys retain their normal lifetime.
public struct ConsumerKeyState {
    public static let pulseReleaseTimeout: TimeInterval = 0.3
    public private(set) var releaseDeadline: TimeInterval?
    private var held: UInt16 = 0
    public init() {}

    public mutating func decode(_ report: Data, at now: TimeInterval) -> [ConsumerKeyEvent]? {
        let bytes = Array(report)
        guard bytes.count == 12, bytes[0] == 3, bytes.dropFirst(3).allSatisfy({ $0 == 0 }) else { return nil }
        let usage = UInt16(bytes[1]) | UInt16(bytes[2]) << 8
        var events = releaseExpired(at: now)
        guard usage != held else { return events }
        if held != 0 { events.append(ConsumerKeyEvent(held, pressed: false)) }
        held = usage
        releaseDeadline = [0xcd, 0xb5, 0xb6].contains(usage) ? now + Self.pulseReleaseTimeout : nil
        if usage != 0 { events.append(ConsumerKeyEvent(usage, pressed: true)) }
        return events
    }

    public mutating func releaseExpired(at now: TimeInterval) -> [ConsumerKeyEvent] {
        guard let deadline = releaseDeadline, now >= deadline else { return [] }
        releaseDeadline = nil
        let previous = held; held = 0
        return previous == 0 ? [] : [ConsumerKeyEvent(previous, pressed: false)]
    }
}
