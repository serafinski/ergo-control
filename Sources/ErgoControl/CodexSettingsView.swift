import SwiftUI
import AppKit
import ErgoCore

struct CodexSettingsView: View {
    @ObservedObject var model: ControlModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Chat keys · M1–M5") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable chat keys", isOn: Binding(get: { model.codex.settings.enabled }, set: model.codex.setEnabled))
                    Picker("Chat source", selection: Binding(get: { model.codex.settings.source }, set: model.codex.setSource)) {
                        ForEach(ChatSource.allCases) { source in Text(source.label).tag(source) }
                    }
                    Text(model.codex.settings.source == .codex
                         ? "Follow recent Codex chats, their pinned order, or fixed assignments."
                         : "Follow saved pinned ChatGPT conversations, or choose fixed chat links. Recent chats and live status are unavailable for ChatGPT.")
                        .font(.caption).foregroundStyle(.secondary)
                    if model.codex.settings.enabled {
                        Picker("Chat selection", selection: Binding(get: { model.codex.settings.activeSelection }, set: model.codex.setSelection)) {
                            ForEach(model.codex.settings.source.selections) { mode in
                                Text(mode == .recent ? "Most recent chats" : mode == .pinned ? "Pinned chats" : "Fixed assignments").tag(mode)
                            }
                        }
                        Text("\(model.codex.assignedSlotCount) of 5 macro keys have a chat")
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle("Use unmapped M1–M5 for chats", isOn: Binding(get: { model.codex.settings.useUnmappedMacroKeys }, set: model.codex.setUseUnmappedMacroKeys))
                        Text("With mappings enabled, macro keys set to Default open their current chat slot. Your explicit mappings and alternate-layer actions take precedence.")
                            .font(.caption).foregroundStyle(.secondary)
                        if model.codex.settings.activeSelection != .fixed {
                            HStack {
                                Text(model.codex.historyMessage.isEmpty ? "Reading chats…" : model.codex.historyMessage).font(.caption)
                                Spacer()
                                Button("Refresh chats") { model.codex.refreshHistory() }
                            }
                            Text("The list refreshes automatically, including while the menu is closed. A key always opens the chat currently shown for its slot.")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(model.codex.settings.source == .codex
                                 ? "Lists local Codex chats. Ordinary ChatGPT conversations are in the ChatGPT source."
                                 : "Reads saved pin titles and links from this Mac. If pins are stale, open ChatGPT’s pinned list and refresh here. Multiple saved accounts are not combined.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if model.codex.settings.source == .codex {
                            HStack {
                                Button("Install status hooks") { model.codex.installHooks() }
                                Button("Review hooks file") { NSWorkspace.shared.open(model.codex.hooksURL) }
                                Button("Remove status hooks") { model.codex.installHooks(remove: true) }
                            }
                            Text("Review and trust ErgoCodexHook if ChatGPT asks. Once accepted, keep using the desktop app normally. Events report working, approval requested, and turn ended; they do not report unread messages or every question.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(model.codex.displaySlots) { slot in
                            if model.codex.settings.activeSelection == .fixed {
                                CodexSlotEditor(slot: slot, source: model.codex.settings.source, activity: model.codex.activity(slot)) { name, link in
                                    model.codex.assign(slot.id - 1, name: name, link: link)
                                } open: { model.codex.openSlot(slot.id) }
                            } else {
                                HStack {
                                    Text("M\(slot.id)").bold()
                                    Text(slot.threadID == nil ? model.codex.emptySlotLabel : slot.name).lineLimit(1)
                                    Spacer()
                                    Text(slot.threadID == nil ? "Unassigned" : model.codex.statusLabel(slot)).font(.caption).foregroundStyle(.secondary)
                                    Button("Open chat") { model.codex.openSlot(slot.id) }.disabled(model.codex.slotURL(slot) == nil)
                                }
                            }
                        }
                        HStack {
                            Button("Create chat mappings profile") { model.createCodexProfile() }
                            Text("Optional: replace all five actions in a separate profile. Existing profiles are preserved.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if model.codex.settings.source == .codex {
                            Toggle("Show Codex status on the macro column", isOn: Binding(get: { model.codex.settings.lighting }, set: model.codex.setLighting))
                            Text("While mappings are enabled: amber = approval, blue = working, green = turn ended, white = idle. All five macro keys share one color; the most urgent assigned chat wins. Other keys stay white. Your previous effect returns when this is switched off or mappings stop. Keep brightness above 0%.")
                                .font(.caption).foregroundStyle(.secondary)
                            if !model.bluetooth.macroStatusLightingMessage.isEmpty {
                                Text(model.bluetooth.macroStatusLightingMessage).font(.caption)
                            }
                        }
                    }
                    Text(model.codex.message).font(.callout).textSelection(.enabled)
                }.padding(8)
            }

        }
    }
}

private struct CodexSlotEditor: View {
    let slot: CodexSlot
    let source: ChatSource
    let activity: CodexActivity
    let save: (String, String) -> Void
    let open: () -> Void
    @State private var name = ""
    @State private var link = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(color).frame(width: 9, height: 9)
                Text("M\(slot.id) · \(source == .codex ? activity.label : "Status unavailable")").font(.caption)
                Spacer()
                Button("Open chat", action: open).disabled(source.url(for: slot) == nil)
            }
            HStack {
                TextField("Label", text: $name).frame(maxWidth: 150)
                TextField(source.linkPlaceholder, text: $link)
                Button("Save slot") { save(name, link) }
            }
        }
        .onAppear(perform: load)
        .onChange(of: slot) { _, _ in load() }
        .onChange(of: source) { _, _ in load() }
    }
    private func load() { name = slot.name; link = source.url(for: slot)?.absoluteString ?? "" }
    private var color: Color {
        let c = activity.color
        return Color(red: Double(c.red) / 255, green: Double(c.green) / 255, blue: Double(c.blue) / 255)
    }
}
