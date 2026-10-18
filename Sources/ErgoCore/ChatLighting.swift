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
    public let chatID: String
    public let activity: CodexActivity
    public let priorityTime: Date
    public init?(provider: ChatProvider, session: CodexSessionStatus, now: Date,
                 completionDuration: TimeInterval = CodexSessionStatus.completionSignalDuration) {
        let activity = session.activity(now: now, completionDuration: completionDuration)
        guard [.working, .attention, .finished].contains(activity) else { return nil }
        self.provider = provider; self.activity = activity
        chatID = "\(provider.rawValue):\(session.latest.sessionID)"
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
    private var pending: [ChatLightingCandidate] = []
    private var seen: [String] = []
    private var activeCompletion: ChatLightingCandidate?
    private var revision: UInt64 = 0
    private let epoch = UUID().uuidString
    public private(set) var presentationID: String?
    public init() {}
    public mutating func select(_ candidates: [ChatLightingCandidate], mode: ChatLightingMode,
                                eligibleChats: Set<String>? = nil, paused: Bool = false) -> ChatLightingCandidate? {
        func included(_ candidate: ChatLightingCandidate) -> Bool {
            mode.includes(candidate.provider) && (eligibleChats?.contains(candidate.chatID) ?? true)
        }
        let eligible = candidates.filter(included)
        pending.removeAll { !included($0) }
        if let activeCompletion, !included(activeCompletion) { self.activeCompletion = nil; presentationID = nil }
        for completion in eligible.filter({ $0.activity == .finished }).sorted(by: {
            $0.priorityTime == $1.priorityTime ? $0.id < $1.id : $0.priorityTime < $1.priorityTime
        }) where !seen.contains(completion.id) {
            seen.append(completion.id); pending.append(completion)
        }
        // Transient, bounded notifications; duplicate Stop hooks do not replay.
        if seen.count > 256 { seen.removeFirst(seen.count - 256) }
        if pending.count > 32 { pending.removeFirst(pending.count - 32) }
        let approval = eligible.filter { $0.activity == .attention }.sorted(by: Self.newest).first
        if approval != nil || paused {
            if let activeCompletion { pending.insert(activeCompletion, at: 0) }
            activeCompletion = nil; presentationID = nil
            return approval ?? eligible.filter { $0.activity == .working }.sorted(by: Self.newest).first
        }
        if activeCompletion == nil, !pending.isEmpty {
            activeCompletion = pending.removeFirst(); revision &+= 1
            presentationID = activeCompletion.map { "\($0.id):notification:\(epoch):\(revision)" }
        }
        return activeCompletion ?? eligible.filter { $0.activity == .working }.sorted(by: Self.newest).first
    }
    /// Called after the acknowledged wave, or the bounded solid-color display.
    @discardableResult public mutating func complete(_ id: String) -> Bool {
        guard presentationID == id else { return false }
        activeCompletion = nil; presentationID = nil
        return true
    }
    private static func newest(_ left: ChatLightingCandidate, _ right: ChatLightingCandidate) -> Bool {
        if left.priorityTime != right.priorityTime { return left.priorityTime > right.priorityTime }
        return left.id < right.id
    }
}
