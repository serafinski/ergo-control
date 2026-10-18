import AppKit
import ApplicationServices
import ErgoCore

/// An explicit idle fallback must not emit a global Play command: macOS may
/// launch Music before the chosen player has published its first media session.
final class PreferredMusicPlayback {
    private let worker = DispatchQueue(label: "dev.local.ergocontrol.preferred-music", qos: .userInitiated)
    private var pending = false // main thread; do not pile up work after a timeout
    func perform(_ app: MusicFallbackApplication, stillCurrent: @escaping () -> Bool,
                 completion: @escaping (String?) -> Void) {
        guard !pending else { completion("\(app.label) is still responding to the previous playback request."); return }
        guard let id = app.bundleID,
              let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first(where: { !$0.isTerminated }) else {
            completion("\(app.label) is no longer running."); return
        }
        pending = true
        let pid = running.processIdentifier
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        var delivered = false // main thread only
        let finish: (String?) -> Void = { error in
            guard !delivered else { return }
            delivered = true; completion(error)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            finish("\(app.label) did not confirm Play / pause in time. No second command was sent.")
        }
        worker.async {
            defer { DispatchQueue.main.async { self.pending = false } }
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.05)
            var value: CFTypeRef?
            let read = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
            let windows = read == .success ? value as? [AXUIElement] : nil
            // Multiple windows must not select an arbitrary player.
            let snapshots = windows?.map { MediaAccessibilitySnapshot.read($0, deadline: deadline) }
            let control = Self.playbackControl(in: snapshots)
            let current = DispatchQueue.main.sync {
                !delivered && ProcessInfo.processInfo.systemUptime < deadline && stillCurrent()
                    && !running.isTerminated && running.bundleIdentifier == id
            }
            guard current else {
                DispatchQueue.main.async { finish("\(app.label) playback request expired or was cancelled. No second command was sent.") }; return
            }
            let error: String?
            if let control {
                let result = AXUIElementPerformAction(control, kAXPressAction as CFString)
                // An uncertain press may already have acted. Never issue a
                // second/global command, which can toggle twice or open Music.
                error = result == .success ? nil : "\(app.label) could not confirm Play / pause. No second command was sent."
            } else {
                error = "No single enabled playback control was found in \(app.label). Choose a track there, then try again."
            }
            DispatchQueue.main.async { finish(error) }
        }
    }
    static func playbackControl(in snapshots: [MediaAccessibilitySnapshot?]?) -> AXUIElement? {
        guard let snapshots else { return nil }
        var candidates: [AXUIElement] = []
        for snapshot in snapshots {
            guard let snapshot else { return nil }
            switch snapshot.discovery {
            case .ambiguous: return nil
            case .none: break
            case .player(let group):
                guard snapshot.nodes.indices.contains(group.playPause),
                      snapshot.elements.indices.contains(group.playPause), snapshot.nodes[group.playPause].enabled else { return nil }
                candidates.append(snapshot.elements[group.playPause])
            }
        }
        return candidates.count == 1 ? candidates.first : nil
    }
}
