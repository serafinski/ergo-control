import Foundation

public enum MappingOrigin: Equatable {
    case standardLayer, alternateLayer, automatic, keyboardDefault
    public var label: String {
        switch self {
        case .standardLayer: return "Standard mapping"
        case .alternateLayer: return "Alternate mapping"
        case .automatic: return "Automatic default"
        case .keyboardDefault: return "Keyboard default"
        }
    }
}

public struct ResolvedMapping: Equatable {
    public let action: MappingAction
    public let origin: MappingOrigin
}

public struct MacroKeyAssignment: Equatable, Identifiable {
    public let id: Int
    public let mapping: ResolvedMapping
    public var slot: Int? {
        guard mapping.action.kind == .codexChat || mapping.action.kind == .claudeChat,
              let slot = Int(mapping.action.value), (1...5).contains(slot) else { return nil }
        return slot
    }
    public var provider: ChatProvider? {
        guard slot != nil else { return nil }
        return mapping.action.kind == .codexChat ? .codex : .claude
    }
}

/// Shared by keyboard dispatch and the assignment display. An explicit action
/// (including Do nothing) always takes precedence over an automatic chat action.
public enum MappingResolver {
    public static func resolve(_ control: String, profile: MappingProfile, alternateLayer: Bool,
                               fallback: MappingAction? = nil) -> ResolvedMapping {
        if alternateLayer, let action = profile.alternate[control], action.kind != .standard {
            return ResolvedMapping(action: action, origin: .alternateLayer)
        }
        if let action = profile.mappings[control], action.kind != .standard {
            return ResolvedMapping(action: action, origin: .standardLayer)
        }
        if let fallback, fallback.kind != .standard { return ResolvedMapping(action: fallback, origin: .automatic) }
        return ResolvedMapping(action: MappingAction(), origin: .keyboardDefault)
    }
    public static func macroKeys(profile: MappingProfile, alternateLayer: Bool,
                                 fallback: (String) -> MappingAction? = { _ in nil }) -> [MacroKeyAssignment] {
        (1...5).map { number in
            let control = "extra:\(number + 31)"
            return MacroKeyAssignment(id: number, mapping: resolve(control, profile: profile,
                alternateLayer: alternateLayer, fallback: fallback(control)))
        }
    }
}
