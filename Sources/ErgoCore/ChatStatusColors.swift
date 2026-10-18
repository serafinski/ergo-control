import Foundation

/// Each provider owns a palette; activity still controls priority and motion
/// even when the user gives several activities the same RGB value.
public struct ChatStatusColors: Codable, Equatable {
    public var working: DialColor
    public var attention: DialColor
    public var finished: DialColor
    public init(working: DialColor, attention: DialColor, finished: DialColor) {
        self.working = working; self.attention = attention; self.finished = finished
    }
    public static func defaults(for provider: ChatProvider) -> Self {
        if provider == .codex {
            return Self(working: CodexActivity.working.color, attention: CodexActivity.attention.color,
                        finished: CodexActivity.finished.color)
        }
        return Self(working: DialColor(red: 255, green: 87, blue: 0),
                    attention: DialColor(red: 255, green: 1, blue: 235),
                    finished: DialColor(red: 0, green: 255, blue: 255))
    }
    public func color(for activity: CodexActivity) -> DialColor {
        switch activity {
        case .working: return working
        case .attention: return attention
        case .finished: return finished
        case .idle, .unknown: return activity.color
        }
    }
    public mutating func set(_ color: DialColor, for activity: CodexActivity) {
        switch activity {
        case .working: working = color
        case .attention: attention = color
        case .finished: finished = color
        case .idle, .unknown: break
        }
    }
}
