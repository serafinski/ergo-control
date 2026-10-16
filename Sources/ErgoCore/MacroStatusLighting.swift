import Foundation

/// Stored inside the existing mapping recovery record, before selecting custom
/// lighting. A selector for an unknown/custom effect cannot restore its pixels.
public struct SavedMacroLighting: Codable, Equatable {
    public let region: UInt8
    public let effect: Data
    public init(region: UInt8, effect: KeyboardEffect) throws {
        guard region == 5 else { throw LightingLabError.unsupportedOriginal }
        _ = try Protocol30Request.keyboardEffect(transaction: 1, effect: effect)
        self.region = region; self.effect = effect.payload
    }
    public func validatedEffect() throws -> KeyboardEffect {
        let value = try KeyboardEffect(payload: effect)
        _ = try Self(region: region, effect: value)
        return value
    }
}

public enum MacroStatusFrame {
    public static func colors(_ macro: DialColor) -> [DialColor] {
        var frame = Array(repeating: DialColor(red: 160, green: 160, blue: 160), count: 19)
        frame[0] = macro
        return frame
    }
}
