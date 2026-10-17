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

/// Defaults from the exact Pro Type Ergo product input table.
public enum DriverMediaControls {
    public static func usage(forExtraKey key: UInt8) -> UInt16? {
        switch key { case 82: return 0xe2; case 83: return 0xb5; case 84: return 0xb6; case 85: return 0xcd; default: return nil }
    }
    public static func wheelEvents(_ steps: Int) -> [ConsumerKeyEvent] {
        guard steps != 0 else { return [] }
        let usage: UInt16 = steps > 0 ? 0xe9 : 0xea
        return (0..<min(32, abs(steps))).flatMap { _ in [ConsumerKeyEvent(usage, pressed: true), ConsumerKeyEvent(usage, pressed: false)] }
    }
}

public enum MediaInputSource: Hashable { case nativeConsumer, driverRecord, extraKey, wheel }

/// Correlate each duplicated gesture only once across sources. Same-source
/// wheel detents and separate key presses are never treated as duplicates.
public struct MediaInputState {
    public static let crossSourceWindow: TimeInterval = 0.08
    private struct Key: Hashable { let source: MediaInputSource; let usage: UInt16 }
    private struct Gesture { let time: TimeInterval; var sources: Set<MediaInputSource> }
    private var native = ConsumerKeyState()
    private var recent: [UInt16: Gesture] = [:]
    private var suppressedReleases: Set<Key> = []
    public var releaseDeadline: TimeInterval? { native.releaseDeadline }
    public init() {}
    public mutating func decode(_ report: Data, at now: TimeInterval) -> [ConsumerKeyEvent]? {
        if let record = DriverMediaRecord(report) {
            let expired = releaseExpired(at: now)
            guard record.usage != 0 else { return expired }
            return expired + accept([.init(record.usage, pressed: true), .init(record.usage, pressed: false)], source: .driverRecord, at: now)
        }
        guard let events = native.decode(report, at: now) else { return nil }
        return accept(events, source: .nativeConsumer, at: now)
    }
    public mutating func releaseExpired(at now: TimeInterval) -> [ConsumerKeyEvent] {
        accept(native.releaseExpired(at: now), source: .nativeConsumer, at: now)
    }
    public mutating func accept(_ events: [ConsumerKeyEvent], source: MediaInputSource, at now: TimeInterval) -> [ConsumerKeyEvent] {
        recent = recent.filter { now - $0.value.time <= Self.crossSourceWindow }
        var output: [ConsumerKeyEvent] = []
        for event in events {
            let key = Key(source: source, usage: event.usage)
            if event.pressed {
                if var gesture = recent[event.usage], !gesture.sources.contains(source) {
                    gesture.sources.insert(source); recent[event.usage] = gesture
                    suppressedReleases.insert(key); continue
                }
                recent[event.usage] = Gesture(time: now, sources: [source])
            } else if suppressedReleases.remove(key) != nil { continue }
            output.append(event)
        }
        return output
    }
}
