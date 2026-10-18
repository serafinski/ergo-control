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
            // Native menus are small and independent of Electron's large,
            // sometimes incomplete web accessibility tree. Match only the
            // exact Play/Pause menu action, never a playlist's Play button.
            let control = Self.menuControl(application, deadline: deadline)
            let current = DispatchQueue.main.sync {
                !delivered && ProcessInfo.processInfo.systemUptime < deadline && stillCurrent()
                    && !running.isTerminated && running.bundleIdentifier == id
            }
            guard current else {
                DispatchQueue.main.async { finish("\(app.label) playback request expired or was cancelled. No second command was sent.") }; return
            }
            let error: String?
            if let control {
                var actions: CFArray?
                AXUIElementCopyActionNames(control, &actions)
                let names = actions as? [String] ?? []
                let action = names.contains(kAXPressAction as String) ? kAXPressAction : kAXPickAction
                let result = names.contains(action as String) ? AXUIElementPerformAction(control, action as CFString) : .actionUnsupported
                // An uncertain press may already have acted. Never issue a
                // second/global command, which can toggle twice or open Music.
                error = result == .success ? nil : "\(app.label) could not confirm Play / pause. No second command was sent."
            } else {
                error = "No single enabled Play / pause menu action was found in \(app.label). Choose a track there, then try again."
            }
            DispatchQueue.main.async { finish(error) }
        }
    }
    private static func menuControl(_ application: AXUIElement, deadline: TimeInterval) -> AXUIElement? {
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
            return value
        }
        guard let bar = attribute(application, kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
        var queue: [(AXUIElement, Int)] = [(bar as! AXUIElement, 0)]
        var elements: [AXUIElement] = [], controls: [(labels: [String], enabled: Bool)] = []
        var visited = 0
        while let (element, depth) = queue.popLast() {
            visited += 1
            guard visited <= 400, ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            guard let role = attribute(element, kAXRoleAttribute) as? String else { return nil }
            if role == kAXMenuItemRole {
                let labels = [kAXTitleAttribute, kAXDescriptionAttribute].compactMap { attribute(element, $0) as? String }
                if MediaControl.button(labels: labels) == .playPause {
                    elements.append(element)
                    controls.append((labels, attribute(element, kAXEnabledAttribute) as? Bool ?? false))
                }
            }
            if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement], !children.isEmpty {
                guard depth < 12 else { return nil }
                queue.append(contentsOf: children.reversed().map { ($0, depth + 1) })
            }
        }
        guard let index = menuPlaybackIndex(in: controls) else { return nil }
        return elements[index]
    }
    static func menuPlaybackIndex(in items: [(labels: [String], enabled: Bool)]) -> Int? {
        let matches = items.indices.filter { MediaControl.button(labels: items[$0].labels) == .playPause }
        guard matches.count == 1, let index = matches.first, items[index].enabled else { return nil }
        return index
    }
}
