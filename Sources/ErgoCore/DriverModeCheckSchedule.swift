import Foundation

/// Readback cadence is independent of the local safety lease renewal.
public struct DriverModeCheckSchedule {
    private var verifiedAt: TimeInterval?
    public init() {}
    public mutating func verified(at uptime: TimeInterval) { verifiedAt = uptime }
    public func isDue(at uptime: TimeInterval) -> Bool {
        verifiedAt.map { uptime - $0 >= 30 } ?? true
    }
}
