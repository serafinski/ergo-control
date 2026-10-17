import AppKit
import CoreGraphics
import Combine
import ErgoCore
import ErgoDevice

final class LightingAutomation: ObservableObject {
    @Published var preferences: LightingOffPreferences {
        didSet {
            if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: "lightingOffPreferences") }
            configureTimer(); refresh()
        }
    }
    private let defaults: UserDefaults
    private let device: BluetoothController
    private var displayAsleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
    private var lastKeyboardActivity = ProcessInfo.processInfo.systemUptime
    private var timer: Timer?
    private var observations = Set<AnyCancellable>()
    init(device: BluetoothController, defaults: UserDefaults = .standard) {
        self.device = device; self.defaults = defaults
        preferences = defaults.data(forKey: "lightingOffPreferences").flatMap { try? JSONDecoder().decode(LightingOffPreferences.self, from: $0) } ?? LightingOffPreferences()
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidSleepNotification)
            .sink { [weak self] _ in self?.displayAsleep = true; self?.refresh() }.store(in: &observations)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidWakeNotification)
            .sink { [weak self] _ in self?.displayAsleep = false; self?.refresh() }.store(in: &observations)
        configureTimer(); refresh()
    }
    func userActivity() { lastKeyboardActivity = ProcessInfo.processInfo.systemUptime; refresh() }
    private func configureTimer() {
        timer?.invalidate(); timer = nil
        guard preferences.whenIdle else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func refresh() {
        let systemIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        let idle = min(systemIdle, ProcessInfo.processInfo.systemUptime - lastKeyboardActivity)
        device.setLightingSuppressed(preferences.shouldTurnOff(displayAsleep: displayAsleep, idleSeconds: idle))
    }
    func stop() { timer?.invalidate(); timer = nil; observations.removeAll() }
    deinit { timer?.invalidate() }
}
