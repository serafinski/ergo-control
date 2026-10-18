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

public enum MediaTargetAvailability { case available, none, unknown }
public enum MusicFallbackDecision: Equatable {
    case system, open(MusicFallbackApplication)
    public static func resolve(command: MediaPlaybackCommand, preferred: MusicFallbackApplication,
                               target: MediaTargetAvailability) -> Self {
        guard command == .playPause, preferred != .system else { return .system }
        switch target {
        case .available: return .system
        case .none: return .open(preferred)
        // The optional idle detector must never disable normal playback.
        case .unknown: return .system
        }
    }
}
