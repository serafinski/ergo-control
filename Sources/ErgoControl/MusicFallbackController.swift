import AppKit
import ErgoCore

final class MusicFallbackController {
    typealias Query = (@escaping (MediaTargetAvailability) -> Void) -> Void
    typealias Open = (MusicFallbackApplication, @escaping (String?) -> Void) -> Void
    var onNotice: ((String) -> Void)?
    var onRoute: ((String) -> Void)?
    private let query: Query
    private let open: Open
    private let system: (MediaPlaybackCommand) -> Void
    private let isRunning: (MusicFallbackApplication) -> Bool
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
         system: @escaping (MediaPlaybackCommand) -> Void = MacMediaKeys.postPlayback) {
        self.query = query; self.open = open; self.isRunning = isRunning; self.system = system
    }
    func start(preferred: MusicFallbackApplication) {
        stop(); self.preferred = preferred; active = true
    }
    func stop() { generation += 1; active = false; pending = false }
    func perform(_ command: MediaPlaybackCommand, stillCurrent: @escaping () -> Bool = { true }) {
        guard active else { return }
        guard command == .playPause, preferred != .system else { sendSystem(command); return }
        guard !pending else { return }
        // An idle/paused app may not publish a MediaRemote client yet. Once
        // the preferred player is open, preserve the ordinary media command
        // instead of repeatedly activating it and swallowing Play/Pause.
        guard !isRunning(preferred) else { sendSystem(command); return }
        pending = true
        let ticket = generation, application = preferred
        query { [weak self] availability in
            guard let self, self.active, self.generation == ticket else { return }
            guard stillCurrent() else { self.pending = false; return }
            guard !self.isRunning(application) else {
                self.pending = false; self.sendSystem(command); return
            }
            switch MusicFallbackDecision.resolve(command: command, preferred: application, target: availability) {
            case .system:
                self.pending = false; self.sendSystem(command)
            case .open(let app):
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
