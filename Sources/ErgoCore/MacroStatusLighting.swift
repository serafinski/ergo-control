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

public enum CodexLightingArea: String, Codable, CaseIterable, Identifiable {
    case macroColumn, wholeKeyboard
    public var id: String { rawValue }
    public var label: String { self == .macroColumn ? "Macro column" : "Whole keyboard" }
}

public enum MacroStatusFrame {
    public static let background = DialColor(red: 16, green: 16, blue: 16)
    public static func colors(_ signal: DialColor, area: CodexLightingArea = .macroColumn) -> [DialColor] {
        if area == .wholeKeyboard { return Array(repeating: signal, count: 19) }
        var frame = Array(repeating: background, count: 19)
        frame[0] = signal
        return frame
    }
}
