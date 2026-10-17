import SwiftUI
import AppKit
import ApplicationServices
import IOKit.hid
import CoreServices
import ErgoCore
import ErgoDevice

final class ControlAppDelegate: NSObject, NSApplicationDelegate {
    var model: ControlModel?
    private var launchedAtLogin: Bool {
        NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { !launchedAtLogin }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if launchedAtLogin {
            DispatchQueue.main.async { NSApp.windows.filter { $0.canBecomeMain }.forEach { $0.orderOut(nil) } }
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { model?.terminate() ?? .terminateNow }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct ErgoControlApp: App {
    @NSApplicationDelegateAdaptor(ControlAppDelegate.self) var delegate
    @StateObject private var model: ControlModel
    init() {
        if CommandLine.arguments.contains("--keyboard-discovery-check") { PairedKeyboardDiscovery.checkCommandLine() }
        if CommandLine.arguments.contains("--codex-history-check") { CodexHistoryReader.checkCommandLine() }
        if CommandLine.arguments.dropFirst().first == "--lighting-lab" {
            LightingLabRunner.runCommandLine(Array(CommandLine.arguments.dropFirst(2)))
        }
        if CommandLine.arguments.dropFirst().first == "--restore-keyboard" {
            NativeDialInspection.restoreKeyboardCommandLine()
        }
        if CommandLine.arguments.dropFirst().first == "--keyboard-power-test" {
            NativeDialInspection.testPowerCommandLine()
        }
        if CommandLine.arguments.dropFirst().first == "--keyboard-power-read" {
            NativeDialInspection.readPowerCommandLine()
        }
        if CommandLine.arguments.dropFirst().first == "--lighting-read" {
            NativeDialInspection.readLightingCommandLine()
        }
        if CommandLine.arguments.dropFirst().first == "--native-dial-read" {
            NativeDialInspection.runCommandLine()
        }
        if CommandLine.arguments.contains("--helper-access-status") { HelperPermissionCheck.runCommandLine() }
        if CommandLine.arguments.contains("--helper-service-status") { FullControlHelper.statusCommandLine() }
        let model = ControlModel()
        _model = StateObject(wrappedValue: model)
        // Login launches may never show Settings or open the menu. Termination
        // must still reach the model and verify restoration before exiting.
        delegate.model = model
    }
    var body: some Scene {
        WindowGroup("Ergo Control", id: "settings") {
            ControlSettingsView(model: model)
        }.defaultSize(width: 1280, height: 850)
        MenuBarExtra {
            ControlMenu(model: model)
        } label: {
            HStack(spacing: 4) {
                Image(nsImage: AppBranding.menuMark).renderingMode(.template)
                Text(model.menuBarBatteryLabel).monospacedDigit()
            }
            .accessibilityLabel("Ergo Control, keyboard battery \(model.menuBarBatteryLabel)")
        }
    }
}

struct ControlMenu: View {
    @ObservedObject var model: ControlModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(model.running ? "Mappings active" : "Mappings off")
        Text("\(model.activeProfileName) · \(model.dialName)")
        Text(model.bluetooth.batteryText)
        Button("Refresh battery") { model.refreshBattery() }
        Divider()
        Button("Settings…") { openWindow(id: "settings"); NSApp.activate(ignoringOtherApps: true) }
        Button(model.running || model.preparing || model.waitingForAutomaticStart ? "Stop mappings" : "Enable mappings") {
            if model.running || model.preparing || model.waitingForAutomaticStart { model.stop() } else { model.start() }
        }
        Divider()
        Button("Quit Ergo Control") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

struct ControlSettingsView: View {
    @ObservedObject var model: ControlModel
    private enum Section: Hashable { case keyboard, codex, app, setup, logs }
    @State private var section = Section.keyboard
    @FocusState private var focusedSection: Section?
    @State private var keyboardPage = KeyboardSettingsPage.buttons

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            switch section {
            case .keyboard:
                KeyboardSettingsView(model: model, page: $keyboardPage) {
                    section = .setup; focusedSection = .setup
                }
            case .codex:
                ScrollView { ChatSettingsView(model: model).frame(maxWidth: 900).frame(maxWidth: .infinity).padding(28) }
            case .app:
                ScrollView { AppSettingsView(startup: model.startup).frame(maxWidth: 800).frame(maxWidth: .infinity).padding(28) }
            case .setup:
                ScrollView { KeyboardSetupView(model: model).frame(maxWidth: 800).frame(maxWidth: .infinity).padding(28) }
            case .logs:
                ScrollView { AppLogView(log: model.logs).frame(maxWidth: 1000).frame(maxWidth: .infinity).padding(28) }
            }
        }
        .frame(minWidth: 980, minHeight: 760)
        .disclosureGroupStyle(WholeRowDisclosureStyle())
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(nsImage: AppBranding.appIcon).resizable().frame(width: 32, height: 32).accessibilityHidden(true)
                Text("Ergo Control").font(.title2.bold())
            }
            Text("PRO TYPE ERGO").font(.caption).foregroundStyle(.secondary)
            Divider()
            VStack(spacing: 6) {
                sectionButton("Keyboard", icon: "keyboard", destination: .keyboard)
                sectionButton("Chat apps", icon: "bubble.left.and.bubble.right", destination: .codex)
                sectionButton("App", icon: "gearshape", destination: .app)
                sectionButton("Setup & diagnostics", icon: "wrench.and.screwdriver", destination: .setup)
                sectionButton("App logs", icon: "list.bullet.rectangle", destination: .logs)
            }
            Divider()
            if section == .keyboard {
                HStack {
                    Text("Profiles").font(.headline)
                    Spacer()
                    Button { model.addProfile(); keyboardPage = .profiles } label: { Image(systemName: "plus") }
                        .help("New profile").accessibilityLabel("New profile")
                }
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(model.configuration.profiles) { profile in
                            Button {
                                model.selectedProfileID = profile.id
                                if !model.configuration.autoSwitch { model.useSelectedProfile() }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(profile.name).fontWeight(.medium)
                                        Text(profile.applicationIDs.isEmpty ? "General profile" : "\(profile.applicationIDs.count) linked apps")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if model.activeProfile.id == profile.id {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint).accessibilityLabel("Active profile")
                                    }
                                }
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(model.selectedProfileID == profile.id ? Color.accentColor.opacity(0.13) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 10))
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Button("Manage profiles…") { keyboardPage = .profiles }
            } else {
                Text(section == .codex ? "Five chat keys and status lighting" : section == .logs ? "Recent events and errors" : section == .setup ? "Keyboard access and troubleshooting" : "Startup and installation")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Label(model.running ? "Mappings active" : model.preparing || model.waitingForAutomaticStart ? "Connecting…" : "Mappings off",
                      systemImage: model.running ? "checkmark.circle.fill" : "pause.circle")
                    .foregroundStyle(model.running ? .green : .secondary)
                Text(model.activeProfileName).font(.headline)
                Text(model.inputAccessMode == .macroButtons ? "Macro buttons only" : "Dial: \(model.dialName)").font(.caption)
            }
            Button(model.running || model.preparing || model.waitingForAutomaticStart ? "Stop mappings" : "Enable mappings") {
                if model.running || model.preparing || model.waitingForAutomaticStart { model.stop() } else { model.start() }
            }.buttonStyle(.borderedProminent).controlSize(.large)
            Text("Closing Settings keeps Ergo Control in the menu bar. Choose Quit there to exit.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(width: 250).background(.background.secondary)
    }

    private func sectionButton(_ title: String, icon: String, destination: Section) -> some View {
        Button { section = destination; focusedSection = destination } label: {
            Label(title, systemImage: icon).font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .background(section == destination ? Color.accentColor.opacity(0.13) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).focused($focusedSection, equals: destination)
    }
}

struct ActionEditor: View {
    @Binding var action: MappingAction
    var control: String? = nil
    var functionKeys = FunctionKeyPreferences()
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Action", selection: Binding(get: { action.kind }, set: { kind in
                let previousKind = action.kind
                action.kind = kind
                switch kind {
                case .shortcut: action.value = "cmd+c"
                case .macro: action.value = "cmd+c\nwait 200\ncmd+v"
                case .scroll: action.value = "down"
                case .media: action.value = "playPause"
                case .keyboardBrightness: action.value = "up"
                case .codexChat, .claudeChat: action.value = "1"
                case .application, .toggleApplication:
                    if previousKind != .application && previousKind != .toggleApplication { action.value = "" }
                default: action.value = ""
                }
            })) { ForEach(ActionKind.allCases) { kind in Text(kind.label).tag(kind) } }
            switch action.kind {
            case .shortcut:
                TextField("Example: cmd+shift+c", text: $action.value)
                Text("Use cmd, ctrl, option, shift and a key name.").font(.caption).foregroundStyle(.secondary)
            case .macro:
                TextEditor(text: $action.value).font(.system(.body, design: .monospaced)).frame(minHeight: 100)
                Text("One shortcut per line. “wait 200” pauses 200 ms. “text Hello” types text. One macro runs at a time.").font(.caption).foregroundStyle(.secondary)
            case .text:
                TextEditor(text: $action.value).frame(minHeight: 70)
            case .application, .toggleApplication, .script:
                HStack { Text(action.value.isEmpty ? (action.kind == .script ? "Choose a file" : "Choose an application") : URL(fileURLWithPath: action.value).lastPathComponent).lineLimit(1); Spacer(); Button("Choose…") { chooseFile() } }
                if action.kind == .script { Text("Runs the selected zsh script when this control is pressed. Stops after 10 seconds.").font(.caption).foregroundStyle(.secondary) }
                if action.kind == .toggleApplication { Text("Bring this app forward. Press again while it is active to minimize its window; press once more to restore it.").font(.caption).foregroundStyle(.secondary) }
            case .scroll:
                Picker("Direction", selection: $action.value) { ForEach(["up","down","left","right"], id: \.self) { Text($0.capitalized).tag($0) } }
            case .media:
                Picker("Media", selection: $action.value) {
                    Text("Play / pause").tag("playPause"); Text("Next track").tag("next"); Text("Previous track").tag("previous")
                    Text("Volume up").tag("volumeUp"); Text("Volume down").tag("volumeDown"); Text("Mute").tag("mute")
                    Text("Screen brightness up").tag("displayBrightnessUp"); Text("Screen brightness down").tag("displayBrightnessDown")
                }
            case .keyboardBrightness:
                Picker("Brightness", selection: $action.value) {
                    Text("Increase").tag("up"); Text("Decrease").tag("down")
                }
                Text("Adjust PT Ergo’s backlight in 5% steps.").font(.caption).foregroundStyle(.secondary)
            case .codexChat, .claudeChat:
                Picker("Chat slot", selection: $action.value) {
                    ForEach(1...5, id: \.self) { number in Text("M\(number) · Slot \(number)").tag(String(number)) }
                }
                Text("Opens this provider’s current slot. Enable its connection in Chat apps first.").font(.caption).foregroundStyle(.secondary)
            case .standard:
                if let control, control.hasPrefix("key:"), let usage = UInt8(control.dropFirst(4)),
                   let label = NativeFunctionKeys.label(for: usage, preferences: functionKeys) {
                    Text("Default: \(label). Choose Shortcut and enter \(ControlCatalog.label(control).lowercased()) to send the function key instead.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Use the normal action or current dial mode. With chat keys enabled, unmapped M1–M5 can open their current chat slots.").font(.caption).foregroundStyle(.secondary)
                }
            case .layer: Text("Other controls use this profile’s alternate layer while this button is held.").font(.caption).foregroundStyle(.secondary)
            case .cycleDial: Text("Switch to the next enabled command-dial mode.").font(.caption).foregroundStyle(.secondary)
            case .battery: Text("Show the current keyboard battery percentage in a brief on-screen popup.").font(.caption).foregroundStyle(.secondary)
            case .disabled: EmptyView()
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func chooseFile() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false
        if action.kind == .application || action.kind == .toggleApplication { panel.allowedContentTypes = [.applicationBundle] }
        if panel.runModal() == .OK, let url = panel.url { action.value = url.path }
    }
}

/// Keep the disclosure label and its empty row space inside the same button.
struct WholeRowDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                    configuration.label
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(configuration.isExpanded ? "Collapse section" : "Expand section")
            if configuration.isExpanded {
                configuration.content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 20)
            }
        }
    }
}
