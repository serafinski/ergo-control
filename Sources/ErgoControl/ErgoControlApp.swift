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
        if model.codex.settings.enabled {
            Divider()
            Text(model.codex.settings.selection.label)
            Text("\(model.codex.assignedSlotCount) of 5 chat keys assigned")
            ForEach(model.codex.displaySlots) { slot in
                let summary = slot.threadID == nil ? model.codex.emptySlotLabel : "\(slot.name) · \(model.codex.activity(slot).label)"
                Button("M\(slot.id) · \(summary)") { model.codex.openSlot(slot.id) }
                    .disabled(slot.url == nil)
            }
        }
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
    private enum Section: Hashable { case keyboard, codex, app, logs }
    @State private var section = Section.keyboard
    @FocusState private var focusedSection: Section?
    @State private var keyToAdd = "4"
    @State private var showAddKey = false
    @State private var testText = ""
    @State private var showDialModes = false
    private var index: Int { model.profileIndex }
    private var profile: Binding<MappingProfile> {
        let id = model.selectedProfileID
        return Binding(get: {
            model.configuration.profiles.first(where: { $0.id == id }) ?? model.configuration.profiles[0]
        }, set: { value in
            if let index = model.configuration.profiles.firstIndex(where: { $0.id == id }) { model.configuration.profiles[index] = value }
        })
    }
    private var mapping: Binding<MappingAction> {
        Binding(get: {
            let p = model.configuration.profiles[index]
            return (model.alternateEditing ? p.alternate : p.mappings)[model.selectedControl] ?? MappingAction()
        }, set: { value in
            if model.alternateEditing { model.configuration.profiles[index].alternate[model.selectedControl] = value }
            else { model.configuration.profiles[index].mappings[model.selectedControl] = value }
        })
    }
    private var controls: [(String, String)] {
        let p = model.configuration.profiles[index]
        let extra = Set(p.mappings.keys).union(p.alternate.keys).filter { $0.hasPrefix("key:") }.sorted()
        let first = ["extra:32", "extra:33", "extra:34", "extra:35", "extra:36", "extra:247"]
        let base = first.compactMap { id in ControlCatalog.controls.first { $0.0 == id } } + ControlCatalog.controls.filter { !first.contains($0.0) }
        return base + extra.map { ($0, ControlCatalog.label($0)) }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(nsImage: AppBranding.appIcon).resizable().frame(width: 32, height: 32).accessibilityHidden(true)
                    Text("Ergo Control").font(.title2.bold())
                }
                Text("PRO TYPE ERGO").font(.caption).foregroundStyle(.secondary)
                Divider()
                VStack(spacing: 6) {
                    sectionButton("Keyboard", icon: "keyboard", destination: .keyboard)
                    sectionButton("Codex", icon: "bubble.left.and.bubble.right", destination: .codex)
                    sectionButton("App", icon: "gearshape", destination: .app)
                    sectionButton("App logs", icon: "list.bullet.rectangle", destination: .logs)
                }
                Divider()
                if section == .keyboard {
                    HStack { Text("Profiles").font(.headline); Spacer(); Button { model.addProfile() } label: { Image(systemName: "plus") }.help("New profile") }
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(model.configuration.profiles) { p in
                                Button {
                                    model.selectedProfileID = p.id
                                    if !model.configuration.autoSwitch { model.useSelectedProfile() }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(p.name).fontWeight(.medium)
                                            Text(p.applicationIDs.isEmpty ? "General profile" : "\(p.applicationIDs.count) linked apps")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if model.activeProfileName == p.name { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(model.selectedProfileID == p.id ? Color.accentColor.opacity(0.13) : Color.clear,
                                                    in: RoundedRectangle(cornerRadius: 10))
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    Toggle("Switch profiles with apps", isOn: $model.configuration.autoSwitch)
                    Button("Use selected as default") { model.useSelectedProfile() }
                    HStack {
                        Button("Duplicate") { model.duplicateProfile() }
                        Button("Remove") { model.removeProfile() }.disabled(model.configuration.profiles.count == 1)
                    }
                } else {
                    Text(section == .codex ? "Five chat keys and status lighting" : section == .logs ? "Recent events and errors" : "Startup and installation").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Label(model.running ? "Active" : "Off", systemImage: model.running ? "checkmark.circle.fill" : "pause.circle")
                        .foregroundStyle(model.running ? .green : .secondary)
                    Text(model.activeProfileName).font(.headline)
                    Text(model.inputAccessMode == .macroButtons ? "Macro buttons only" : "Dial: \(model.dialName)").font(.caption)
                }
                Button(model.running || model.preparing || model.waitingForAutomaticStart ? "Stop mappings" : "Enable mappings") {
                    if model.running || model.preparing || model.waitingForAutomaticStart { model.stop() } else { model.start() }
                }.buttonStyle(.borderedProminent).controlSize(.large)
                Text("Closing this window keeps the menu-bar app available. Quit restores the keyboard’s saved mode.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(22).frame(width: 250).background(.background.secondary)
            Divider()
            if section == .logs {
                ScrollView {
                    AppLogView(log: model.logs).frame(maxWidth: 1000).frame(maxWidth: .infinity).padding(28)
                }
            } else if section == .app {
                ScrollView {
                    AppSettingsView(startup: model.startup).frame(maxWidth: 800).frame(maxWidth: .infinity).padding(28)
                }
            } else if section == .codex {
                ScrollView {
                    CodexSettingsView(model: model).frame(maxWidth: 900).frame(maxWidth: .infinity).padding(28)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Profile name").font(.caption).foregroundStyle(.secondary)
                                TextField("Profile name", text: profile.name)
                                    .textFieldStyle(.roundedBorder).font(.title.bold())
                                    .frame(maxWidth: 380)
                                    .accessibilityLabel("Profile name")
                                    .help("Rename this profile, then choose Save changes.")
                                Text("Make the keyboard work the way you do.").foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(model.dirty ? "Unsaved changes" : "Saved").font(.caption).foregroundStyle(.secondary)
                            Button("Save changes") { model.save() }.keyboardShortcut("s")
                        }
                        GroupBox {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(model.status).font(.callout)
                                if model.inputAccessMode == .macroButtons {
                                    Text("Custom dial modes, media-button replacement, ordinary-key remaps need full keyboard control. macOS denied that access. The left dial uses horizontal scrolling while driver mode is active.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                if !model.bluetooth.lightingStatus.isEmpty {
                                    Text(model.bluetooth.lightingStatus).font(.caption).foregroundStyle(.secondary)
                                }
                                if let error = model.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                                HStack {
                                    permission("Input Monitoring", granted: model.inputGranted, url: "Privacy_ListenEvent")
                                    permission("Accessibility", granted: model.accessibilityGranted, url: "Privacy_Accessibility")
                                    Button("60-second test") { model.start(testSeconds: 60) }.disabled(model.running || model.preparing)
                                    Spacer()
                                    Text(model.bluetooth.batteryText).font(.callout)
                                }
                                if model.preparing || model.running || model.bluetooth.restoreOwed { Text(model.bluetooth.status).font(.caption).foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                        }
                        KeyboardLightingView(model: model)
                        FunctionKeySettingsView(model: model)
                        GroupBox("Try your mappings") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Click below to test ordinary typing, shortcuts, and macros. This text is not saved.")
                                    .font(.caption).foregroundStyle(.secondary)
                                TextEditor(text: $testText).frame(minHeight: 90)
                                Button("Clear test text") { testText = "" }
                            }.padding(8)
                        }
                        GroupBox("Full dial control") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(model.fullControlHelper.status).font(.callout)
                                Text("The optional input helper gives Ergo Control exclusive access to PT Ergo so dial actions can be replaced. Installation requires administrator approval. The helper releases the keyboard when mappings stop or the app stops responding.")
                                    .font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    if model.fullControlHelper.needsStartupRepair {
                                        Button("Repair helper startup…") { model.enableFullControl() }
                                    } else if model.fullControlHelper.enabled || model.fullControlHelper.needsApproval {
                                        if model.fullControlHelper.needsApproval {
                                            Button("Open approval settings") { model.fullControlHelper.showApproval() }
                                        }
                                        Button("Remove input helper") { model.removeFullControl() }
                                    } else {
                                        Button(model.fullControlHelper.usesLocalCertificate ? "Install input helper…" : "Enable full dial control…") { model.enableFullControl() }
                                    }
                                    Button("Refresh status") { model.fullControlHelper.refresh() }
                                    Button("Check helper permission") { model.fullControlHelper.checkPermission() }
                                        .disabled(!model.fullControlHelper.enabled || model.fullControlHelper.checkingPermission || model.running || model.preparing)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        }
                        DisclosureGroup("Link this profile to applications") {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    if model.configuration.profiles[index].applicationIDs.isEmpty { Text("Used when no linked application is active").foregroundStyle(.secondary) }
                                    ForEach(model.configuration.profiles[index].applicationIDs, id: \.self) { id in
                                        HStack {
                                            Text(id).textSelection(.enabled)
                                            Button { model.configuration.profiles[index].applicationIDs.removeAll { $0 == id } } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain)
                                        }
                                    }
                                }
                                Spacer(); Button("Link application…") { model.addApplication() }
                            }.padding(8)
                        }
                        HStack {
                            Text("Button mappings").font(.title2.bold())
                            Spacer()
                            Picker("Layer", selection: $model.alternateEditing) { Text("Standard").tag(false); Text("Alternate layer").tag(true) }
                                .pickerStyle(.segmented).frame(width: 260)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 10)], spacing: 10) {
                            ForEach(controls, id: \.0) { control in
                                Button { model.selectedControl = control.0 } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(control.1).fontWeight(.medium).lineLimit(2)
                                        let p = model.configuration.profiles[index]
                                        let action = (model.alternateEditing ? p.alternate : p.mappings)[control.0]
                                        Text(action?.kind.label ?? (model.alternateEditing ? "Use standard layer" : "Default"))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, minHeight: 55, alignment: .leading).padding(12)
                                        .background(model.selectedControl == control.0 ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.07),
                                                    in: RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain)
                                    .disabled(model.inputAccessMode == .macroButtons && !InputAccessMode.macroButtons.supports(control: control.0))
                            }
                        }
                        HStack {
                            Button("Add ordinary key…") { showAddKey = true }.popover(isPresented: $showAddKey) {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text("Choose a keyboard key").font(.headline)
                                    Picker("Key", selection: $keyToAdd) {
                                        ForEach(KeyChord.names.keys.sorted(), id: \.self) { name in Text(name.uppercased()).tag(String(KeyChord.names[name]!)) }
                                    }
                                    Button("Add mapping") {
                                        let id = "key:\(keyToAdd)"
                                        model.configuration.profiles[index].mappings[id] = MappingAction()
                                        model.selectedControl = id; showAddKey = false
                                    }
                                }.padding(20).frame(width: 300)
                            }
                            Spacer()
                            Text("Last input: \(model.lastControl)").font(.caption).foregroundStyle(.secondary)
                        }
                        DisclosureGroup("Command dial modes", isExpanded: $showDialModes) {
                            VStack(alignment: .leading, spacing: 14) {
                        HStack { Spacer(); Button("Add mode") {
                            model.configuration.profiles[index].dialModes.append(DialMode(name: "Custom mode", clockwise: MappingAction(.shortcut, "cmd+equal"), counterclockwise: MappingAction(.shortcut, "cmd+minus")))
                        } }
                        Text("Click the left dial to cycle enabled modes. The current mode appears briefly on screen.").foregroundStyle(.secondary)
                        ForEach(model.configuration.profiles[index].dialModes) { mode in
                            let modeBinding = dialBinding(mode)
                            GroupBox {
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack {
                                        Toggle("", isOn: modeBinding.enabled).labelsHidden().toggleStyle(.switch)
                                        TextField("Mode name", text: modeBinding.name).font(.headline)
                                        Button { model.configuration.profiles[index].dialModes.removeAll { $0.id == mode.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                                    }
                                    HStack(alignment: .top, spacing: 20) {
                                        VStack(alignment: .leading) { Text("Clockwise").font(.caption); ActionEditor(action: modeBinding.clockwise) }
                                        VStack(alignment: .leading) { Text("Counterclockwise").font(.caption); ActionEditor(action: modeBinding.counterclockwise) }
                                    }
                                }.padding(8)
                            }
                        }
                            }
                        }.disabled(model.inputAccessMode == .macroButtons)
                        Text("Only PT Ergo is handled while mappings are enabled. Profiles are stored on this Mac. No account or cloud service is required.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(28)
                }
                Divider()
                VStack(alignment: .leading, spacing: 18) {
                    Text("Selected control").font(.caption).foregroundStyle(.secondary)
                    Text(ControlCatalog.label(model.selectedControl)).font(.title.bold())
                    Text(model.alternateEditing ? "Alternate layer" : "Standard layer").foregroundStyle(.secondary)
                    Divider()
                    ActionEditor(action: mapping, control: model.selectedControl, functionKeys: model.configuration.functionKeys)
                        .disabled(model.inputAccessMode == .macroButtons && !InputAccessMode.macroButtons.supports(control: model.selectedControl))
                    if model.alternateEditing {
                        Text("Assign Hold alternate layer to a button in the standard layer first.").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Save this mapping") { model.save() }.buttonStyle(.borderedProminent)
                    Text("Choose a button in the middle, set its action here, then save. Start with M1 and Type text to try a simple mapping.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Text(model.dirty ? "Unsaved changes" : "Settings saved locally").font(.caption).foregroundStyle(.secondary)
                }.padding(22).frame(width: 300).background(.background.secondary)
            }
        }.frame(minWidth: 1180, minHeight: 760)
            .disclosureGroupStyle(WholeRowDisclosureStyle())
    }

    private func sectionButton(_ title: String, icon: String, destination: Section) -> some View {
        Button {
            section = destination
            focusedSection = destination
        } label: {
            Label(title, systemImage: icon).font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .background(section == destination ? Color.accentColor.opacity(0.13) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .focused($focusedSection, equals: destination)
    }

    private func dialBinding(_ original: DialMode) -> Binding<DialMode> {
        let parent = profile
        return Binding(get: {
            parent.wrappedValue.dialModes.first(where: { $0.id == original.id }) ?? original
        }, set: { value in
            var copy = parent.wrappedValue
            if let index = copy.dialModes.firstIndex(where: { $0.id == original.id }) {
                copy.dialModes[index] = value; parent.wrappedValue = copy
            }
        })
    }

    private func permission(_ label: String, granted: Bool, url: String) -> some View {
        Button {
            if !granted {
                if url == "Privacy_ListenEvent" { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
                if url == "Privacy_Accessibility" {
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(options)
                }
            }
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(url)")!)
        } label: { Label(label + (granted ? " · Ready" : " · Required"), systemImage: granted ? "checkmark.circle.fill" : "circle") }
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
                case .codexChat: action.value = "1"
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
            case .codexChat:
                Picker("Chat slot", selection: $action.value) {
                    ForEach(1...5, id: \.self) { number in Text("M\(number) · Slot \(number)").tag(String(number)) }
                }
                Text("Opens the current Codex slot. Enable the connection in the Codex section first.").font(.caption).foregroundStyle(.secondary)
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
private struct WholeRowDisclosureStyle: DisclosureGroupStyle {
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
