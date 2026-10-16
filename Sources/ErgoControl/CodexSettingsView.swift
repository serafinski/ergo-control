import SwiftUI
import AppKit
import ErgoCore

struct CodexSettingsView: View {
    @ObservedObject var model: ControlModel
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Codex").font(.largeTitle.bold())
            Text("M1–M5 open your chats. The keyboard can show their activity.").foregroundStyle(.secondary)
            Toggle("Connect to Codex", isOn: Binding(get: { model.codex.settings.enabled }, set: model.codex.setEnabled))
                .toggleStyle(.switch)
            if !model.running { Text(model.status).font(.callout).foregroundStyle(.secondary) }
            if let error = model.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if model.codex.settings.enabled {
                chatKeys
                statusLights
                DisclosureGroup("Setup and advanced options") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Status hooks report activity from Codex chats in the desktop app. Review and trust ErgoCodexHook if asked; already-approved hooks need no reinstall.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Install status hooks") { model.codex.installHooks() }
                            Button("Review hooks file") { NSWorkspace.shared.open(model.codex.hooksURL) }
                            Button("Remove status hooks") { model.codex.installHooks(remove: true) }
                        }
                        Button("Create Codex mappings profile") { model.createCodexProfile() }
                        Text("Optional: create a separate profile with five explicit chat-slot actions. Existing profiles are preserved.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 10)
                }
            }
            Text(model.codex.message).font(.callout).textSelection(.enabled)
        }
    }
    private var chatKeys: some View {
        GroupBox("Chat keys") {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Chat selection", selection: Binding(get: { model.codex.settings.selection }, set: model.codex.setSelection)) {
                    ForEach(CodexSelectionMode.allCases) { mode in
                        Text(mode == .recent ? "Most recent chats" : mode == .pinned ? "Pinned chats" : "Fixed assignments").tag(mode)
                    }
                }
                Toggle("Use unmapped M1–M5 for Codex chats", isOn: Binding(get: { model.codex.settings.useUnmappedMacroKeys }, set: model.codex.setUseUnmappedMacroKeys))
                Text("Enable mappings to use the keys. Explicit mappings and alternate-layer actions take precedence.")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                ForEach(model.codex.displaySlots) { slot in
                    if model.codex.settings.selection == .fixed {
                        CodexSlotEditor(slot: slot, activity: model.codex.activity(slot)) { name, link in
                            model.codex.assign(slot.id - 1, name: name, link: link)
                        } open: { model.codex.openSlot(slot.id) }
                    } else {
                        HStack {
                            Text("M\(slot.id)").bold().frame(width: 30, alignment: .leading)
                            Text(slot.threadID == nil ? model.codex.emptySlotLabel : slot.name).lineLimit(1)
                            Spacer()
                            Text(slot.threadID == nil ? "Unassigned" : model.codex.activity(slot).label).font(.caption).foregroundStyle(.secondary)
                            Button("Open chat") { model.codex.openSlot(slot.id) }.disabled(slot.url == nil)
                        }
                    }
                }
                if model.codex.settings.selection != .fixed {
                    HStack {
                        Text(model.codex.historyMessage.isEmpty ? "Reading Codex chats…" : model.codex.historyMessage).font(.caption)
                        Spacer()
                        Button("Refresh chats") { model.codex.refreshHistory() }
                    }
                }
                Text("\(model.codex.assignedSlotCount) of 5 keys assigned · local Codex chats only. Ordinary ChatGPT conversations are not included.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(10)
        }
    }
    private var statusLights: some View {
        GroupBox("Status lights") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Show Codex status lights", isOn: Binding(get: { model.codex.settings.lighting }, set: model.codex.setLighting))
                Picker("Signal style", selection: Binding(get: { model.codex.settings.lightingArea }, set: model.codex.setLightingArea)) {
                    ForEach(CodexLightingArea.allCases) { area in Text(area.label).tag(area) }
                }
                HStack(spacing: 18) {
                    statusKey(.working); statusKey(.attention); statusKey(.finished)
                }
                Text(model.codex.settings.lightingArea == .completionWave
                     ? "Blue sweeps once from M1–M5 to the right when work starts. Amber bounces continuously right and left while approval is pending. Green travels right and back once when the turn ends. One-shot waves restore your normal effect; brightness stays unchanged."
                     : "Green lasts four seconds, then idle restores your previous effect. Another working chat or pending approval keeps its signal active. Macro column dims the other keys; Whole keyboard uses a solid color across all zones. Brightness stays unchanged.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    if let stage = model.codex.lightingTestStage {
                        Button("Stop test") { model.codex.cancelLightingTest() }
                        Text("Test: \(stage.label)").font(.callout)
                    } else {
                        Button(model.codex.settings.lightingArea == .completionWave ? "Test status waves · 24 seconds" : "Test status lights · 16 seconds") { model.codex.startLightingTest() }
                            .disabled(!model.running || !model.codex.settings.lighting)
                        Text(model.running ? "Keep keyboard brightness above 0%." : "Enable mappings to test the lights.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(model.codex.settings.lightingArea == .completionWave
                     ? "The test shows a blue sweep, bouncing amber waves, then one green out-and-back sweep and your previous effect. Live status resumes afterward; chat status is unchanged."
                     : "The test shows blue → amber → green → your previous effect, for four seconds each. Live status resumes afterward; chat status is unchanged.")
                    .font(.caption).foregroundStyle(.secondary)
                if !model.bluetooth.macroStatusLightingMessage.isEmpty {
                    Text(model.bluetooth.macroStatusLightingMessage).font(.caption).textSelection(.enabled)
                }
            }.padding(10)
        }
    }
    private func statusKey(_ activity: CodexActivity) -> some View {
        let c = activity.color
        return Label {
            Text(activity.label).font(.caption)
        } icon: {
            Circle().fill(Color(red: Double(c.red) / 255, green: Double(c.green) / 255, blue: Double(c.blue) / 255))
                .frame(width: 9, height: 9)
        }
    }
}

private struct CodexSlotEditor: View {
    let slot: CodexSlot
    let activity: CodexActivity
    let save: (String, String) -> Void
    let open: () -> Void
    @State private var name = ""
    @State private var link = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("M\(slot.id) · \(activity.label)").font(.caption)
                Spacer()
                Button("Open chat", action: open).disabled(slot.url == nil)
            }
            HStack {
                TextField("Label", text: $name).frame(maxWidth: 150)
                TextField("codex://threads/…", text: $link)
                Button("Save slot") { save(name, link) }
            }
        }
        .onAppear(perform: load)
        .onChange(of: slot) { _, _ in load() }
    }
    private func load() { name = slot.name; link = slot.url?.absoluteString ?? "" }
}
