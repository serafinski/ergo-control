import Foundation

public enum ChatLightingMode: String, Codable, CaseIterable, Identifiable {
    case automatic, codex, claude
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .automatic: return "Automatic · Both apps"
        case .codex: return "Codex only"
        case .claude: return "Claude Code only"
        }
    }
    public func includes(_ provider: ChatProvider) -> Bool {
        self == .automatic || rawValue == provider.rawValue
    }
}

/// A selected chat's transient signal. Ranking working turns by their start
/// time prevents later tool hooks (or approval resumption) from stealing focus.
public struct ChatLightingCandidate: Equatable, Identifiable {
    public let id: String
    public let provider: ChatProvider
    public let activity: CodexActivity
    public let priorityTime: Date
    public init?(provider: ChatProvider, session: CodexSessionStatus, now: Date,
                 completionDuration: TimeInterval = CodexSessionStatus.completionSignalDuration) {
        let activity = session.activity(now: now, completionDuration: completionDuration)
        guard [.working, .attention, .finished].contains(activity) else { return nil }
        self.provider = provider; self.activity = activity
        priorityTime = activity == .working ? session.turnStarted : session.latest.time
        let phase: String
        switch activity {
        case .working: phase = String(session.workingSince.timeIntervalSinceReferenceDate)
        case .finished: phase = session.latest.turnID ?? String(session.turnStarted.timeIntervalSinceReferenceDate)
        default: phase = String(session.latest.time.timeIntervalSinceReferenceDate)
        }
        id = "\(provider.rawValue):\(activity.rawValue):\(session.latest.sessionID):\(phase)"
    }
}

public struct ChatLightingArbiter {
    private var suppressedCompletions: Set<String> = []
    public init() {}
    public mutating func select(_ candidates: [ChatLightingCandidate], mode: ChatLightingMode) -> ChatLightingCandidate? {
        let eligible = candidates.filter { mode.includes($0.provider) }
        let completions = Set(eligible.filter { $0.activity == .finished }.map(\.id))
        suppressedCompletions.formIntersection(completions)
        let busy = eligible.filter { $0.activity == .attention || $0.activity == .working }
        if !busy.isEmpty { suppressedCompletions.formUnion(completions) }
        let pending = eligible.filter { !suppressedCompletions.contains($0.id) }
        return pending.sorted {
            let left = Self.rank($0.activity), right = Self.rank($1.activity)
            if left != right { return left > right }
            if $0.priorityTime != $1.priorityTime { return $0.priorityTime > $1.priorityTime }
            return $0.id < $1.id
        }.first
    }
    private static func rank(_ activity: CodexActivity) -> Int {
        switch activity {
        case .attention: return 3
        case .working: return 2
        case .finished: return 1
        default: return 0
        }
    }
}
