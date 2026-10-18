public enum MusicFallbackApplication: String, CaseIterable, Identifiable {
    case system, music, spotify
    public init(savedValue: String?) { self = Self(rawValue: savedValue ?? "") ?? .system }
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .system: return "macOS default"
        case .music: return "Apple Music"
        case .spotify: return "Spotify"
        }
    }
    public var bundleID: String? {
        switch self {
        case .system: return nil
        case .music: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        }
    }
}

/// An explicit idle app is a fallback behind the currently focused player.
/// The experimental option additionally remembers previous player windows.
public enum MusicPlaybackDispatch: Equatable {
    case focused, fallback
    public static func resolve(command: MediaPlaybackCommand, preferred: MusicFallbackApplication,
                               focusFirst: Bool, foregroundBundleID: String?) -> Self {
        if focusFirst { return .focused }
        guard command == .playPause, preferred != .system,
              foregroundBundleID != preferred.bundleID else { return .fallback }
        return .focused
    }
}
public enum MusicFallbackDecision: Equatable {
    case system, open, control
    public static func resolve(command: MediaPlaybackCommand, preferred: MusicFallbackApplication,
                               running: Bool) -> Self {
        guard command == .playPause, preferred != .system else { return .system }
        return running ? .control : .open
    }
}
