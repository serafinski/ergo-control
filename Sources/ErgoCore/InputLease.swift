import Foundation

/// Limits exclusive capture to a responsive client that has processed its input stream.
public struct InputLease {
    public static let duration: TimeInterval = 3
    public static let maximumPending: UInt64 = 256
    public private(set) var active = false
    public private(set) var sent: UInt64 = 0
    public private(set) var acknowledged: UInt64 = 0
    private var deadline: TimeInterval = 0

    public init() {}
    public mutating func begin(now: TimeInterval) {
        active = true; sent = 0; acknowledged = 0; deadline = now + Self.duration
    }
    public mutating func nextReport(now: TimeInterval) -> UInt64? {
        guard isValid(now: now), sent - acknowledged < Self.maximumPending, sent < UInt64.max else {
            end(); return nil
        }
        sent += 1; return sent
    }
    public mutating func renew(ack: UInt64, now: TimeInterval) -> Bool {
        guard isValid(now: now), ack >= acknowledged, ack <= sent else { end(); return false }
        // A stuck receiver cannot keep capture alive simply by sending heartbeats.
        if ack > acknowledged || ack == sent { deadline = now + Self.duration }
        acknowledged = ack
        return true
    }
    public func isValid(now: TimeInterval) -> Bool { active && now < deadline }
    public mutating func end() { active = false }
}
