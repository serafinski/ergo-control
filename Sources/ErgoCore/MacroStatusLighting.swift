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

/// `completionWave` keeps its saved value; its UI now covers waves for all active states.
public enum CodexLightingArea: String, Codable, CaseIterable, Identifiable {
    case macroColumn, wholeKeyboard, completionWave
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .macroColumn: return "Macro column"
        case .wholeKeyboard: return "Whole keyboard · solid"
        case .completionWave: return "Status waves"
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

/// Fixed passes over the recovered 19-zone row. Approval repeats by request;
/// working and completion restore the normal effect after a single pass.
public enum CodexStatusWave {
    public static let maximumDuration: TimeInterval = 6
    public static let minimumFrameInterval: TimeInterval = 0
    public static let completionWindow: TimeInterval = 8
    public static func positions(for activity: CodexActivity) -> [Int] {
        switch activity {
        case .working: return [0, 6, 12, 18]
        case .attention, .finished: return [0, 6, 12, 18, 12, 6, 0]
        default: return []
        }
    }
    public static func frame(_ index: Int, activity: CodexActivity) -> [DialColor] {
        var colors = Array(repeating: MacroStatusFrame.background, count: 19)
        let positions = positions(for: activity)
        guard positions.indices.contains(index) else { return colors }
        let head = positions[index]
        let direction = index > 0 && head < positions[index - 1] ? -1 : 1
        let color = activity.color
        for trail in 0..<7 {
            let column = head - direction * trail
            guard (0..<19).contains(column) else { continue }
            colors[column] = DialColor(red: UInt8(Int(color.red) * (7 - trail) / 7),
                                      green: UInt8(Int(color.green) * (7 - trail) / 7),
                                      blue: UInt8(Int(color.blue) * (7 - trail) / 7))
        }
        return colors
    }
}
