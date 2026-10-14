import AppKit
import ApplicationServices
import ErgoCore

/// Only acts on the application explicitly chosen for this mapping. AX elements
/// remain in memory so the next press restores the exact window we minimized.
final class ApplicationToggle {
    private var minimized: [pid_t: AXUIElement] = [:]
    private var opening: Set<String> = []
    private var generation = 0

    func cancelPending() { generation += 1; opening.removeAll() }

    func perform(_ url: URL, onError: @escaping (String) -> Void) throws {
        guard url.pathExtension == "app", let id = Bundle(url: url)?.bundleIdentifier else {
            throw MappingValidationError.message("Choose an application")
        }
        guard !opening.contains(id) else { return }
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first(where: { !$0.isTerminated })
        let visibleWindow = app.flatMap { preferredWindow(for: $0, minimized: false) }
        let decision = ApplicationToggleDecision.resolve(isRunning: app != nil, isFrontmost: app?.isActive == true,
                                                         hasVisibleWindow: visibleWindow != nil)
        if decision == .minimize, let app, let window = visibleWindow {
            guard AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success else {
                throw MappingValidationError.message("This application's window could not be minimized.")
            }
            minimized[app.processIdentifier] = window
            return
        }

        // Opening also asks an already running app with no windows to reopen one.
        opening.insert(id)
        let ticket = generation
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { [weak self] app, error in
            DispatchQueue.main.async {
                guard let self, self.generation == ticket else { return }
                self.opening.remove(id)
                if let error { onError(error.localizedDescription); return }
                guard let app else { return }
                self.minimized = self.minimized.filter { NSRunningApplication(processIdentifier: $0.key)?.isTerminated == false }
                let saved = self.minimized.removeValue(forKey: app.processIdentifier)
                let window = saved ?? self.preferredWindow(for: app, minimized: true)
                if let window {
                    let result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                    if result != .success, let fallback = self.preferredWindow(for: app, minimized: true) {
                        _ = AXUIElementSetAttributeValue(fallback, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                        _ = AXUIElementPerformAction(fallback, kAXRaiseAction as CFString)
                    } else if result == .success { _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString) }
                }
                app.activate()
            }
        }
    }

    private func preferredWindow(for app: NSRunningApplication, minimized desired: Bool) -> AXUIElement? {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var candidates: [AXUIElement] = []
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
               let value, CFGetTypeID(value) == AXUIElementGetTypeID() { candidates.append(value as! AXUIElement) }
        }
        var windows: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windows) == .success,
           let list = windows as? [AXUIElement] { candidates.append(contentsOf: list) }
        return candidates.first { window in
            var value: CFTypeRef?
            var settable: DarwinBoolean = false
            return AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value) == .success
                && (value as? Bool) == desired
                && AXUIElementIsAttributeSettable(window, kAXMinimizedAttribute as CFString, &settable) == .success
                && settable.boolValue
        }
    }
}
