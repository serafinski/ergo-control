import Foundation
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
    let refreshAfter: TimeInterval?
}

/// Hardware-free routing, shared by live updates and tests. Each winning app
/// keeps its own palette and animation preferences while the renderer keeps
/// the original keyboard-effect snapshot across handoffs.
final class ChatLightingController {
    private let bridges: [ChatBridge]
    private var arbiter = ChatLightingArbiter()
    private var lastProvider: ChatProvider?
    private let uptime: () -> TimeInterval
    private var timedPresentation: String?
    private var presentationDeadline: TimeInterval?
    init(codex: ChatBridge, claude: ChatBridge, uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        bridges = [codex, claude]; self.uptime = uptime
    }
    func reset() {
        arbiter = ChatLightingArbiter(); lastProvider = nil
        timedPresentation = nil; presentationDeadline = nil
    }
    @discardableResult func completeWave(_ id: String) -> Bool {
        guard arbiter.complete(id) else { return false }
        timedPresentation = nil; presentationDeadline = nil
        return true
    }
    func output(mode: ChatLightingMode) -> ChatLightingOutput {
        let preview = bridges.first { mode.includes($0.provider) && $0.settings.enabled && $0.settings.lighting && $0.lightingTestStage != nil }
        let winner = arbiter.select(bridges.flatMap(\.lightingCandidates), mode: mode,
            eligibleChats: Set(bridges.flatMap(\.lightingChatIDs)), paused: preview != nil)
        if let deadline = presentationDeadline, uptime() >= deadline,
           timedPresentation == arbiter.presentationID, let id = timedPresentation {
            completeWave(id)
            return output(mode: mode)
        }
        let provider = preview?.provider ?? winner?.provider
        if let provider { lastProvider = provider }
        let bridge = bridges.first { $0.provider == (provider ?? lastProvider) } ?? bridges[0]
        if timedPresentation != arbiter.presentationID {
            timedPresentation = arbiter.presentationID
            // Waves hand back immediately after the final ACK. A finite
            // fallback also releases a stalled/unavailable renderer.
            presentationDeadline = timedPresentation.map { _ in uptime() + (bridge.settings.lightingArea == .completionWave
                ? 30 : CodexSessionStatus.completionSignalDuration) }
        }
        let activity = preview?.lightingActivity ?? winner?.activity ?? .idle
        let color = preview != nil ? bridge.lightingColor : winner.map { bridge.statusColors.color(for: $0.activity) }
        let signal = preview != nil ? bridge.lightingSignalID.map { "\(bridge.provider.rawValue):\($0)" } : arbiter.presentationID ?? winner?.id
        return ChatLightingOutput(provider: provider, color: color, activity: activity,
            signalID: bridge.settings.lightingArea == .completionWave ? signal : nil,
            area: bridge.settings.lightingArea, speed: bridge.settings.waveSpeed,
            pulseWhileWorking: bridge.settings.pulseWhileWorking, darkBackground: bridge.settings.darkStatusBackground,
            allowCompletionToFinish: preview == nil && winner == nil && mode.includes(bridge.provider) && bridge.allowsCompletionToFinish,
            refreshAfter: presentationDeadline.map { max(0.01, $0 - uptime()) })
    }
}
