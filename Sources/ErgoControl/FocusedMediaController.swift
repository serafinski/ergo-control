import AppKit
import ApplicationServices
import ErgoCore

/// General focus-first routing through the player's accessible transport bar.
/// No app allowlist, page script, keyboard shortcut, activation or private API.
/// AX reads run only on focus changes / media presses, on a bounded worker queue.
final class FocusedMediaController {
    var onNotice: ((String) -> Void)?
    var onRoute: ((String) -> Void)?
    var onSystemPlayback: (MediaPlaybackCommand) -> Void = MacMediaKeys.postPlayback
    private let worker = DispatchQueue(label: "dev.local.ergocontrol.media", qos: .userInitiated)
    private let lock = NSLock()
    private var generation = 0
    private var pending = 0
    private var active = false
    private var observer: AXObserver?
    private var observedApp: AXUIElement?
    // Accessed only on worker; never persisted or logged.
    private var focused: (pid: pid_t, window: AXUIElement)?
    private var remembered: AXUIElement?

    func start() { active = true; focusChanged() }
    func stop() {
        active = false
        lock.withLock { generation += 1 }
        removeObserver()
        worker.async { [weak self] in self?.focused = nil; self?.remembered = nil }
    }
    func focusChanged() {
        guard active, let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier
        watchWindows(pid)
        let ticket = lock.withLock { generation }
        worker.async { [weak self] in
            guard let self, self.current(ticket) else { return }
            self.rememberPreviousWindow()
            self.focused = self.window(pid).map { (pid, $0) }
        }
    }
    func perform(_ command: MediaPlaybackCommand) {
        guard active, let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier
        let ticket: Int? = lock.withLock {
            guard pending < 8 else { return nil }
            pending += 1; return generation
        }
        guard let ticket else { return }
        worker.async { [weak self] in
            guard let self else { return }
            defer { self.lock.withLock { self.pending -= 1 } }
            guard self.current(ticket) else { return }
            let window = self.window(pid)
            if let prior = self.focused, window.map({ !CFEqual($0, prior.window) }) ?? true {
                self.rememberPreviousWindow()
            }
            self.focused = window.map { (pid, $0) }
            let foreground = window.flatMap(self.snapshot)
            let focusedDiscovery = foreground?.discovery ?? (window == nil ? .none : .ambiguous)
            let previous: MediaAccessibilitySnapshot? = focusedDiscovery == .none ? self.remembered.flatMap(self.snapshot) : nil
            let route = MediaPlaybackRoute.resolve(command: command, focused: focusedDiscovery,
                                                    remembered: previous?.discovery ?? .none)
            // Never act on an old focus after a slow AX query or queue delay.
            let stillFocused = DispatchQueue.main.sync {
                self.active && self.current(ticket) && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
            }
            guard stillFocused else { return }
            switch route {
            case .focused, .remembered:
                guard let tree = route == .focused ? foreground : previous,
                      case .player(let group) = tree.discovery,
                      let index = group.index(for: command) else { return }
                guard tree.nodes[index].enabled else {
                    self.notice("\(command.label) is unavailable in the selected media window.", ticket); return
                }
                if route == .focused, let window {
                    guard let currentWindow = self.window(pid), CFEqual(currentWindow, window) else { return }
                }
                let result = AXUIElementPerformAction(tree.elements[index], kAXPressAction as CFString)
                // A timed-out AXPress might already have acted. Never retry it
                // as a global toggle and risk pausing twice.
                if result == .success {
                    self.remembered = tree.elements[group.root]
                    self.record("\(command.label) → \(route == .focused ? "focused window" : "last media window")", ticket)
                } else { self.notice("The media window could not confirm \(command.label.lowercased()). No second command was sent.", ticket) }
            case .unavailable:
                self.notice("\(command.label) is unavailable or multiple media players are visible in the selected window.", ticket)
            case .system:
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.active, self.current(ticket),
                          NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                    self.onSystemPlayback(command)
                }
            }
        }
    }
    private func current(_ ticket: Int) -> Bool { lock.withLock { generation == ticket } }
    private func notice(_ message: String, _ ticket: Int) {
        DispatchQueue.main.async { [weak self] in guard let self, self.current(ticket) else { return }; self.onNotice?(message) }
    }
    private func record(_ message: String, _ ticket: Int) {
        DispatchQueue.main.async { [weak self] in guard let self, self.current(ticket) else { return }; self.onRoute?(message) }
    }
    private func rememberPreviousWindow() {
        if let prior = focused, let tree = snapshot(prior.window), case .player(let group) = tree.discovery {
            remembered = tree.elements[group.root]
        }
    }
    private func window(_ pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.05)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private func snapshot(_ root: AXUIElement) -> MediaAccessibilitySnapshot? { .read(root) }
    private func watchWindows(_ pid: pid_t) {
        removeObserver()
        var newObserver: AXObserver?
        let result = AXObserverCreate(pid, { _, _, _, context in
            guard let context else { return }
            Unmanaged<FocusedMediaController>.fromOpaque(context).takeUnretainedValue().focusChanged()
        }, &newObserver)
        guard result == .success, let newObserver else { return }
        let app = AXUIElementCreateApplication(pid)
        guard AXObserverAddNotification(newObserver, app, kAXFocusedWindowChangedNotification as CFString,
                                        Unmanaged.passUnretained(self).toOpaque()) == .success else { return }
        observer = newObserver; observedApp = app
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .commonModes)
    }
    private func removeObserver() {
        if let observer {
            if let observedApp { AXObserverRemoveNotification(observer, observedApp, kAXFocusedWindowChangedNotification as CFString) }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil; observedApp = nil
    }
    deinit { removeObserver() }
}
