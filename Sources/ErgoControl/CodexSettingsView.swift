import SwiftUI
import AppKit
import ErgoCore

struct CodexSettingsView: View {
    @ObservedObject var model: ControlModel
    var body: some View {
        GroupBox("Codex · five chat slots") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Connect to Codex", isOn: Binding(get: { model.codex.settings.enabled }, set: model.codex.setEnabled))
                Text("Open assigned chats with M1–M5. Empty slots fill from the first five chats observed after hooks are installed. Slots stay in place until you edit them.")
                    .font(.caption).foregroundStyle(.secondary)
                if model.codex.settings.enabled {
                    HStack {
                        Button("Install status hooks") { model.codex.installHooks() }
                        Button("Review hooks file") { NSWorkspace.shared.open(model.codex.hooksURL) }
                        Button("Remove status hooks") { model.codex.installHooks(remove: true) }
                    }
                    Text("Review and trust ErgoCodexHook if ChatGPT asks. Once accepted, keep using the desktop app normally. Events report working, approval requested, and turn ended; they do not report unread messages or every question.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(model.codex.settings.slots) { slot in
                        CodexSlotEditor(slot: slot, activity: model.codex.activity(slot)) { name, link in
                            model.codex.assign(slot.id - 1, name: name, link: link)
                        } open: { model.codex.openSlot(slot.id) }
                    }
                    HStack {
                        Button("Create Codex mappings profile") { model.createCodexProfile() }
                        Text("Select that profile and choose Use selected as default to use M1–M5 from other apps.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Show Codex status on the macro column", isOn: Binding(get: { model.codex.settings.lighting }, set: model.codex.setLighting))
                    Text("While mappings are enabled: amber = approval, blue = working, green = turn ended, white = idle. All five macro keys share one color; the most urgent assigned chat wins. Other keys stay white. Your previous effect returns when this is switched off or mappings stop. Keep brightness above 0%.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !model.bluetooth.macroStatusLightingMessage.isEmpty {
                        Text(model.bluetooth.macroStatusLightingMessage).font(.caption)
                    }
                }
                Text(model.codex.message).font(.callout).textSelection(.enabled)
            }.padding(8)
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
                Circle().fill(color).frame(width: 9, height: 9)
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
    private var color: Color {
        let c = activity.color
        return Color(red: Double(c.red) / 255, green: Double(c.green) / 255, blue: Double(c.blue) / 255)
    }
}
