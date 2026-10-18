import AppKit
import ErgoCore

final class MusicFallbackController {
    typealias Query = (@escaping (MediaTargetAvailability) -> Void) -> Void
    typealias Open = (MusicFallbackApplication, @escaping (String?) -> Void) -> Void
    typealias Playback = (MusicFallbackApplication, @escaping () -> Bool, @escaping (String?) -> Void) -> Void
    var onNotice: ((String) -> Void)?
    var onRoute: ((String) -> Void)?
    private let query: Query
    private let open: Open
    private let system: (MediaPlaybackCommand) -> Void
    private let isRunning: (MusicFallbackApplication) -> Bool
    private let playback: Playback
    private var preferred: MusicFallbackApplication = .system
    private var generation = 0
    private var active = false
    private var pending = false
    init(query: @escaping Query = SystemMediaTarget().query,
         open: @escaping Open = MusicFallbackController.openApplication,
         isRunning: @escaping (MusicFallbackApplication) -> Bool = { app in
             guard let id = app.bundleID else { return false }
             return NSRunningApplication.runningApplications(withBundleIdentifier: id).contains { !$0.isTerminated }
         },
         playback: @escaping Playback = PreferredMusicPlayback().perform,
         system: @escaping (MediaPlaybackCommand) -> Void = MacMediaKeys.postPlayback) {
        self.query = query; self.open = open; self.isRunning = isRunning; self.playback = playback; self.system = system
    }
    func start(preferred: MusicFallbackApplication) {
        stop(); self.preferred = preferred; active = true
    }
    func stop() { generation += 1; active = false; pending = false }
    func perform(_ command: MediaPlaybackCommand, stillCurrent: @escaping () -> Bool = { true }) {
        guard active else { return }
        guard command == .playPause, preferred != .system else { sendSystem(command); return }
        guard !pending else { return }
        pending = true
        let ticket = generation, application = preferred
        query { [weak self] availability in
            guard let self, self.active, self.generation == ticket else { return }
            guard stillCurrent() else { self.pending = false; return }
            // With no identified target, a running preferred app needs its
            // own transport control; a global command can launch Apple Music.
            let target: MediaTargetAvailability = availability == .unknown && self.isRunning(application) ? .none : availability
            switch MusicFallbackDecision.resolve(command: command, preferred: application, target: target) {
            case .system:
                self.pending = false; self.sendSystem(command)
            case .open(let app):
                if self.isRunning(app) {
                    self.playback(app, { [weak self] in
                        self?.active == true && self?.generation == ticket && stillCurrent()
                    }) { [weak self] error in
                        guard let self, self.active, self.generation == ticket else { return }
                        self.pending = false
                        guard stillCurrent() else { return }
                        if let error { self.onNotice?(error) }
                        else { self.onRoute?("Play / pause → \(app.label) playback control") }
                    }
                    return
                }
                self.open(app) { [weak self] error in
                    guard let self, self.active, self.generation == ticket else { return }
                    self.pending = false
                    if let error { self.onNotice?(error) }
                    else { self.onRoute?("Play / pause → opened \(app.label) (no media target)") }
                }
            }
        }
    }
    private func sendSystem(_ command: MediaPlaybackCommand) {
        system(command); onRoute?("\(command.label) → macOS media target")
    }
    private static func openApplication(_ application: MusicFallbackApplication, completion: @escaping (String?) -> Void) {
        guard let id = application.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            completion("\(application.label) is not installed. Choose another music app under Keyboard → Buttons."); return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            DispatchQueue.main.async { completion(error.map { "Could not open \(application.label): \($0.localizedDescription)" }) }
        }
    }
}
