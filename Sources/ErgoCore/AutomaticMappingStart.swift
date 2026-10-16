/// A launch/wake request waits for permissions, connection and restoration. It
/// permits one activation attempt, so a failing helper never causes a retry loop.
/// Readiness has no deadline: Bluetooth may arrive well after login. Only manual
/// cancellation or consuming the activation attempt ends the pending request.
public struct AutomaticMappingStart {
    private var pending = false
    public init() {}
    public mutating func arm() { pending = true }
    public mutating func cancel() { pending = false }
    public enum Decision: Equatable { case wait, start }
    public mutating func next(ready: Bool, permissions: Bool,
                              busy: Bool, restorationPending: Bool) -> Decision {
        guard pending, ready, permissions, !busy, !restorationPending else { return .wait }
        cancel()
        return .start
    }
}
