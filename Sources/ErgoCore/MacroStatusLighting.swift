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
    case macroColumn, wholeKeyboard, completionWave
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .macroColumn: return "Macro column"
        case .wholeKeyboard: return "Whole keyboard · solid"
        case .completionWave: return "Completion wave"
        }
    }
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

/// One bounded pass over the recovered 19-zone row, with acknowledged frames.
public enum CodexCompletionWave {
    public static let positions = [0, 4, 8, 12, 16, 18]
    public static let maximumDuration: TimeInterval = 6
    public static let minimumFrameInterval: TimeInterval = 0.25
    public static let completionWindow: TimeInterval = 8
    public static func frame(_ index: Int) -> [DialColor] {
        var colors = Array(repeating: MacroStatusFrame.background, count: 19)
        guard positions.indices.contains(index) else { return colors }
        let head = positions[index]
        for trail in 0..<5 where head - trail >= 0 {
            colors[head - trail] = DialColor(red: 0, green: UInt8(255 * (5 - trail) / 5), blue: 0)
        }
        return colors
    }
}
