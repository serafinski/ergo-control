import SwiftUI
import AppKit
import ErgoCore

struct ChatSettingsView: View {
    @ObservedObject var model: ControlModel
    let onEditMappings: (Bool) -> Void
    @State private var viewedProvider: ChatProvider
    @State private var alternateLayer: Bool
    init(model: ControlModel, onEditMappings: @escaping (Bool) -> Void = { _ in }) {
        self.model = model; self.onEditMappings = onEditMappings
        _viewedProvider = State(initialValue: model.chatPreferences.provider)
        _alternateLayer = State(initialValue: model.layerActive)
    }
    private var bridge: ChatBridge { model.chatBridge(for: viewedProvider) }
    private var assignments: [MacroKeyAssignment] { model.macroAssignments(alternateLayer: alternateLayer) }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Chat apps").font(.largeTitle.bold())
            Picker("App settings", selection: $viewedProvider) {
                ForEach(ChatProvider.allCases) { provider in Text(provider.name).tag(provider) }
            }.pickerStyle(.segmented)
            Text("View either app here. Switching pages keeps your key assignments and lighting source unchanged.")
                .font(.caption).foregroundStyle(.secondary)
            automaticDefaults
            if let error = model.chatPreferences.error { Text(error).foregroundStyle(.red) }
            Toggle("Connect to \(bridge.provider.name)", isOn: Binding(get: { bridge.settings.enabled }, set: bridge.setEnabled))
                .toggleStyle(.switch)
            Text("Optional. Keyboard mappings work with the chat app closed.")
                .font(.caption).foregroundStyle(.secondary)
            if !model.running { Text(model.status).font(.callout).foregroundStyle(.secondary) }
            if let error = model.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            macroAssignments
            if bridge.settings.enabled {
                chatKeys
                statusLights
                DisclosureGroup("Setup and advanced options") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(bridge.provider == .codex ? "Status hooks report activity from Codex chats in the desktop app. Review and trust ErgoCodexHook if asked; already-approved hooks need no reinstall." : "Install hooks, then start a new local Claude Code session. Cloud and SSH sessions are not included. Existing hooks and permission rules are preserved.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Install status hooks") { bridge.installHooks() }
                            Button("Review hooks file") { NSWorkspace.shared.open(bridge.hooksURL) }
                            Button("Remove status hooks") { bridge.installHooks(remove: true) }
                        }
                        Button("Create \(bridge.provider.name) mappings profile") { model.createChatProfile(bridge.provider) }
                        Text("Optional: create a separate profile with five explicit chat-slot actions. Existing profiles are preserved.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 10)
                }
            }
            Text(bridge.message).font(.callout).textSelection(.enabled)
            if bridge.provider == .claude { claudeCatalog }
        }.id(bridge.provider)
    }
    private var automaticDefaults: some View {
        GroupBox("Automatic keys and status lights") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Follow", selection: Binding(get: { model.chatPreferences.provider }, set: model.setChatProvider)) {
                    ForEach(ChatProvider.allCases) { provider in Text(provider.name).tag(provider) }
                }
                Toggle("Use unmapped M1–M5 for \(model.chat.provider.name) chats", isOn: Binding(
                    get: { model.chat.settings.useUnmappedMacroKeys }, set: { model.chat.setUseUnmappedMacroKeys($0) }))
                Text("Only keys set to Default follow this choice. Explicit mappings can open either app and take precedence.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(10)
        }
    }
    private var macroAssignments: some View {
        GroupBox("Macro keys for \(bridge.provider.name)") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Active profile: \(model.activeProfile.name)").font(.headline)
                    Spacer()
                    Button("Edit mappings") { onEditMappings(alternateLayer) }
                }
                Picker("Layer shown", selection: $alternateLayer) {
                    Text("Standard").tag(false); Text("Alternate").tag(true)
                }.pickerStyle(.segmented)
                Text("Showing \(alternateLayer ? "Alternate" : "Standard") assignments · current keyboard layer: \(model.layerActive ? "Alternate" : "Standard").")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(assignments) { assignment in
                    HStack(alignment: .top, spacing: 12) {
                        Text("M\(assignment.id)").bold().frame(width: 32, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            if assignment.provider == bridge.provider {
                                Text(destination(assignment))
                                Text(assignment.mapping.origin == .standardLayer && alternateLayer
                                     ? "Standard mapping (inherited)" : assignment.mapping.origin.label)
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("Unassigned to \(bridge.provider.name)").foregroundStyle(.secondary)
                                Text("Current: \(destination(assignment))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if assignment.provider == bridge.provider, let slot = assignedChat(assignment) {
                            Text(!bridge.settings.enabled ? "Connection off" : slot.threadID == nil ? "No chat in slot" : bridge.activity(slot).label)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Text("\(assignments.filter { $0.provider == bridge.provider }.count) of 5 macro keys assigned to \(bridge.provider.name) in this layer.")
                    .font(.caption).foregroundStyle(.secondary)
                if !model.running { Text("Mappings are off. These assignments apply when mappings are enabled.").font(.caption).foregroundStyle(.secondary) }
                if model.dirty { Text("Mapping changes have not been saved yet.").font(.caption).foregroundStyle(.secondary) }
            }.padding(10)
        }
    }
    private func assignedChat(_ assignment: MacroKeyAssignment) -> CodexSlot? {
        guard let provider = assignment.provider, let slot = assignment.slot else { return nil }
        return model.chatBridge(for: provider).displaySlots.first { $0.id == slot }
    }
    private func destination(_ assignment: MacroKeyAssignment) -> String {
        if let provider = assignment.provider, let number = assignment.slot {
            let slot = assignedChat(assignment)
            let name = slot.flatMap { $0.threadID == nil ? nil : $0.name } ?? "No chat in slot"
            return "\(provider.name) · Slot \(number) · \(name)"
        }
        switch assignment.mapping.action.kind {
        case .standard: return "Keyboard default"
        case .codexChat: return "Codex · invalid chat slot"
        case .claudeChat: return "Claude Code · invalid chat slot"
        default: return assignment.mapping.action.kind.label
        }
    }
    private func macroKeys(for slot: CodexSlot) -> String {
        let keys = assignments.filter { $0.provider == bridge.provider && $0.slot == slot.id }.map { "M\($0.id)" }
        return keys.isEmpty ? "No macro key assigned" : "Macro keys: " + keys.joined(separator: ", ")
    }
    private var chatKeys: some View {
        GroupBox("Available \(bridge.provider.name) chat slots") {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Chat selection", selection: Binding(get: { bridge.settings.selection }, set: bridge.setSelection)) {
                    ForEach(CodexSelectionMode.allCases) { mode in
                        Text(mode == .recent ? "Most recent chats" : mode == .pinned ? (bridge.provider == .claude ? "Starred chats · newest first" : "Pinned chats") : "Fixed assignments").tag(mode)
                    }
                }
                Text("Chat slots are destinations for key mappings. The macro-key assignments above show which keys actually open them.")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                ForEach(bridge.displaySlots) { slot in
                    if bridge.settings.selection == .fixed {
                        ChatSlotEditor(slot: slot, provider: bridge.provider, activity: bridge.activity(slot)) { name, link in
                            bridge.assign(slot.id - 1, name: name, link: link)
                        } open: { bridge.openSlot(slot.id) }
                        if bridge.provider == .claude, !bridge.catalogSlots.isEmpty {
                            Menu("Choose saved chat for Slot \(slot.id)") {
                                ForEach(bridge.catalogSlots) { saved in
                                    Button(saved.name) { bridge.assign(slot.id - 1, name: saved.name, link: saved.threadID ?? "") }
                                }
                            }
                        }
                    } else {
                        HStack {
                            Text("Slot \(slot.id)").bold().frame(width: 50, alignment: .leading)
                            Text(slot.threadID == nil ? bridge.emptySlotLabel : slot.name).lineLimit(1)
                            Spacer()
                            Text(slot.threadID == nil ? "No chat" : bridge.activity(slot).label).font(.caption).foregroundStyle(.secondary)
                            Button("Open chat") { bridge.openSlot(slot.id) }.disabled(bridge.url(for: slot) == nil)
                        }
                    }
                    Text(macroKeys(for: slot)).font(.caption).foregroundStyle(.secondary)
                }
                if bridge.needsCatalog {
                    HStack {
                        Text(bridge.historyMessage.isEmpty ? "Reading \(bridge.provider.name) chats…" : bridge.historyMessage).font(.caption)
                        Spacer()
                        Button("Refresh chats") { bridge.refreshHistory() }
                    }
                }
                Text("\(bridge.availableSlotCount) of 5 chat slots have a chat · local \(bridge.provider.name) chats only.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(10)
        }
    }
    private var statusLights: some View {
        GroupBox("Status lights") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Show \(bridge.provider.name) status lights", isOn: Binding(get: { bridge.settings.lighting }, set: bridge.setLighting))
                Text("Keyboard lights currently follow \(model.chatPreferences.provider.name). Choose the lighting source under Automatic keys and status lights above.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Signal style", selection: Binding(get: { bridge.settings.lightingArea }, set: bridge.setLightingArea)) {
                    ForEach(CodexLightingArea.allCases) { area in Text(area.label).tag(area) }
                }
                if bridge.settings.lightingArea == .completionWave {
                    Picker("Wave speed", selection: Binding(get: { bridge.settings.waveSpeed }, set: bridge.setWaveSpeed)) {
                        ForEach(CodexWaveSpeed.allCases) { speed in Text(speed.label).tag(speed) }
                    }.pickerStyle(.segmented)
                    Text("Quick makes shorter sweeps with wider steps. Smooth uses more steps.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if bridge.settings.lightingArea != .wholeKeyboard {
                    Toggle("Keep other keys dark during status lights", isOn: Binding(get: { bridge.settings.darkStatusBackground }, set: bridge.setDarkStatusBackground))
                    Text("Saves lighting power while keeping chat signals and animations active, including while you’re away.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Pulse macro keys while working", isOn: Binding(get: { bridge.settings.pulseWhileWorking }, set: bridge.setPulseWhileWorking))
                    Text("Fades your working color through dim to dark and back after the starting wave. Off keeps a solid color.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Colors for \(bridge.provider.name)").font(.headline)
                    ForEach([CodexActivity.working, .attention, .finished], id: \.rawValue) { activity in
                        ColorPicker(activity.label, selection: statusColorBinding(activity), supportsOpacity: false)
                            .frame(maxWidth: 340)
                    }
                    Button("Reset \(bridge.provider.name) colors") { bridge.resetStatusColors() }
                        .disabled(bridge.settings.statusColors == nil)
                    Text("Each chat app saves its own colors. These colors apply to solid signals, waves, pulses and the light test.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(bridge.settings.lightingArea == .completionWave
                     ? "The working color sweeps once from M1–M5 to the right, then stays on the macro keys. The approval color bounces continuously while approval is pending. The turn-ended color travels right and back once, then restores your normal effect. Brightness stays unchanged."
                     : "The turn-ended color lasts four seconds, then idle restores your previous effect. Another working chat or pending approval keeps its signal active. Macro column dims the other keys; Whole keyboard uses a solid color across all zones. Brightness stays unchanged.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    if let stage = bridge.lightingTestStage {
                        Button("Stop test") { bridge.cancelLightingTest() }
                        Text("Test: \(stage.label)").font(.callout)
                    } else {
                        Button(bridge.settings.lightingArea == .completionWave ? "Test status waves · 24 seconds" : "Test status lights · 16 seconds") { bridge.startLightingTest() }
                            .disabled(!model.running || !bridge.settings.lighting || bridge.provider != model.chatPreferences.provider)
                        Text(bridge.provider != model.chatPreferences.provider
                             ? "Choose \(bridge.provider.name) as the lighting source above to test its colors."
                             : model.running ? "Keep keyboard brightness above 0%." : "Enable mappings to test the lights.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(bridge.settings.lightingArea == .completionWave
                     ? "The test uses your colors for a working sweep, bouncing approval waves, then one turn-ended sweep and your previous effect. Live status resumes afterward; chat status is unchanged."
                     : "The test uses your colors for working → approval → turn ended → your previous effect, for four seconds each. Live status resumes afterward; chat status is unchanged.")
                    .font(.caption).foregroundStyle(.secondary)
                if !model.bluetooth.macroStatusLightingMessage.isEmpty {
                    Text(model.bluetooth.macroStatusLightingMessage).font(.caption).textSelection(.enabled)
                }
            }.padding(10)
        }
    }
    private var claudeCatalog: some View {
        DisclosureGroup("Claude session catalog") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent and starred lists use the local desktop catalog. Starred chats are shown newest first. If you use several Claude accounts, choose the account/organization folder you want here.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(bridge.settings.catalogPath ?? "Find the catalog automatically")
                    .font(.caption).textSelection(.enabled)
                HStack {
                    Button("Choose catalog folder…") {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        panel.message = "Choose the account/organization folder containing Claude's local_… session JSON files."
                        panel.directoryURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                            .appendingPathComponent("Claude/claude-code-sessions")
                        if panel.runModal() == .OK, let url = panel.url { bridge.setCatalogFolder(url) }
                    }
                    Button("Use automatic catalog") { bridge.setCatalogFolder(nil) }
                    Button("Clear observed status") { bridge.resetStatus() }
                }
                Text("If you interrupt Claude and its status stays Working, clear observed status. Claude's idle notification also clears working status when received; it never dismisses a pending approval.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 10)
        }
    }
    private func statusColorBinding(_ activity: CodexActivity) -> Binding<Color> {
        Binding(get: {
            let rgb = bridge.statusColors.color(for: activity)
            return Color(.sRGB, red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255, opacity: 1)
        }, set: { color in
            guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
            func channel(_ value: CGFloat) -> UInt8 {
                value.isFinite ? UInt8((min(1, max(0, value)) * 255).rounded()) : 0
            }
            bridge.setStatusColor(DialColor(red: channel(rgb.redComponent), green: channel(rgb.greenComponent),
                                           blue: channel(rgb.blueComponent)), for: activity)
        })
    }
}

private struct ChatSlotEditor: View {
    let slot: CodexSlot
    let provider: ChatProvider
    let activity: CodexActivity
    let save: (String, String) -> Void
    let open: () -> Void
    @State private var name = ""
    @State private var link = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Slot \(slot.id) · \(activity.label)").font(.caption)
                Spacer()
                Button("Open chat", action: open).disabled(provider.url(for: slot.threadID) == nil)
            }
            HStack {
                TextField("Label", text: $name).frame(maxWidth: 150)
                TextField(provider == .codex ? "codex://threads/…" : "claude://code/continue?session=local_…", text: $link)
                Button("Save slot") { save(name, link) }
            }
        }
        .onAppear(perform: load)
        .onChange(of: slot) { _, _ in load() }
    }
    private func load() { name = slot.name; link = provider.url(for: slot.threadID)?.absoluteString ?? "" }
}
