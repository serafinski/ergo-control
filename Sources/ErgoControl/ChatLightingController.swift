import ErgoCore

struct ChatLightingOutput: Equatable {
    let provider: ChatProvider?
    let color: DialColor?
    let activity: CodexActivity
    let signalID: String?
    let area: CodexLightingArea
    let speed: CodexWaveSpeed
    let pulseWhileWorking: Bool
    let darkBackground: Bool
    let allowCompletionToFinish: Bool
}

/// Hardware-free routing, shared by live updates and tests. Each winning app
/// keeps its own palette and animation preferences while the renderer keeps
/// the original keyboard-effect snapshot across handoffs.
final class ChatLightingController {
    private let bridges: [ChatBridge]
    private var arbiter = ChatLightingArbiter()
    private var lastProvider: ChatProvider?
    init(codex: ChatBridge, claude: ChatBridge) { bridges = [codex, claude] }
    func reset() { arbiter = ChatLightingArbiter(); lastProvider = nil }
    func output(mode: ChatLightingMode) -> ChatLightingOutput {
        let winner = arbiter.select(bridges.flatMap(\.lightingCandidates), mode: mode)
        let preview = bridges.first { mode.includes($0.provider) && $0.settings.enabled && $0.settings.lighting && $0.lightingTestStage != nil }
        let provider = preview?.provider ?? winner?.provider
        if let provider { lastProvider = provider }
        let bridge = bridges.first { $0.provider == (provider ?? lastProvider) } ?? bridges[0]
        let activity = preview?.lightingActivity ?? winner?.activity ?? .idle
        let color = preview != nil ? bridge.lightingColor : winner.map { bridge.statusColors.color(for: $0.activity) }
        let signal = preview != nil ? bridge.lightingSignalID.map { "\(bridge.provider.rawValue):\($0)" } : winner?.id
        return ChatLightingOutput(provider: provider, color: color, activity: activity,
            signalID: bridge.settings.lightingArea == .completionWave ? signal : nil,
            area: bridge.settings.lightingArea, speed: bridge.settings.waveSpeed,
            pulseWhileWorking: bridge.settings.pulseWhileWorking, darkBackground: bridge.settings.darkStatusBackground,
            allowCompletionToFinish: preview == nil && winner == nil && mode.includes(bridge.provider) && bridge.allowsCompletionToFinish)
    }
}
