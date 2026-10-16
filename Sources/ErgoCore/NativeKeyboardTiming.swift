import Foundation

/// Values are seconds from AppKit, not optional defaults-domain tick counts.
public struct NativeKeyboardTiming: Equatable {
    public let delay: TimeInterval
    public let interval: TimeInterval
    public init(delay: TimeInterval, interval: TimeInterval) {
        self.delay = delay.isFinite && delay > 0 ? delay : 0.5
        self.interval = interval.isFinite && interval > 0 ? interval : 1.0 / 12
    }
}

public struct NativeKeyboardTransition: Equatable {
    public let usage: UInt8
    public let pressed: Bool
    public let modifiers: UInt8
}

public enum NativeKeyboardTransitions {
    /// Release ordinary keys before releasing their modifiers; press modifiers
    /// before new ordinary keys. Maintain modifier state at each transition.
    public static func changes(from previous: Set<UInt8>, to current: Set<UInt8>) -> [NativeKeyboardTransition] {
        var modifiers: UInt8 = 0
        for usage in previous where (224...231).contains(usage) { modifiers |= 1 << (usage - 224) }
        let released = previous.subtracting(current).sorted()
        let pressed = current.subtracting(previous).sorted()
        var result: [NativeKeyboardTransition] = []
        for usage in released where usage < 224 {
            result.append(NativeKeyboardTransition(usage: usage, pressed: false, modifiers: modifiers))
        }
        for usage in released where (224...231).contains(usage) {
            modifiers &= ~(1 << (usage - 224))
            result.append(NativeKeyboardTransition(usage: usage, pressed: false, modifiers: modifiers))
        }
        for usage in pressed where (224...231).contains(usage) {
            modifiers |= 1 << (usage - 224)
            result.append(NativeKeyboardTransition(usage: usage, pressed: true, modifiers: modifiers))
        }
        for usage in pressed where usage < 224 {
            result.append(NativeKeyboardTransition(usage: usage, pressed: true, modifiers: modifiers))
        }
        return result
    }
}
