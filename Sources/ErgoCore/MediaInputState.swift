import Foundation

/// Physical vendor report 6 can carry logical record 2 (media), as well as
/// logical record 5 (notifications). A media record is a momentary command,
/// with a little-endian consumer usage, not an ordinary keyboard snapshot.
public struct DriverMediaRecord: Equatable {
    public let usage: UInt16
    public init?(_ data: Data) {
        let bytes = Array(data)
        guard bytes.count == 12, bytes[0] == 6, bytes[1] == 2,
              bytes.dropFirst(4).allSatisfy({ $0 == 0 }) else { return nil }
        usage = UInt16(bytes[2]) | UInt16(bytes[3]) << 8
    }
}

/// Native report-3 key lifetimes and vendor momentary media records share one
/// output path. Correlate only across sources: repeated vendor volume steps are
/// distinct actions, while a native+vendor copy must not toggle playback twice.
public struct MediaInputState {
    public static let crossSourceWindow: TimeInterval = 0.08
    private var native = ConsumerKeyState()
    private var nativePresses: [UInt16: TimeInterval] = [:]
    private var driverPulses: [UInt16: TimeInterval] = [:]
    private var suppressedNative: Set<UInt16> = []
    public var releaseDeadline: TimeInterval? { native.releaseDeadline }
    public init() {}

    public mutating func decode(_ report: Data, at now: TimeInterval) -> [ConsumerKeyEvent]? {
        if let record = DriverMediaRecord(report) {
            var events = releaseExpired(at: now)
            guard record.usage != 0 else { return events }
            // Keep histories bounded even for malformed/unsupported usages.
            prune(at: now)
            driverPulses[record.usage] = now
            if let previous = nativePresses[record.usage], now - previous <= Self.crossSourceWindow { return events }
            events.append(ConsumerKeyEvent(record.usage, pressed: true))
            events.append(ConsumerKeyEvent(record.usage, pressed: false))
            return events
        }
        guard let events = native.decode(report, at: now) else { return nil }
        prune(at: now)
        return filterNative(events, at: now)
    }
    public mutating func releaseExpired(at now: TimeInterval) -> [ConsumerKeyEvent] {
        filterNative(native.releaseExpired(at: now), at: now)
    }
    private mutating func filterNative(_ events: [ConsumerKeyEvent], at now: TimeInterval) -> [ConsumerKeyEvent] {
        var output: [ConsumerKeyEvent] = []
        for event in events {
            if event.pressed {
                nativePresses[event.usage] = now
                if let previous = driverPulses[event.usage], now - previous <= Self.crossSourceWindow {
                    suppressedNative.insert(event.usage); continue
                }
            } else if suppressedNative.remove(event.usage) != nil { continue }
            output.append(event)
        }
        return output
    }
    private mutating func prune(at now: TimeInterval) {
        nativePresses = nativePresses.filter { now - $0.value <= Self.crossSourceWindow }
        driverPulses = driverPulses.filter { now - $0.value <= Self.crossSourceWindow }
    }
}
