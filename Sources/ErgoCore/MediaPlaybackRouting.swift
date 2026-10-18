import Foundation

public enum MediaPlaybackCommand: String, Equatable, CaseIterable {
    case playPause, next, previous
    public init?(usage: UInt16) {
        switch usage {
        case 0xcd: self = .playPause
        case 0xb5: self = .next
        case 0xb6: self = .previous
        default: return nil
        }
    }
    public var usage: UInt16 {
        switch self { case .playPause: return 0xcd; case .next: return 0xb5; case .previous: return 0xb6 }
    }
    public var label: String {
        switch self { case .playPause: return "Play / pause"; case .next: return "Next track"; case .previous: return "Previous track" }
    }
}

/// Playback controls, not application names or page URLs. Restrict labels to
/// whole control names; “Play playlist …” and browser Back/Forward are not media.
public enum MediaControl: Equatable {
    case playPause, next, previous, mute, timeline
    public static func button(labels: [String]) -> MediaControl? {
        for label in labels {
            let name = label.components(separatedBy: "(").first!.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).replacingOccurrences(of: "ł", with: "l")
                .replacingOccurrences(of: #"\s+(?:skrot klawiszowy|keyboard shortcut)\s+(?:[a-z0-9]|space|spacja|shift\+[a-z])$"#,
                                      with: "", options: .regularExpression)
            switch name {
            case "play", "pause", "play/pause", "play / pause", "resume", "odtworz", "odtwarzaj", "wstrzymaj", "pauza", "wznow": return .playPause
            case "next", "next track", "next video", "dalej", "nastepny", "nastepny utwor", "nastepny film": return .next
            case "previous", "previous track", "previous video", "poprzedni", "poprzedni utwor", "poprzedni film": return .previous
            case "mute", "unmute", "wycisz", "wylacz wyciszenie", "wlacz dzwiek": return .mute
            default: continue
            }
        }
        return nil
    }
    public static func slider(labels: [String]) -> MediaControl? {
        let names: Set<String> = ["volume", "playback position", "playback timeline", "seek", "seek slider", "progress", "glosnosc", "zmien glosnosc", "zmien postep"]
        return labels.contains {
            names.contains($0.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).replacingOccurrences(of: "ł", with: "l"))
        } ? .timeline : nil
    }

}

public struct MediaControlNode {
    public let parent: Int?
    public let control: MediaControl?
    public let enabled: Bool
    public init(parent: Int?, control: MediaControl? = nil, enabled: Bool = true) {
        self.parent = parent; self.control = control; self.enabled = enabled
    }
}

public struct MediaControlGroup: Equatable {
    public let root: Int
    public let playPause: Int
    public let next: Int?
    public let previous: Int?
    public func index(for command: MediaPlaybackCommand) -> Int? {
        switch command { case .playPause: return playPause; case .next: return next; case .previous: return previous }
    }
}

/// A Play button alone could start a playlist, game or preview. Require a small
/// transport group with one Play/Pause and supporting playback controls. Never
/// arbitrarily choose between two equally plausible players.
public enum MediaControlDiscovery: Equatable {
    case none, ambiguous, player(MediaControlGroup)
    public static func find(in nodes: [MediaControlNode]) -> MediaControlDiscovery {
        var children = Array(repeating: [Int](), count: nodes.count)
        for (i, node) in nodes.enumerated() {
            if let parent = node.parent, parent >= 0, parent < i { children[parent].append(i) }
        }
        var candidates: [(MediaControlGroup, Int)] = []
        for play in nodes.indices where nodes[play].control == .playPause {
            var root = nodes[play].parent
            for distance in 0..<4 {
                guard let groupRoot = root, nodes.indices.contains(groupRoot) else { break }
                var members: [Int] = [], pending = [groupRoot]
                while let member = pending.popLast(), members.count <= 120 {
                    members.append(member); pending.append(contentsOf: children[member])
                }
                if members.count <= 120, members.filter({ nodes[$0].control == .playPause }).count == 1 {
                    let next = members.filter { nodes[$0].control == .next }
                    let previous = members.filter { nodes[$0].control == .previous }
                    let hasMute = members.contains { nodes[$0].control == .mute }
                    let hasTimeline = members.contains { nodes[$0].control == .timeline }
                    if next.count <= 1, previous.count <= 1,
                       (!next.isEmpty && !previous.isEmpty) || hasMute || hasTimeline {
                        let score = (!next.isEmpty && !previous.isEmpty ? 30 : 0) + (hasMute ? 20 : 0) + (hasTimeline ? 10 : 0) - distance
                        candidates.append((MediaControlGroup(root: groupRoot, playPause: play, next: next.first, previous: previous.first), score))
                    }
                }
                root = nodes[groupRoot].parent
            }
        }
        guard let best = candidates.map(\.1).max() else { return .none }
        let strongest = candidates.filter { $0.1 == best }
        guard Set(strongest.map { $0.0.playPause }).count == 1, let selected = strongest.first else { return .ambiguous }
        return .player(selected.0)
    }
}

/// A recognized foreground player owns the command even if Next/Previous is
/// unavailable. It must not accidentally skip a different background player.
public enum MediaPlaybackRoute: Equatable {
    case focused, remembered, system, unavailable
    public static func resolve(command: MediaPlaybackCommand, focused: MediaControlDiscovery,
                               remembered: MediaControlDiscovery) -> MediaPlaybackRoute {
        switch focused {
        case .player(let group): return group.index(for: command) == nil ? .unavailable : .focused
        case .ambiguous: return .unavailable
        case .none:
            switch remembered {
            case .player(let group): return group.index(for: command) == nil ? .unavailable : .remembered
            case .ambiguous: return .unavailable
            case .none: return .system
            }
        }
    }
}
