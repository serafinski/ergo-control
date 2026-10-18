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

public enum CodexWaveSpeed: String, Codable, CaseIterable, Identifiable {
    case smooth, quick
    public var id: String { rawValue }
    public var label: String { self == .quick ? "Quick" : "Smooth" }
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
/// working settles on its signal color; completion restores the normal effect.
public enum CodexStatusWave {
    /// Working falls back to solid color; completion waits for its finite acknowledged pass.
    public static let maximumDuration: TimeInterval = 6
    public static let minimumFrameInterval: TimeInterval = 0
    public static let completionWindow: TimeInterval = 8
    public static func positions(for activity: CodexActivity, speed: CodexWaveSpeed = .smooth) -> [Int] {
        if speed == .quick {
            switch activity {
            case .working: return [0, 9, 18]
            case .attention, .finished: return [0, 9, 18, 9, 0]
            default: return []
            }
        }
        switch activity {
        case .working: return [0, 6, 12, 18]
        case .attention, .finished: return [0, 6, 12, 18, 12, 6, 0]
        default: return []
        }
    }
    public static func frame(_ index: Int, activity: CodexActivity, speed: CodexWaveSpeed = .smooth, darkBackground: Bool = false, color: DialColor? = nil) -> [DialColor] {
        var colors = Array(repeating: darkBackground ? DialColor(red: 0, green: 0, blue: 0) : MacroStatusFrame.background, count: 19)
        let positions = positions(for: activity, speed: speed)
        guard positions.indices.contains(index) else { return colors }
        let head = positions[index]
        let direction = index > 0 && head < positions[index - 1] ? -1 : 1
        let color = color ?? activity.color
        let width = speed == .quick ? 10 : 7
        for trail in 0..<width {
            let column = head - direction * trail
            guard (0..<19).contains(column) else { continue }
            colors[column] = DialColor(red: UInt8(Int(color.red) * (width - trail) / width),
                                      green: UInt8(Int(color.green) * (width - trail) / width),
                                      blue: UInt8(Int(color.blue) * (width - trail) / width))
        }
        return colors
    }
}
