import AppKit
import ServiceManagement
import SwiftUI

final class StartupSettings: ObservableObject {
    @Published private(set) var loginEnabled = false
    @Published private(set) var loginMessage = ""
    @Published var automaticMappings: Bool {
        didSet { defaults.set(automaticMappings, forKey: "automaticMappings") }
    }
    private let defaults: UserDefaults
    var installedInApplications: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().deletingLastPathComponent().path
        return path == "/Applications" || path == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        automaticMappings = defaults.bool(forKey: "automaticMappings")
        refresh()
    }
    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled: loginEnabled = true; loginMessage = "Ergo Control will open when you log in."
        case .requiresApproval: loginEnabled = false; loginMessage = "Allow Ergo Control in System Settings → General → Login Items."
        case .notRegistered: loginEnabled = false; loginMessage = "Launch at login is off."
        case .notFound: loginEnabled = false; loginMessage = "Move Ergo Control to Applications, then reopen it."
        @unknown default: loginEnabled = false; loginMessage = "Login status is unavailable."
        }
    }
    func setLoginEnabled(_ enabled: Bool) {
        guard !enabled || installedInApplications else {
            loginMessage = "Move Ergo Control to Applications and reopen it before enabling launch at login."
            return
        }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refresh()
        } catch { refresh(); loginMessage = error.localizedDescription }
    }
}

struct AppSettingsView: View {
    @ObservedObject var startup: StartupSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("App").font(.largeTitle.bold())
            GroupBox("Startup") {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Launch at login", isOn: Binding(get: { startup.loginEnabled }, set: startup.setLoginEnabled))
                    Text(startup.loginMessage).font(.caption).foregroundStyle(.secondary)
                    Toggle("Enable mappings automatically", isOn: $startup.automaticMappings)
                    Text("Start your saved mappings when Ergo Control opens. Keep waiting if the keyboard connects later. If mappings were active before sleep, resume after waking. Stop mappings cancels a pending start; an activation error requires a manual retry.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Codex connection and status-light choices are remembered automatically. These settings take effect immediately; no Save changes is needed.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Login Items settings…") { SMAppService.openSystemSettingsLoginItems() }
                        Button("Refresh status") { startup.refresh() }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            GroupBox("Installation") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(startup.installedInApplications ? "Running from Applications" : "Running from another folder")
                    Text("Quit Ergo Control, drag it from the disk image to Applications, eject the image, then open the Applications copy. Your profiles and Codex settings stay on this Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(Bundle.main.bundleURL.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
        }.onAppear { startup.refresh() }
    }
}
