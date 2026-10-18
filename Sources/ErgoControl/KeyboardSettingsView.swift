import SwiftUI
import AppKit
import ErgoCore

enum KeyboardSettingsPage: String, CaseIterable, Identifiable {
    case buttons = "Buttons", dials = "Dials", lighting = "Lighting & power", functionKeys = "Function keys", profiles = "Profiles"
    var id: String { rawValue }
}

struct KeyboardSettingsView: View {
    @ObservedObject var model: ControlModel
    @Binding var page: KeyboardSettingsPage
    var openSetup: () -> Void
    @State private var showEditor = false
    @State private var draft = MappingAction()
    @State private var editorError: String?
    @State private var testText = ""
    @State private var keyToAdd = "4"
    @State private var showAddKey = false
    @State private var expandedMode: UUID?
    @State private var confirmRemoveProfile = false

    private var profile: Binding<MappingProfile> {
        let id = model.selectedProfileID
        return Binding(get: {
            model.configuration.profiles.first { $0.id == id } ?? model.configuration.profiles[0]
        }, set: { value in
            if let index = model.configuration.profiles.firstIndex(where: { $0.id == id }) {
                model.configuration.profiles[index] = value
            }
        })
    }
    private var mappings: [String: MappingAction] {
        model.alternateEditing ? profile.wrappedValue.alternate : profile.wrappedValue.mappings
    }
    private var extraKeys: [String] {
        Set(profile.wrappedValue.mappings.keys).union(profile.wrappedValue.alternate.keys)
            .filter { $0.hasPrefix("key:") }.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Picker("Keyboard settings", selection: $page) {
                ForEach(KeyboardSettingsPage.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            notices
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch page {
                    case .buttons: buttons
                    case .dials: dials
                    case .lighting: KeyboardLightingView(model: model)
                    case .functionKeys: functionKeys
                    case .profiles: profiles
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }.id(page)
        }
        .padding(28)
        .sheet(isPresented: $showEditor) { mappingEditor }
        .confirmationDialog("Remove “\(profile.wrappedValue.name)” and its mappings?", isPresented: $confirmRemoveProfile) {
            Button("Remove profile", role: .destructive) { model.removeProfile() }
        } message: { Text("Other profiles are kept. Use Save changes to keep this removal.") }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Keyboard").font(.largeTitle.bold())
                Text(page == .lighting || page == .functionKeys ? "These settings apply to every profile." : "Editing profile: \(profile.wrappedValue.name)")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                Text(model.bluetooth.batteryText).font(.callout).foregroundStyle(.secondary)
                if page != .lighting || model.dirty {
                HStack {
                    Text(model.dirty ? "Unsaved changes" : "Saved").font(.caption).foregroundStyle(.secondary)
                    Button("Save changes") { model.save() }.keyboardShortcut("s")
                        .buttonStyle(.borderedProminent).disabled(!model.dirty)
                }
                }
            }
        }
    }

    @ViewBuilder private var notices: some View {
        if let error = model.error {
            HStack(alignment: .top) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(error).textSelection(.enabled)
                Spacer()
                Button("Setup & diagnostics…", action: openSetup)
            }.font(.callout).padding(12).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        } else if !model.inputGranted || !model.accessibilityGranted || model.inputAccessMode == .macroButtons {
            HStack {
                Label("Some controls need keyboard access.", systemImage: "exclamationmark.circle")
                Spacer()
                Button("Set up keyboard…", action: openSetup)
            }.font(.callout)
        } else if model.preparing || model.waitingForAutomaticStart {
            Text(model.status).font(.callout).foregroundStyle(.secondary)
        }
    }

    private var buttons: some View {
        VStack(alignment: .leading, spacing: 22) {
            layerPicker
            Text("Choose a button to change what it does.").foregroundStyle(.secondary)
            controlGroup("Macro keys and AI", ids: ["extra:32", "extra:33", "extra:34", "extra:35", "extra:36", "extra:247"])
            controlGroup("Media and battery", ids: ["mediaSingle", "mediaDouble", "mediaTriple", "extra:65"])
            Picker("Music app when nothing can resume", selection: $model.musicFallbackApplication) {
                ForEach(MusicFallbackApplication.allCases) { app in Text(app.label).tag(app) }
            }
            Text("Play / pause opens this app when nothing can resume. If it is already open, its own playback control is used when needed. Existing playback keeps normal media controls. Opening does not choose a track. This choice saves immediately.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Try Play / pause", action: model.tryPlayPause).disabled(!model.running)
            if let notice = model.musicFallbackNotice { Text(notice).font(.caption).foregroundStyle(.orange) }
            Text(model.focusedMediaPlayback ? "Experimental playback routing prefers the focused window’s accessible player, then the last media window. Volume and mute control system audio." : "Playback uses macOS media routing. Volume and mute control system audio.")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Other keys") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Split keys and any other keys you remap.").font(.callout).foregroundStyle(.secondary)
                    controlGrid(["extra:253", "extra:252", "extra:251"] + extraKeys)
                    addKeyButton
                }.padding(.top, 8)
            }
            testPad
        }
    }

    private var layerPicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            Picker("Layer", selection: $model.alternateEditing) {
                Text("Standard").tag(false); Text("Alternate").tag(true)
            }.pickerStyle(.segmented).frame(maxWidth: 300)
            if model.alternateEditing {
                Text("Assign “Hold alternate layer” to a button in Standard first. Other controls use these actions while that button is held.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var dials: some View {
        VStack(alignment: .leading, spacing: 22) {
            layerPicker
            controlGroup("Left command dial", ids: ["leftCW", "leftCCW", "extra:96"])
            Text("With Default actions, clicking the left dial cycles the enabled modes below. Turning it uses that mode. A custom dial mapping overrides the mode.")
                .font(.callout).foregroundStyle(.secondary)
            GroupBox("Left dial modes") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(profile.wrappedValue.dialModes) { mode in modeRow(mode) }
                    Button("Add mode") {
                        let mode = DialMode(name: "Custom mode", clockwise: MappingAction(.shortcut, "cmd+equal"),
                                            counterclockwise: MappingAction(.shortcut, "cmd+minus"))
                        var value = profile.wrappedValue; value.dialModes.append(mode); profile.wrappedValue = value
                        expandedMode = mode.id
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }.disabled(model.inputAccessMode == .macroButtons)
            controlGroup("Right roller", ids: ["rightCW", "rightCCW", "rightClick"])
            Text("The right roller controls volume and mute by default.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func modeRow(_ mode: DialMode) -> some View {
        let binding = dialBinding(mode)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Toggle("Enable \(mode.name)", isOn: binding.enabled).labelsHidden().toggleStyle(.switch)
                Button { expandedMode = expandedMode == mode.id ? nil : mode.id } label: {
                    HStack {
                        Text(mode.name).fontWeight(.medium)
                        Spacer()
                        Image(systemName: expandedMode == mode.id ? "chevron.up" : "chevron.down")
                    }.padding(.vertical, 8).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityValue(expandedMode == mode.id ? "Expanded" : "Collapsed")
                Button {
                    var value = profile.wrappedValue; value.dialModes.removeAll { $0.id == mode.id }; profile.wrappedValue = value
                } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("Remove \(mode.name)").accessibilityLabel("Remove \(mode.name)")
            }
            if expandedMode == mode.id {
                TextField("Mode name", text: binding.name).textFieldStyle(.roundedBorder)
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Clockwise").font(.headline)
                        ActionEditor(action: binding.clockwise)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Counterclockwise").font(.headline)
                        ActionEditor(action: binding.counterclockwise)
                    }
                }.padding(.bottom, 8)
            }
            Divider()
        }
    }

    private var functionKeys: some View {
        VStack(alignment: .leading, spacing: 20) {
            FunctionKeySettingsView(model: model)
            DisclosureGroup("All function keys and custom actions") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Choose a key to override its standard action in this profile.").foregroundStyle(.secondary)
                    layerPicker
                    controlGrid((1...12).compactMap { KeyChord.names["f\($0)"].map { "key:\($0)" } })
                }.padding(.top, 8)
            }
        }
    }

    private var profiles: some View {
        VStack(alignment: .leading, spacing: 22) {
            GroupBox("Selected profile") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Profile name").font(.caption).foregroundStyle(.secondary)
                    TextField("Profile name", text: profile.name)
                        .textFieldStyle(.plain).font(.title2.bold())
                        .padding(10).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.4)))
                        .accessibilityLabel("Profile name")
                    HStack {
                        Button("Duplicate profile") { model.duplicateProfile() }
                        Spacer()
                        Button("Remove profile", role: .destructive) { confirmRemoveProfile = true }
                            .disabled(model.configuration.profiles.count == 1)
                    }
                }.padding(8)
            }
            GroupBox("Profile switching") {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Switch profiles automatically with apps", isOn: $model.configuration.autoSwitch)
                    Text("Linked apps use their profile when they are in front. Your default profile is used for everything else.")
                        .font(.callout).foregroundStyle(.secondary)
                    let defaultName = model.configuration.profiles.first { $0.id == model.configuration.manualProfileID }?.name ?? "Default"
                    HStack {
                        Text("Default profile: \(defaultName)")
                        Spacer()
                        Button("Use this profile as default") { model.useSelectedProfile() }
                            .disabled(model.configuration.manualProfileID == model.selectedProfileID)
                    }
                }.padding(8)
            }
            GroupBox("Apps linked to this profile") {
                VStack(alignment: .leading, spacing: 14) {
                    if profile.wrappedValue.applicationIDs.isEmpty {
                        Text("No linked apps. Add an app to use this profile automatically when it is active.").foregroundStyle(.secondary)
                    }
                    ForEach(profile.wrappedValue.applicationIDs, id: \.self) { id in
                        HStack {
                            Text(appName(id)).textSelection(.enabled)
                            Spacer()
                            Button("Unlink") {
                                var value = profile.wrappedValue; value.applicationIDs.removeAll { $0 == id }; profile.wrappedValue = value
                            }
                        }
                    }
                    Button("Link application…") { model.addApplication() }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
        }
    }

    private func appName(_ id: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.deletingPathExtension().lastPathComponent ?? id
    }

    private func controlGroup(_ title: String, ids: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.bold())
            controlGrid(ids)
        }
    }
    private func controlGrid(_ ids: [String]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 150), spacing: 12), count: ids.count == 4 ? 2 : 3), spacing: 12) {
            ForEach(ids, id: \.self) { id in
                Button { edit(id) } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(ControlCatalog.label(id)).fontWeight(.semibold)
                            Spacer(minLength: 6)
                            Image(systemName: "pencil").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(summary(id)).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading).padding(14)
                    .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .help("Edit \(ControlCatalog.label(id))")
                    .disabled(model.inputAccessMode == .macroButtons && !InputAccessMode.macroButtons.supports(control: id))
            }
        }
    }
    private func summary(_ id: String) -> String {
        let action = mappings[id] ?? MappingAction()
        if action.kind != .standard {
            switch action.kind {
            case .shortcut: return action.value
            case .text: return action.value.isEmpty ? "Type text" : "“\(action.value.replacingOccurrences(of: "\n", with: " ").prefix(36))”"
            case .application, .toggleApplication, .script:
                return action.value.isEmpty ? action.kind.label : "\(action.kind.label) · \(URL(fileURLWithPath: action.value).deletingPathExtension().lastPathComponent)"
            case .claudeChat: return "Claude Code chat · slot \(action.value)"
            case .codexChat: return "Codex chat · slot \(action.value)"
            default: return action.kind.label
            }
        }
        if model.alternateEditing { return "Use standard layer" }
        if let usage = UInt8(id.hasPrefix("key:") ? String(id.dropFirst(4)) : ""),
           let label = NativeFunctionKeys.label(for: usage, preferences: model.configuration.functionKeys) { return label }
        if let number = Int(id.replacingOccurrences(of: "extra:", with: "")), (32...36).contains(number),
           model.chat.settings.enabled, model.chat.settings.useUnmappedMacroKeys { return "\(model.chat.provider.name) chat · slot \(number - 31)" }
        switch id {
        case "leftCW", "leftCCW": return "Use current dial mode"
        case "extra:96": return "Next dial mode"
        case "rightCW": return "Volume up"
        case "rightCCW": return "Volume down"
        case "rightClick": return "Mute / unmute"
        case "mediaSingle": return "Play / pause"
        case "mediaDouble": return "Next track"
        case "mediaTriple": return "Previous track"
        case "extra:65": return "Show battery"
        case "extra:253": return "Space"
        case "extra:252": return "B"
        case "extra:251": return "Backspace"
        default: return "Keyboard default"
        }
    }

    private var addKeyButton: some View {
        Button("Remap another key…") { showAddKey = true }
            .popover(isPresented: $showAddKey) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Choose a key").font(.headline)
                    Picker("Key", selection: $keyToAdd) {
                        ForEach(KeyChord.names.keys.sorted(), id: \.self) { name in
                            Text(name.uppercased()).tag(String(KeyChord.names[name]!))
                        }
                    }
                    Button("Edit action") { showAddKey = false; edit("key:\(keyToAdd)") }
                }.padding(20).frame(width: 320)
            }
    }
    private var testPad: some View {
        DisclosureGroup("Try your mappings") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Enable mappings, click in the box, then press a mapped button. Test text is not saved.")
                    .font(.callout).foregroundStyle(.secondary)
                TextEditor(text: $testText).frame(minHeight: 150)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                Button("Clear test text") { testText = "" }
            }.padding(.top, 8)
        }
    }
    private func edit(_ id: String) {
        model.selectedControl = id
        draft = mappings[id] ?? MappingAction()
        editorError = nil
        showEditor = true
    }
    private var mappingEditor: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(ControlCatalog.label(model.selectedControl)).font(.title.bold())
            Text("\(profile.wrappedValue.name) · \(model.alternateEditing ? "Alternate" : "Standard") layer").foregroundStyle(.secondary)
            ScrollView {
                ActionEditor(action: $draft, control: model.selectedControl, functionKeys: model.configuration.functionKeys)
                    .padding(.vertical, 4)
            }.frame(minHeight: 200, maxHeight: 440)
            if let error = editorError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Use default") { draft = MappingAction() }
                Spacer()
                Button("Cancel") { showEditor = false }.keyboardShortcut(.cancelAction)
                Button("Save mapping", action: saveDraft)
                    .buttonStyle(.borderedProminent).keyboardShortcut("s")
            }
        }.padding(24).frame(width: 560)
    }
    private func saveDraft() {
        let previous = profile.wrappedValue
        let wasDirty = model.dirty
        let previousError = model.error
        var value = previous
        if model.alternateEditing { value.alternate[model.selectedControl] = draft }
        else { value.mappings[model.selectedControl] = draft }
        profile.wrappedValue = value
        model.save()
        if let error = model.error {
            editorError = error
            profile.wrappedValue = previous
            model.dirty = wasDirty
            model.error = previousError
        } else { showEditor = false }
    }
    private func dialBinding(_ mode: DialMode) -> Binding<DialMode> {
        let parent = profile
        return Binding(get: {
            parent.wrappedValue.dialModes.first { $0.id == mode.id } ?? mode
        }, set: { value in
            var copy = parent.wrappedValue
            if let index = copy.dialModes.firstIndex(where: { $0.id == mode.id }) { copy.dialModes[index] = value }
            parent.wrappedValue = copy
        })
    }
}
