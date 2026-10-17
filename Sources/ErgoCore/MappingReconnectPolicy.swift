/// Resume only a previously verified, untimed session after connection loss.
/// Activation/capture failures remain one-shot and never arm a retry loop.
public struct MappingReconnectPolicy {
    private var established = false
    public init() {}
    public mutating func activated(timed: Bool) { established = !timed }
    public mutating func cancel() { established = false }
    public enum Decision: Equatable { case ignore, stop, resume }
    public mutating func connectionLost(running: Bool, preparing: Bool, automatic: Bool,
                                        terminating: Bool) -> Decision {
        // Duplicate HID/BLE callbacks must not cancel an already pending resume.
        guard running || preparing else { return .ignore }
        let resume = established && running && automatic && !terminating
        cancel()
        return resume ? .resume : .stop
    }
}
