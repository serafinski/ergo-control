import Foundation

/// A launch/wake request waits for permissions, connection and restoration. It
/// permits one activation attempt, so a failing helper never causes a retry loop.
public struct AutomaticMappingStart {
    private var deadline: TimeInterval?
    public init() {}
    public mutating func arm(at time: TimeInterval) { deadline = time + 120 }
    public mutating func cancel() { deadline = nil }
    public enum Decision: Equatable { case wait, start, expired }
    public mutating func next(at time: TimeInterval, ready: Bool, permissions: Bool,
                              busy: Bool, restorationPending: Bool) -> Decision {
        guard let deadline else { return .wait }
        guard time < deadline else { cancel(); return .expired }
        guard ready, permissions, !busy, !restorationPending else { return .wait }
        cancel()
        return .start
    }
}
