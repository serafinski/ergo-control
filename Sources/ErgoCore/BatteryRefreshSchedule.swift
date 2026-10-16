import Foundation

/// Read-only battery polling shares the keyboard's serial configuration channel.
/// Mapping activation/restoration always takes priority over background reads.
public struct BatteryRefreshSchedule {
    public enum Action: Equatable { case connect, read }
    private var lastConnectionAttempt: TimeInterval?
    private var lastReadAttempt: TimeInterval?
    public init() {}

    public mutating func refresh() {
        lastConnectionAttempt = nil
        lastReadAttempt = nil
    }

    public mutating func next(at uptime: TimeInterval, ready: Bool, busy: Bool,
                              preparingMappings: Bool, restorationOwed: Bool, driverModeVerified: Bool) -> Action? {
        guard !busy, !preparingMappings else { return nil }
        if ready {
            guard !restorationOwed || driverModeVerified else { return nil }
            guard lastReadAttempt.map({ uptime - $0 >= 300 }) ?? true else { return nil }
            lastReadAttempt = uptime
            return .read
        }
        // A fresh app with a recovery journal must connect before the controller
        // can restore it. Suppress battery reads, not that required connection.
        guard !driverModeVerified, lastConnectionAttempt.map({ uptime - $0 >= 60 }) ?? true else { return nil }
        lastConnectionAttempt = uptime
        lastReadAttempt = nil // Refresh immediately after reconnecting, once the channel is idle.
        return .connect
    }
}
