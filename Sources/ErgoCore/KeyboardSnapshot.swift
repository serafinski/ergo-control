import Foundation

public struct KeyboardSnapshot: Equatable {
    public let modifiers: UInt8
    public let held: Set<UInt8>
    public init?(_ data: Data) {
        let bytes = Array(data)
        guard bytes.count == 12, bytes[0] == 1 else { return nil }
        let keys = bytes.dropFirst(2)
        // HID rollover/error usages do not describe an empty keyboard.
        guard !keys.contains(where: { (1...3).contains($0) }) else { return nil }
        modifiers = bytes[1]
        var held = Set(keys.filter { $0 != 0 })
        for bit in 0..<8 where modifiers & (1 << bit) != 0 { held.insert(UInt8(224 + bit)) }
        self.held = held
    }
}
